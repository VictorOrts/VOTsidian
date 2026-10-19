import SwiftUI
import UniformTypeIdentifiers

// MARK: - Lector de Markdown con enlaces [[...]]

struct TableBlock {
    var headerLine: Int
    var header: [String]
    var rows: [(line: Int, cells: [String])]
    var lastLine: Int { rows.last?.line ?? headerLine + 1 }
}

enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String, indent: Int, mark: String, line: Int, raw: String)
    case quote(String)
    case code(String)
    case dataview
    case table(TableBlock)
    case rule
    case properties([(String, String)])
    case embed(String)
}

enum MDParser {
    static func blocks(_ text: String) -> [MDBlock] {
        var out: [MDBlock] = []
        let lines = MD.lines(text)
        var i = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            let props = lines[1..<end].compactMap { l -> (String, String)? in
                guard !l.hasPrefix(" "), !l.hasPrefix("-"), let c = l.firstIndex(of: ":") else { return nil }
                return (String(l[..<c]), String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces))
            }
            if !props.isEmpty { out.append(.properties(props)) }
            i = end + 1
        }
        while i < lines.count {
            let l = lines[i]
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                let lang = t.dropFirst(3)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { body.append(lines[i]); i += 1 }
                out.append(lang.hasPrefix("dataview") ? .dataview : .code(body.joined(separator: "\n")))
                i += 1
                continue
            }
            if MD.isTable(l) {
                let headerLine = i
                let header = MD.cells(l)
                var rows: [(line: Int, cells: [String])] = []
                i += 1
                while i < lines.count, MD.isTable(lines[i]) {
                    let c = MD.cells(lines[i])
                    if !c.allSatisfy({ $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }) { rows.append((i, c)) }
                    i += 1
                }
                out.append(.table(TableBlock(headerLine: headerLine, header: header, rows: rows)))
                continue
            }
            if t.isEmpty { i += 1; continue }
            if let m = t.firstMatch(of: /^!\[\[([^\]]+)\]\]$/) { out.append(.embed(String(m.1))); i += 1; continue }
            if t == "---" { out.append(.rule); i += 1; continue }
            if let m = t.firstMatch(of: /^(#{1,6})\s+(.*)$/) { out.append(.heading(m.1.count, String(m.2))); i += 1; continue }
            if t.hasPrefix(">") {
                var q = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let r = q.range(of: #"^\[![^\]]*\]\s*"#, options: .regularExpression) { q = String(q[r.upperBound...]) }
                out.append(.quote(q)); i += 1; continue
            }
            if let m = l.firstMatch(of: /^(\s*)(?:[-*]|\d+\.)\s+(?:\[([ xX])\]\s+)?(.*)$/) {
                let mark = m.2.map { $0 == " " ? "☐" : "☑" } ?? "•"
                out.append(.bullet(String(m.3), indent: m.1.count / 2, mark: mark, line: i, raw: l)); i += 1; continue
            }
            out.append(.paragraph(t)); i += 1
        }
        return out
    }

    /// Texto con `[[enlaces]]` convertidos a enlaces pulsables `votsidian://note/...`.
    static func inline(_ raw: String) -> AttributedString {
        var s = raw.replacingOccurrences(of: "![[", with: "[[")
        let regex = /\[\[([^\]]+)\]\]/
        s = s.replacing(regex) { m in
            let inner = String(m.1)
            var target = inner, label = inner
            if let r = inner.range(of: #"\\?\|"#, options: .regularExpression) {
                target = String(inner[..<r.lowerBound]); label = String(inner[r.upperBound...])
            }
            if let h = target.firstIndex(of: "#") { target = String(target[..<h]) }
            let enc = target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? target
            return "[\(label)](votsidian://note/\(enc))"
        }
        return (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(raw)
    }
}

enum Embed {
    /// `Nota#Sección|alias` → nombre y sección.
    static func target(_ raw: String) -> (name: String, heading: String?) {
        var t = raw
        if let r = t.range(of: #"\\?\|"#, options: .regularExpression) { t = String(t[..<r.lowerBound]) }
        var heading: String?
        if let h = t.firstIndex(of: "#") { heading = String(t[t.index(after: h)...]).trimmingCharacters(in: .whitespaces); t = String(t[..<h]) }
        return ((t as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces), heading?.isEmpty == true ? nil : heading)
    }

    static func isImage(_ name: String) -> Bool { ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains((name as NSString).pathExtension.lowercased()) }

    /// Texto que se muestra al incrustar una nota: sin cabecera, y solo la sección pedida si se indica.
    static func body(of text: String, heading: String?) -> String {
        var lines = MD.lines(text)
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { lines.removeSubrange(0...end) }
        guard let heading else { return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        let fence = MD.fenced(lines)
        func level(_ l: String) -> Int { l.prefix(while: { $0 == "#" }).count }
        guard let start = lines.indices.first(where: { !fence.contains($0) && lines[$0].hasPrefix("#") && MD.fold(lines[$0].drop(while: { $0 == "#" || $0 == " " }).description).contains(MD.fold(heading)) }) else { return "" }
        let lv = level(lines[start])
        var end = start + 1
        while end < lines.count, fence.contains(end) || !(lines[end].hasPrefix("#") && level(lines[end]) <= lv) { end += 1 }
        return lines[(start + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EmbedView: View {
    @Environment(Store.self) private var store
    let raw: String
    let depth: Int

    var body: some View {
        let (name, heading) = Embed.target(raw)
        if Embed.isImage(name) {
            if let url = store.attachmentURL(name) {
                ThumbView(url: url, size: 1000).frame(maxWidth: 520, maxHeight: 420).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label("No encuentro la imagen \(name)", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
            }
        } else if let path = store.fuzzyResolve(name) {
            let text = Embed.body(of: store.noteTexts[path] ?? store.read(path), heading: heading)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(Brand.accent)
                    Button(((path as NSString).lastPathComponent as NSString).deletingPathExtension + (heading.map { " › \($0)" } ?? "")) { store.pendingNote = path }
                        .buttonStyle(.link).font(.caption.weight(.semibold))
                }
                if depth >= 2 { Text("(contenido anidado: ábrela para verla)").font(.caption).foregroundStyle(.secondary) }
                else if text.isEmpty { Text(heading == nil ? "Nota vacía." : "No encuentro la sección «\(heading!)».").font(.caption).foregroundStyle(.secondary) }
                else { NoteBody(text: text, actions: NoteActions(toggle: { _, _ in }, editRow: { _ in }, addRow: { _ in }, setProperty: { _, _ in }), depth: depth + 1) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Brand.accent).frame(width: 3).padding(.vertical, 6) }
        } else {
            Label("No encuentro la nota «\(name)»", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Brand.warn)
        }
    }
}

struct NoteActions {
    var toggle: (Int, String) -> Void
    var editRow: (Int) -> Void
    var addRow: (TableBlock) -> Void
    var setProperty: (String, String) -> Void
}

struct NoteBody: View {
    let text: String
    let actions: NoteActions
    var depth = 0

    var body: some View {
        let blocks = MDParser.blocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in render(b) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func render(_ b: MDBlock) -> some View {
        switch b {
        case .heading(let level, let t):
            Text(MDParser.inline(t)).font(.system(size: [26, 21, 17, 15, 14, 13][min(level, 6) - 1], weight: .bold, design: .rounded)).padding(.top, level <= 2 ? 8 : 2)
        case .paragraph(let t): Text(MDParser.inline(t)).textSelection(.enabled)
        case .bullet(let t, let indent, let mark, let line, let raw):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if mark == "•" { Text(mark).foregroundStyle(.secondary) }
                else {
                    Button { actions.toggle(line, raw) } label: { Text(mark).foregroundStyle(mark == "☑" ? Brand.accent : .secondary) }
                        .buttonStyle(.plain).help("Marcar o desmarcar")
                }
                Text(MDParser.inline(t)).strikethrough(mark == "☑").foregroundStyle(mark == "☑" ? .secondary : .primary).textSelection(.enabled)
            }.padding(.leading, CGFloat(indent) * 18)
        case .quote(let t):
            Text(MDParser.inline(t)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        case .code(let t):
            Text(t).font(.system(size: 12, design: .monospaced)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8)).textSelection(.enabled)
        case .embed(let raw): EmbedView(raw: raw, depth: depth)
        case .dataview: EmptyView()   // consultas de Obsidian: la app muestra esos datos en sus pantallas
        case .table(let tb):
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
                        GridRow {
                            ForEach(Array(tb.header.enumerated()), id: \.offset) { _, c in Text(MDParser.inline(c)).fontWeight(.semibold).foregroundStyle(.secondary) }
                            Color.clear.frame(width: 18, height: 1)
                        }
                        Divider()
                        ForEach(Array(tb.rows.enumerated()), id: \.offset) { _, r in
                            GridRow {
                                ForEach(0..<tb.header.count, id: \.self) { i in Text(MDParser.inline(i < r.cells.count ? r.cells[i] : "")).frame(maxWidth: 380, alignment: .leading) }
                                EditButton { actions.editRow(r.line) }
                            }
                        }
                    }.padding(10)
                }
                Button { actions.addRow(tb) } label: { Label("Añadir fila", systemImage: "plus") }.buttonStyle(.borderless).font(.caption).padding(.leading, 10)
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        case .rule: Divider()
        case .properties(let p):
            DisclosureGroup("Propiedades") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(p.enumerated()), id: \.offset) { _, kv in
                        PropertyRow(key: kv.0, value: kv.1, set: actions.setProperty)
                    }
                }.padding(.top, 4)
            }.font(.caption)
        }
    }
}

struct PropertyRow: View {
    let key: String
    let value: String
    let set: (String, String) -> Void
    @State private var text = ""

    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            TextField("", text: $text).onSubmit { if text != value { set(key, text) } }
        }
        .font(.callout)
        .onAppear { text = value }
        .onChange(of: value) { text = value }
    }
}
