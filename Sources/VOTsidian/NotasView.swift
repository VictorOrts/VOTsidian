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

// MARK: - Pantalla

struct NotasView: View {
    enum Mode: String { case leer = "Leer", editar = "Editar" }
    enum Sort: String, CaseIterable, Identifiable {
        case carpeta = "Por carpeta", reciente = "Más recientes", nombre = "Por nombre"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @State private var selected: String?
    @State private var back: [String] = []
    @State private var forward: [String] = []
    @State private var search = ""
    @State private var tag: String?
    @State private var mode: Mode = ProcessInfo.processInfo.environment["VOT_EDIT"] != nil ? .editar : .leer
    @State private var draft = ""
    @State private var baseline = ""
    @State private var conflict = false
    @State private var showNew = false
    @State private var showRename = false
    @State private var confirmDelete = false
    @State private var rowSpec: RowSpec?
    @State private var savedFlash = false
    @State private var focusMode = false
    @State private var mentions: [NoteFile] = []
    @State private var textSelection: TextSelection?
    @State private var tabs: [String] = []
    @State private var suggestIndex = 0
    @State private var suggestDismissed = false
    @AppStorage("recentNotes") private var recentRaw = ""
    @AppStorage("openTabs") private var tabsRaw = ""
    @AppStorage("activeTab") private var activeRaw = ""
    @AppStorage("noteSort") private var sortRaw = Sort.carpeta.rawValue

    private var sort: Sort { Sort(rawValue: sortRaw) ?? .carpeta }
    private var dirty: Bool { selected != nil && draft != baseline }
    private func name(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    private var filtered: [NoteFile] {
        var list = store.notes
        if let tag { let set = store.notes(withTag: tag); list = list.filter { set.contains($0.path) } }
        if !search.isEmpty {
            let q = MD.fold(search)
            list = list.filter { MD.fold($0.path).contains(q) || MD.fold(store.snippets[$0.path] ?? "").contains(q) }
        }
        switch sort {
        case .reciente: return list.sorted { (store.modified[$0.path] ?? .distantPast) > (store.modified[$1.path] ?? .distantPast) }
        case .nombre: return list.sorted { MD.fold($0.name) < MD.fold($1.name) }
        case .carpeta: return list
        }
    }

    // MARK: Navegación y guardado

    /// Abre una nota. Por defecto reemplaza la pestaña activa; con `newTab` abre otra. Si ya está abierta, salta a su pestaña.
    private func go(_ path: String, newTab: Bool = false) {
        guard path != selected else { return }
        guard saveIfDirty() else { return }
        if let s = selected { back.append(s); forward = [] }
        tabs = TabLogic.open(tabs, active: selected, path: path, newTab: newTab)
        open(path)
    }

    private func closeTab(_ path: String) {
        if path == selected { _ = saveIfDirty() }
        let r = TabLogic.close(tabs, active: selected, path: path)
        tabs = r.tabs
        if path == selected {
            if let next = r.active { open(next) } else { selected = nil; draft = ""; baseline = "" }
        }
    }

    private func switchTab(_ delta: Int) {
        guard tabs.count > 1, saveIfDirty(), let next = TabLogic.cycle(tabs, active: selected, by: delta), next != selected else { return }
        open(next)
    }

    private func restoreTabs() {
        guard tabs.isEmpty else { return }
        let saved = tabsRaw.split(separator: "\n").map(String.init).filter { p in store.notes.contains { $0.path == p } }
        guard !saved.isEmpty else { return }
        tabs = saved
        if store.pendingNote == nil { open(saved.contains(activeRaw) ? activeRaw : saved[0]) }
    }

    private var recent: [String] {
        recentRaw.split(separator: "\n").map(String.init).filter { p in store.notes.contains { $0.path == p } }
    }

    private func open(_ path: String) {
        var r = recent.filter { $0 != path }
        r.insert(path, at: 0)
        recentRaw = r.prefix(6).joined(separator: "\n")
        selected = path
        draft = store.read(path)
        baseline = draft
        conflict = false
        textSelection = nil
    }

    @discardableResult
    private func saveIfDirty() -> Bool {
        guard dirty, let path = selected else { return true }
        return save(path, force: false)
    }

    @discardableResult
    private func save(_ path: String, force: Bool) -> Bool {
        if !force, store.readOptional(path) != baseline { conflict = true; return false }
        guard store.writeNote(path, text: draft) else { return false }
        baseline = draft
        conflict = false
        return true
    }

    /// Guarda en silencio 1,5 s después de dejar de escribir. Si la nota cambió fuera de la app, avisa en vez de pisarla.
    private func autosaveNote() {
        guard dirty, !conflict, let p = selected else { return }
        if store.readOptional(p) != baseline { conflict = true; return }
        if store.writeNote(p, text: draft, quiet: true) {
            baseline = draft
            savedFlash = true
            Task { try? await Task.sleep(for: .seconds(2)); savedFlash = false }
        }
    }

    private func consumePending() {
        if let p = store.pendingNote { go(p); store.pendingNote = nil }
    }

    // MARK: Cuerpo

    var body: some View {
        HStack(spacing: 0) {
            if !focusMode {
                listPanel.frame(width: 290)
                Divider()
            }
            content
        }
        .navigationTitle("Notas")
        .onAppear { restoreTabs(); consumePending() }
        .onChange(of: tabs) { tabsRaw = tabs.joined(separator: "\n") }
        .onChange(of: selected) { activeRaw = selected ?? "" }
        .onDisappear { saveIfDirty() }
        .autosave(on: draft) { autosaveNote() }
        .onChange(of: store.pendingNote) { consumePending() }
        .onChange(of: store.revision) {
            if let p = selected, !dirty { let disk = store.read(p); draft = disk; baseline = disk }
        }
        .task(id: "\(selected ?? "")-\(store.revision)") {
            if let p = selected, mode == .leer { mentions = store.unlinkedMentions(of: p) } else { mentions = [] }
        }
        .sheet(item: $rowSpec) { RowSheet(spec: $0) }
        .sheet(isPresented: $showNew) {
            NewNoteSheet(folders: Array(Set(store.notes.map(\.folder).filter { $0 != "Raíz" })).sorted()) { path in
                if saveIfDirty() { if let s = selected { back.append(s) }; if !tabs.contains(path) { tabs.append(path) }; open(path); mode = .editar }
            }
        }
        .sheet(isPresented: $showRename) {
            if let p = selected {
                RenameSheet(current: name(p)) { newName in
                    if saveIfDirty(), let np = store.renameNote(p, to: newName) { tabs = tabs.map { $0 == p ? np : $0 }; selected = np; open(np) }
                }
            }
        }
    }

    // MARK: Lista de notas (estilo Bear)

    private var listPanel: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Buscar nota", text: $search)
                Button { showNew = true } label: { Image(systemName: "square.and.pencil").accessibilityLabel("Nueva nota") }.help("Nueva nota")
            }.padding([.horizontal, .top], 10)
            HStack(spacing: 6) {
                Menu {
                    ForEach(Sort.allCases) { s in Button(s.rawValue) { sortRaw = s.rawValue } }
                } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Button("Todas las etiquetas") { tag = nil }
                    Divider()
                    ForEach(store.allTags, id: \.tag) { t in Button("#\(t.tag) (\(t.count))") { tag = t.tag } }
                } label: { Label(tag.map { "#\($0)" } ?? "Etiquetas", systemImage: "number") }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                if tag != nil { Button { tag = nil } label: { Image(systemName: "xmark.circle.fill").accessibilityLabel("Quitar filtro") }.buttonStyle(.borderless).foregroundStyle(.secondary) }
            }.font(.caption).padding(.horizontal, 10)
            List(selection: Binding(get: { selected }, set: { if let p = $0 { go(p) } })) {
                if search.isEmpty, tag == nil {
                    let pins = store.pinned.filter { p in store.notes.contains { $0.path == p } }
                    if !pins.isEmpty { Section("Fijadas") { ForEach(pins, id: \.self) { row($0) } } }
                    if !recent.isEmpty, sort == .carpeta { Section("Recientes") { ForEach(recent, id: \.self) { row($0) } } }
                }
                if sort == .carpeta {
                    ForEach(Dictionary(grouping: filtered, by: \.folder).keys.sorted(), id: \.self) { folder in
                        Section(folder) { ForEach(filtered.filter { $0.folder == folder }) { row($0.path) } }
                    }
                } else {
                    ForEach(filtered) { row($0.path) }
                }
            }
        }
    }

    private func row(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name(path)).fontWeight(.medium).lineLimit(1)
                if store.pinned.contains(path) { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Brand.accent) }
                Spacer()
                if let d = store.modified[path] { Text(shortDate(d)).font(.caption2).foregroundStyle(.tertiary) }
            }
            if let s = store.snippets[path], !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .tag(path)
        .contextMenu {
            Button("Abrir en pestaña nueva") { go(path, newTab: true) }
            Button(store.pinned.contains(path) ? "Desfijar" : "Fijar arriba") { store.togglePin(path) }
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(path)]) }
        }
    }

    // MARK: Contenido

    @ViewBuilder private var content: some View {
        if let path = selected {
            VStack(alignment: .leading, spacing: 0) {
                tabBar
                toolbar(path)
                Divider()
                if conflict {
                    HStack {
                        Label("Esta nota cambió fuera de la app mientras la editabas.", systemImage: "exclamationmark.triangle.fill")
                        Spacer()
                        Button("Sobrescribir con lo mío") { save(path, force: true) }
                        Button("Descartar lo mío") { let d = store.read(path); draft = d; baseline = d; conflict = false }
                    }.padding(10).background(Color.orange.opacity(0.25))
                }
                if mode == .editar {
                    formatBar
                    editor
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            tagChips(path)
                            NoteBody(text: store.read(path), actions: actions(path)).id("\(path)-\(store.revision)")
                            linksPanel(path)
                        }
                        .padding(24).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                    }
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "votsidian", let target = url.lastPathComponent.removingPercentEncoding else { return .systemAction }
                        if let p = store.fuzzyResolve(target) { go(p, newTab: NSEvent.modifierFlags.contains(.command)); return .handled }
                        return store.open(link: url)
                    })
                }
            }
        } else {
            ContentUnavailableView("Elige una nota", systemImage: "doc.text",
                                   description: Text("Pulsa el lápiz de arriba para crear una nueva. Los enlaces [[así]] se pueden pulsar."))
        }
    }

    // MARK: Autocompletado ([[ y #)

    private var caretOffset: Int? {
        guard let sel = textSelection, case .selection(let r) = sel.indices, r.isEmpty, r.lowerBound <= draft.endIndex else { return nil }
        return draft.distance(from: draft.startIndex, to: r.lowerBound)
    }

    private var completion: EditorCompletion.Match? {
        guard mode == .editar, !suggestDismissed, let c = caretOffset else { return nil }
        return EditorCompletion.detect(draft, caret: c)
    }

    private var suggestions: [EditorCompletion.Suggestion] {
        guard let m = completion else { return [] }
        switch m.kind {
        case .link:
            return EditorCompletion.noteSuggestions(query: m.query,
                                                    notes: store.notes.map { (name: $0.name, folder: $0.folder, aliases: []) },
                                                    current: selected.map(name) ?? "", recent: recent.map(name))
        case .tag:
            return EditorCompletion.tagSuggestions(query: m.query, tags: store.allTags)
        }
    }

    private func accept(_ s: EditorCompletion.Suggestion) {
        guard let m = completion else { return }
        if let create = s.create {
            let folder = selected.map { ($0 as NSString).deletingLastPathComponent } ?? ""
            _ = store.createNote(folder: folder, name: create, template: "En blanco")
        }
        apply(EditorOps.accept(draft, match: m, insert: s.insert))
        suggestIndex = 0
    }

    @ViewBuilder private var editor: some View {
        let list = suggestions
        TextEditor(text: $draft, selection: $textSelection)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(.quaternary.opacity(0.2))
            .onChange(of: draft) { suggestDismissed = false; suggestIndex = 0 }
            .onKeyPress(.downArrow) { guard !list.isEmpty else { return .ignored }; suggestIndex = min(suggestIndex + 1, list.count - 1); return .handled }
            .onKeyPress(.upArrow) { guard !list.isEmpty else { return .ignored }; suggestIndex = max(suggestIndex - 1, 0); return .handled }
            .onKeyPress(.return) { guard list.indices.contains(suggestIndex) else { return .ignored }; accept(list[suggestIndex]); return .handled }
            .onKeyPress(.tab) { guard list.indices.contains(suggestIndex) else { return .ignored }; accept(list[suggestIndex]); return .handled }
            .onKeyPress(.escape) { guard !list.isEmpty else { return .ignored }; suggestDismissed = true; return .handled }
            .overlay(alignment: .topTrailing) {
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, sug in
                            Button { accept(sug) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: sug.create != nil ? "plus.circle" : (completion?.kind == .tag ? "number" : "doc.text")).foregroundStyle(Brand.accent).frame(width: 18)
                                    Text(sug.title).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(sug.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(i == suggestIndex ? Brand.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        Text("↑↓ elegir · ⏎ o ⇥ insertar · esc cerrar").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 8).padding(.top, 2)
                    }
                    .padding(6).frame(width: 330)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    .shadow(radius: 10, y: 3).padding(12)
                }
            }
    }

    @ViewBuilder private func tagChips(_ path: String) -> some View {
        let tags = store.noteTags[path] ?? []
        if !tags.isEmpty {
            FlowRow(tags, minimum: 64) { t in
                Button("#\(t)") { tag = t; focusMode = false }.buttonStyle(.bordered).controlSize(.small).tint(Brand.accent)
            }
        }
    }

    private func actions(_ path: String) -> NoteActions {
        NoteActions(
            toggle: { store.toggleLine(path, line: $0, raw: $1) },
            editRow: { rowSpec = RowSpec(file: path, mode: .edit(line: $0), title: "fila") },
            addRow: { rowSpec = RowSpec(file: path, mode: .add(afterLine: $0.lastLine, headerLine: $0.headerLine), title: "tabla") },
            setProperty: { store.setProperty(path, key: $0, value: $1) })
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(tabs, id: \.self) { t in
                        let active = t == selected
                        HStack(spacing: 6) {
                            Text(name(t)).lineLimit(1).font(.callout.weight(active ? .semibold : .regular))
                            if active, dirty { Circle().fill(Brand.warn).frame(width: 6, height: 6) }
                            Button { closeTab(t) } label: { Image(systemName: "xmark").accessibilityLabel("Cerrar pestaña").font(.system(size: 9, weight: .bold)) }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Cerrar pestaña (⌘W)")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: 190)
                        .background(active ? Brand.accent.opacity(0.2) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                        .onTapGesture { if saveIfDirty() { open(t) } }
                        .contextMenu {
                            Button("Cerrar pestaña") { closeTab(t) }
                            Button("Cerrar las demás") { for o in tabs where o != t { closeTab(o) } }
                            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(t)]) }
                        }
                    }
                }.padding(.horizontal, 10)
            }.scrollIndicators(.never)
            Button { showNew = true } label: { Image(systemName: "plus").accessibilityLabel("Nueva pestaña") }.buttonStyle(.borderless).help("Nueva nota en otra pestaña (⌘T)").padding(.trailing, 10)
            // atajos de pestañas
            Group {
                Button("") { if let s = selected { closeTab(s) } }.keyboardShortcut("w", modifiers: .command)
                Button("") { showNew = true }.keyboardShortcut("t", modifiers: .command)
                Button("") { switchTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("") { switchTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            }.opacity(0).frame(width: 0, height: 0)
        }
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.25))
    }

    private func toolbar(_ path: String) -> some View {
        let text = mode == .editar ? draft : store.read(path)
        let words = NoteInfo.wordCount(text)
        return HStack(spacing: 10) {
            Button { if let p = back.popLast(), saveIfDirty() { if let s = selected { forward.append(s) }; open(p) } } label: { Image(systemName: "chevron.left").accessibilityLabel("Anterior") }.disabled(back.isEmpty)
            Button { if let p = forward.popLast(), saveIfDirty() { if let s = selected { back.append(s) }; open(p) } } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }.disabled(forward.isEmpty)
            Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            if dirty { Circle().fill(Brand.warn).frame(width: 8, height: 8).help("Cambios sin guardar: se guardan solos en un momento") }
            else if savedFlash { Label("Guardado", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Brand.accent) }
            Spacer()
            Text("\(words) palabras · \(max(1, words / 200)) min").font(.caption).foregroundStyle(.tertiary)
            Button { store.togglePin(path) } label: { Image(systemName: store.pinned.contains(path) ? "pin.fill" : "pin").accessibilityLabel(store.pinned.contains(path) ? "Desfijar nota" : "Fijar nota") }
                .buttonStyle(.borderless).foregroundStyle(store.pinned.contains(path) ? Brand.accent : .secondary).help("Fijar arriba")
            Button { focusMode.toggle() } label: { Image(systemName: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").accessibilityLabel(focusMode ? "Salir del modo concentración" : "Modo concentración") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Modo enfoque (⌃⌘F)").keyboardShortcut("f", modifiers: [.control, .command])
            Picker("", selection: Binding(get: { mode }, set: { new in if new == .leer { _ = saveIfDirty() }; mode = new })) {
                Text("Leer").tag(Mode.leer); Text("Editar").tag(Mode.editar)
            }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
            Button("Guardar") { save(path, force: false) }.keyboardShortcut("s", modifiers: .command).disabled(!dirty)
            Menu {
                Button("Renombrar…") { showRename = true }
                Button("Copiar como Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.read(path), forType: .string) }
                Button("Exportar a PDF…") { exportPDF(path) }
                Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(path)]) }
                Divider()
                if confirmDelete {
                    Button("Confirmar: mover a la papelera", role: .destructive) { let p = path; tabs.removeAll { $0 == p }; store.trashNote(p); confirmDelete = false; if let n = tabs.last { open(n) } else { selected = nil } }
                } else {
                    Button("Mover a la papelera…", role: .destructive) { confirmDelete = true }
                }
            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Más acciones") }.menuStyle(.borderlessButton).frame(width: 30)
        }.padding(12)
    }

    // MARK: Barra de formato

    private var formatBar: some View {
        HStack(spacing: 4) {
            fmtButton("bold", "Negrita") { wrap("**", "**") }
            fmtButton("italic", "Cursiva") { wrap("*", "*") }
            fmtButton("strikethrough", "Tachado") { wrap("~~", "~~") }
            fmtButton("chevron.left.forwardslash.chevron.right", "Código") { wrap("`", "`") }
            Divider().frame(height: 16)
            fmtButton("textformat.size", "Título") { linePrefix("## ") }
            fmtButton("list.bullet", "Lista") { linePrefix("- ") }
            fmtButton("checklist", "Tarea") { linePrefix("- [ ] ") }
            fmtButton("text.quote", "Cita") { linePrefix("> ") }
            Divider().frame(height: 16)
            Menu {
                ForEach(store.notes.sorted { MD.fold($0.name) < MD.fold($1.name) }) { n in Button(n.name) { insertText("[[\(n.name)]]") } }
            } label: { Image(systemName: "link").accessibilityLabel("Insertar enlace a una nota") }.menuStyle(.borderlessButton).fixedSize().help("Insertar enlace a una nota")
            Menu {
                ForEach(store.notes.sorted { MD.fold($0.name) < MD.fold($1.name) }) { n in Button(n.name) { insertText("\n![[\(n.name)]]\n") } }
            } label: { Image(systemName: "rectangle.on.rectangle").accessibilityLabel("Incrustar otra nota") }.menuStyle(.borderlessButton).fixedSize().help("Mostrar aquí el contenido de otra nota (![[nota]])")
            fmtButton("calendar", "Insertar fecha de hoy") { insertText(DayKey.string(DayKey.today())) }
            Spacer()
            Text("Markdown: **negrita**, *cursiva*, [[enlace]], #etiqueta").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.quaternary.opacity(0.25))
    }

    private func fmtButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 22, height: 20).accessibilityLabel(help) }.buttonStyle(.borderless).help(help)
    }

    private var selectionRange: Range<Int>? {
        guard let sel = textSelection, case .selection(let r) = sel.indices, r.lowerBound <= draft.endIndex, r.upperBound <= draft.endIndex else { return nil }
        return draft.distance(from: draft.startIndex, to: r.lowerBound)..<draft.distance(from: draft.startIndex, to: r.upperBound)
    }

    private func apply(_ r: EditorOps.Result) {
        draft = r.text
        textSelection = TextSelection(insertionPoint: draft.index(draft.startIndex, offsetBy: min(r.caret, draft.count)))
    }

    /// Rodea la selección (o inserta el par vacío con el cursor en medio).
    private func wrap(_ pre: String, _ post: String) { apply(EditorOps.wrap(draft, selection: selectionRange, pre: pre, post: post)) }

    private func insertText(_ t: String) { apply(EditorOps.insert(draft, selection: selectionRange, t)) }

    /// Pone o quita un prefijo al principio de la línea donde está el cursor.
    private func linePrefix(_ prefix: String) { apply(EditorOps.linePrefix(draft, caret: selectionRange?.lowerBound, prefix: prefix)) }

    // MARK: Enlaces, menciones y exportación

    private func linksPanel(_ path: String) -> some View {
        let outgoing = store.outLinks[path] ?? []
        let incoming = store.backLinks[path] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            linkRow("Enlaza a (\(outgoing.count))", outgoing)
            linkRow("Enlazada desde (\(incoming.count))", incoming)
            if !mentions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menciones sin enlazar (\(mentions.count))").font(.subheadline.weight(.semibold))
                    Text("Estas notas nombran «\(name(path))» sin enlace. Enlázalas para conectarlas.").font(.caption).foregroundStyle(.secondary)
                    ForEach(mentions.prefix(8)) { m in
                        HStack {
                            Button(m.name) { go(m.path) }.buttonStyle(.link)
                            if let s = store.snippets[m.path] { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            Button("Enlazar") { store.linkMention(in: m.path, to: name(path)) }.controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func linkRow(_ title: String, _ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if paths.isEmpty { Text("Ninguna").font(.callout).foregroundStyle(.secondary) }
            else { FlowRow(paths) { p in Button(name(p)) { go(p) }.buttonStyle(.bordered).controlSize(.small) } }
        }
    }

    @MainActor private func exportPDF(_ path: String) {
        let noop = NoteActions(toggle: { _, _ in }, editRow: { _ in }, addRow: { _ in }, setProperty: { _, _ in })
        let view = NoteBody(text: store.read(path), actions: noop).frame(width: 640).padding(36)
            .background(Color.white).environment(\.colorScheme, .light).foregroundStyle(Color.black)
        let renderer = ImageRenderer(content: view)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name(path) + ".pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        NSWorkspace.shared.open(url)
    }
}

struct NewNoteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folders: [String]
    var template0 = "En blanco"
    var folder0 = ""
    let created: (String) -> Void
    @State private var name = ""
    @State private var folder = ""
    @State private var template = "En blanco"
    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nueva nota").font(.title3.weight(.semibold))
            TextField("Nombre", text: $name).frame(minWidth: 380)
            Picker("Plantilla", selection: $template) {
                ForEach(NoteTemplates.names, id: \.self) { Text($0).tag($0) }
                let mine = store.userTemplates()
                if !mine.isEmpty { Divider(); ForEach(mine, id: \.self) { Text("★ \($0)").tag($0) } }
            }
            .onChange(of: template) {
                let f = NoteTemplates.names.contains(template) ? NoteTemplates.defaultFolder(template) : (store.userTemplate(template, title: "")?.folder ?? "")
                if !f.isEmpty { folder = f }
            }
            let questions = NoteTemplates.names.contains(template) ? [] : store.templateQuestions(template)
            if !questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Datos de la plantilla").font(.subheadline.weight(.semibold))
                    ForEach(questions) { q in
                        TextField(q.label, text: Binding(get: { answers[q.label] ?? q.defaultValue }, set: { answers[q.label] = $0 }))
                    }
                }
            }
            if store.userTemplates().isEmpty {
                Button("Crear plantillas de ejemplo (Reunión, Lectura, Idea, Viaje)") { store.createSampleTemplates() }.buttonStyle(.link).font(.caption)
            } else {
                Text("Tus plantillas están en la carpeta Plantillas. Variables: {{titulo}} {{fecha}} {{hora}} {{dia}} {{semana}}.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Carpeta", selection: $folder) {
                Text("(raíz)").tag("")
                ForEach(Array(Set(folders + [NoteTemplates.defaultFolder(template)].filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Crear") {
                    if let p = store.createNote(folder: folder, name: name, template: template, answers: answers) { dismiss(); created(p) }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(22)
         .onAppear { template = template0; folder = folder0 }
    }
}

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let rename: (String) -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Renombrar nota").font(.title3.weight(.semibold))
            TextField("Nombre", text: $name).frame(minWidth: 380)
            Text("Los enlaces [[\(current)]] de las demás notas se actualizan solos.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Renombrar") { dismiss(); rename(name) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == current)
            }
        }.padding(22).onAppear { name = current }
    }
}

/// Fila que salta de línea.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    var minimum: CGFloat = 120
    let content: (Item) -> Content
    init(_ items: [Item], minimum: CGFloat = 120, @ViewBuilder content: @escaping (Item) -> Content) { self.items = items; self.minimum = minimum; self.content = content }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 260), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}
