import Foundation

// MARK: - Lecturas: lo que quieres leer, lo que lees y lo que terminaste, con un objetivo anual

struct LecturasData: Equatable {
    enum Status: String, Equatable { case pending, reading, finished, dropped }

    struct Book: Identifiable, Equatable {
        var title: String
        var author: String
        var status: Status
        var started: Date?
        var finished: Date?
        /// De 1 a 5.
        var rating: Int?
        var pages: Int?
        var line: Int
        var id: Int { line }
    }

    /// Libros que se quieren terminar este año (`objetivo_anual:`); 0 si no hay.
    var goal = 0
    var books: [Book] = []

    var reading: [Book] { books.filter { $0.status == .reading } }
    var pending: [Book] { books.filter { $0.status == .pending } }

    func finished(in year: Int) -> [Book] {
        let cal = DayKey.calendar()
        return books.filter { $0.status == .finished && ($0.finished.map { cal.component(.year, from: $0) == year } ?? false) }
            .sorted { $0.finished! > $1.finished! }
    }

    func pages(in year: Int) -> Int { finished(in: year).compactMap(\.pages).reduce(0, +) }

    /// Días medios entre empezar y terminar, en los libros que tienen las dos fechas.
    var averageDays: Int? {
        let d = books.compactMap { b -> Int? in
            guard b.status == .finished, let s = b.started, let f = b.finished, f >= s else { return nil }
            return DayKey.days(from: s, to: f)
        }
        return d.isEmpty ? nil : Int((Double(d.reduce(0, +)) / Double(d.count)).rounded())
    }

    /// Libros que saldrían a fin de año al ritmo de lo que va de año; `nil` en las primeras semanas, cuando no dice nada.
    func projection(today: Date = DayKey.today()) -> Int? {
        let cal = DayKey.calendar()
        let day = cal.ordinality(of: .day, in: .year, for: today) ?? 1
        let done = finished(in: cal.component(.year, from: today)).count
        guard day >= 30, done > 0 else { return nil }
        return Int((Double(done) / Double(day) * 365).rounded())
    }
}

extension Parse {
    static func lecturas(_ text: String) -> LecturasData {
        var d = LecturasData()
        d.goal = MD.int(MD.frontmatter(text)["objetivo_anual"].flatMap(MD.number)).map { max(0, $0) } ?? 0
        func date(_ s: String) -> Date? { DayKey.date(s) ?? DayKey.dmyDate(s) }
        for t in tables(text) where t.col("titulo") != nil {
            for r in t.rows {
                let title = t.value(r, "titulo")
                guard !title.isEmpty else { continue }
                let (started, finished) = (date(t.value(r, "empezado")), date(t.value(r, "terminado")))
                let state = MD.fold(t.value(r, "estado"))
                let status: LecturasData.Status = state.contains("termin") || state.contains("leido") ? .finished
                    : state.contains("leyendo") ? .reading : state.contains("abandon") ? .dropped : state.contains("pendiente") ? .pending
                    : finished != nil ? .finished : started != nil ? .reading : .pending
                let rating = t.value(r, "nota")
                let stars = rating.filter { $0 == "⭐" || $0 == "★" }.count
                d.books.append(.init(title: title, author: t.value(r, "autor"), status: status, started: started, finished: finished,
                                     rating: stars > 0 ? min(5, stars) : MD.int(MD.number(rating)).flatMap { (1...5).contains($0) ? $0 : nil },
                                     pages: MD.int(MD.number(t.value(r, "paginas"))).flatMap { $0 > 0 ? $0 : nil }, line: r.line))
            }
        }
        return d
    }
}

extension Edit {
    static func addLibro(_ text: String, title: String, author: String, pages: Int?) -> String? {
        addRow(text, section: "Libros", cells: [title, author, "Pendiente", "", "", "", pages.map(String.init) ?? ""]
            .map { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") })
    }
}

extension Store {
    func addLibro(title: String, author: String, pages: Int?) {
        edit(VaultPath.lecturas) { Edit.addLibro($0, title: title, author: author, pages: pages) }
    }

    func startBook(_ b: LecturasData.Book, on day: Date = DayKey.today()) {
        edit(VaultPath.lecturas) { Edit.setRowValues($0, line: b.line, expectFirst: b.title, values: ["estado": "Leyendo", "empezado": DayKey.string(day), "terminado": ""]) }
    }

    /// Termina el libro hoy. Con nota (1 a 5) se apunta como estrellas.
    func finishBook(_ b: LecturasData.Book, rating: Int? = nil, on day: Date = DayKey.today()) {
        var values = ["estado": "Terminado", "terminado": DayKey.string(day)]
        if b.started == nil { values["empezado"] = DayKey.string(day) }
        if let rating { values["nota"] = String(repeating: "⭐", count: min(5, max(1, rating))) }
        edit(VaultPath.lecturas) { Edit.setRowValues($0, line: b.line, expectFirst: b.title, values: values) }
    }

    func dropBook(_ b: LecturasData.Book) {
        edit(VaultPath.lecturas) { Edit.setRowValues($0, line: b.line, expectFirst: b.title, values: ["estado": "Abandonado"]) }
    }
}
