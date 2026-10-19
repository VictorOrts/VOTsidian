import Foundation

// MARK: - Casa

struct TableRow: Identifiable, Equatable {
    var line: Int
    var cells: [String]
    var id: Int { line }
}

struct SectionTable: Equatable {
    var title: String
    var header: [String] = []
    var rows: [TableRow] = []

    func col(_ name: String) -> Int? { header.firstIndex { MD.fold($0) == MD.fold(name) } }
    func value(_ row: TableRow, _ name: String) -> String { col(name).flatMap { $0 < row.cells.count ? row.cells[$0] : nil } ?? "" }
}

struct CasaData: Equatable {
    var reformas = SectionTable(title: "Reformas")
    var compras = SectionTable(title: "Compras")
    var electros = SectionTable(title: "Electrodomésticos")
    var small = SectionTable(title: "Pequeños electrodomésticos")
}

enum Money {
    /// Igual que la nota Casa: quita €, usa coma decimal y punto de millares.
    static func parse(_ s: String) -> Double {
        var t = s.replacingOccurrences(of: "€", with: "").filter { !$0.isWhitespace }
        if t.isEmpty { return 0 }
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else if t.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil { t = t.replacingOccurrences(of: ".", with: "") }
        return Double(t) ?? 0
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "es_ES")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v)) €"
    }
}

extension Parse {
    static func sectionTable(_ text: String, title: String) -> SectionTable {
        var t = SectionTable(title: title)
        let lines = MD.lines(text)
        guard let range = MD.section(lines, containing: title) else { return t }
        let rows = MD.tableRows(Array(lines)).filter { range.contains($0.index) }
        guard let head = rows.first else { return t }
        t.header = head.cells
        for r in rows.dropFirst() {
            if r.cells.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil || $0.isEmpty }) && r.cells.contains(where: { !$0.isEmpty }) { continue }
            t.rows.append(TableRow(line: r.index, cells: r.cells))
        }
        return t
    }

    static func casa(_ text: String) -> CasaData {
        CasaData(reformas: sectionTable(text, title: "Reformas"), compras: sectionTable(text, title: "Compras"),
                 electros: sectionTable(text, title: "Electrodomésticos"), small: sectionTable(text, title: "Pequeños electrodomésticos"))
    }
}

// MARK: - Enlaces entre notas

enum Links {
    /// Nombres de nota enlazados con `[[Nota]]`, `[[Nota|alias]]` o `[[Nota#sección]]`, fuera de bloques de código.
    static func extract(_ text: String) -> [String] {
        let lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var out: [String] = []
        for (i, l) in lines.enumerated() where !fence.contains(i) {
            for m in l.matches(of: /\[\[([^\]]+)\]\]/) {
                var name = String(m.1)
                if let r = name.range(of: #"\\?\|"#, options: .regularExpression) { name = String(name[..<r.lowerBound]) }
                if let h = name.firstIndex(of: "#") { name = String(name[..<h]) }
                name = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { out.append(name) }
            }
        }
        return out
    }
}

enum GraphLayout {
    /// Disposición de fuerzas (Fruchterman-Reingold). Devuelve posiciones en [0,1]².
    static func compute(count n: Int, edges: [(Int, Int)], iterations: Int = 320) -> [CGPoint] {
        guard n > 0 else { return [] }
        if n == 1 { return [CGPoint(x: 0.5, y: 0.5)] }
        var pos = (0..<n).map { i -> CGPoint in
            let angle = 2 * Double.pi * Double(i) / Double(n)
            let jitter = abs(sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let r = 0.3 + 0.15 * jitter
            return CGPoint(x: 0.5 + r * cos(angle), y: 0.5 + r * sin(angle))
        }
        let k = 0.9 * (1.0 / Double(n)).squareRoot()
        var temp = 0.1
        for _ in 0..<iterations {
            var disp = [CGVector](repeating: .zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    let d = max((dx * dx + dy * dy).squareRoot(), 0.001)
                    let f = k * k / d
                    disp[i].dx += dx / d * f; disp[i].dy += dy / d * f
                    disp[j].dx -= dx / d * f; disp[j].dy -= dy / d * f
                }
            }
            for (a, b) in edges where a != b {
                let dx = pos[a].x - pos[b].x, dy = pos[a].y - pos[b].y
                let d = max((dx * dx + dy * dy).squareRoot(), 0.001)
                let f = d * d / k
                disp[a].dx -= dx / d * f; disp[a].dy -= dy / d * f
                disp[b].dx += dx / d * f; disp[b].dy += dy / d * f
            }
            for i in 0..<n {
                disp[i].dx -= (pos[i].x - 0.5) * k * 2
                disp[i].dy -= (pos[i].y - 0.5) * k * 2
                let len = max((disp[i].dx * disp[i].dx + disp[i].dy * disp[i].dy).squareRoot(), 0.0001)
                let step = min(len, temp)
                pos[i].x += disp[i].dx / len * step
                pos[i].y += disp[i].dy / len * step
            }
            temp *= 0.985
        }
        let xs = pos.map(\.x), ys = pos.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let span = max(maxX - minX, maxY - minY, 0.0001)
        return pos.map { CGPoint(x: 0.5 + ($0.x - (minX + maxX) / 2) / span * 0.9, y: 0.5 + ($0.y - (minY + maxY) / 2) / span * 0.9) }
    }
}
