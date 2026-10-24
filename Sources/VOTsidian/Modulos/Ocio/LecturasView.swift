import SwiftUI

struct LecturasView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.lecturas
    @State private var title = ""
    @State private var author = ""
    @State private var pages = ""

    var body: some View {
        let _ = BodyCounter.hit("LecturasView")
        let l = store.lecturas
        let today = DayKey.today()
        let year = DayKey.calendar().component(.year, from: today)
        let done = l.finished(in: year)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .lecturas)
                HStack(spacing: 12) {
                    Tile(title: "Este año", value: l.goal > 0 ? "\(done.count) de \(l.goal)" : "\(done.count)",
                         note: l.goal > 0 ? l.projection(today: today).map { "al ritmo de ahora, \(plural($0, "libro", "libros")) a fin de año" } : "pon «objetivo_anual» en la nota para fijar uno",
                         tint: l.goal > 0 && done.count >= l.goal ? Brand.accent : nil)
                    Tile(title: "Leyendo", value: "\(l.reading.count)")
                    Tile(title: "Pendientes", value: "\(l.pending.count)")
                    Tile(title: "Páginas", value: l.pages(in: year) > 0 ? l.pages(in: year).formatted() : "–", note: l.averageDays.map { "\(plural($0, "día", "días")) por libro" })
                }
                if l.goal > 0 {
                    ProgressView(value: Double(min(done.count, l.goal)), total: Double(l.goal)) {
                        Text("Objetivo de \(year): \(done.count) de \(plural(l.goal, "libro", "libros"))").font(.caption).foregroundStyle(.secondary)
                    }.tint(Brand.accent)
                }
                Card(title: "Leyendo", icon: "book") {
                    if l.reading.isEmpty { EmptyNote("Nada en marcha. Empieza uno de los pendientes.", icon: "book") }
                    ForEach(l.reading) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.title).fontWeight(.medium)
                                Text([b.author, b.started.map { "desde hace \(plural(DayKey.days(from: $0, to: today), "día", "días"))" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu("Terminar") {
                                Button("Sin nota") { store.finishBook(b) }
                                ForEach(1...5, id: \.self) { n in Button(String(repeating: "⭐", count: n)) { store.finishBook(b, rating: n) } }
                            }.menuStyle(.borderedButton).fixedSize()
                            Button("Abandonar") { store.dropBook(b) }.controlSize(.small)
                        }
                    }
                }
                Card(title: "Pendientes", icon: "books.vertical") {
                    if l.pending.isEmpty { EmptyNote("Añade libros a tu lista abajo.", icon: "books.vertical") }
                    ForEach(l.pending) { b in
                        HStack {
                            Text(b.title)
                            if !b.author.isEmpty { Text(b.author).foregroundStyle(.secondary) }
                            Spacer()
                            if let p = b.pages { Text("\(p) pág.").font(.callout).foregroundStyle(.secondary) }
                            Button("Empezar") { store.startBook(b) }.controlSize(.small)
                        }
                    }
                }
                Card(title: "Añadir libro", icon: "plus.circle") {
                    HStack {
                        TextField("Título", text: $title).onSubmit(add)
                        TextField("Autor", text: $author)
                        TextField("Páginas", text: $pages).frame(width: 80)
                        Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Card(title: "Terminados en \(year)", icon: "checkmark.seal") {
                    if done.isEmpty { EmptyNote("Aún no has terminado ninguno este año.", icon: "checkmark.seal") }
                    ForEach(done) { b in
                        HStack {
                            Text(b.title).fontWeight(.medium)
                            if !b.author.isEmpty { Text(b.author).foregroundStyle(.secondary) }
                            Spacer()
                            if let r = b.rating { Text(String(repeating: "⭐", count: r)).accessibilityLabel("\(r) de 5") }
                            Text(b.finished.map(DayKey.dmy) ?? "").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                NoteTables(file: file, icon: "tablecells")
                Button("Abrir la nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Lecturas")
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addLibro(title: t, author: author.trimmingCharacters(in: .whitespaces), pages: MD.int(MD.number(pages)).flatMap { $0 > 0 ? $0 : nil })
        title = ""; author = ""; pages = ""
    }
}
