import AppKit
import Foundation
import Observation
import SwiftUI

enum VaultPath {
    static let peso = "Cambio físico/Peso.md"
    static let mounjaro = "Cambio físico/Mounjaro.md"
    static let plan = "Cambio físico/Plan Nutricional.md"
    static let proyecto = "Proyectos/Cambio físico 2026.md"
    static let nala = "Nala/Nala.md"
    static let casa = "Casa/Casa.md"
    static let moda = "Moda/Armario.md"
    static let medico = "Organización/Médico/Médico.md"
    static let inbox = "Organización/Inbox.md"
    static let documentos = "Organización/Documentos.md"
    static let personas = "Organización/Personas.md"
    static let objetivos = "Organización/Objetivos.md"
    static let finanzas = "Finanzas/Finanzas.md"
    static let revisiones = "Revisiones"
}

struct NoteFile: Identifiable, Hashable {
    let path: String
    let folder: String
    let name: String
    var id: String { path }

    init(path: String) {
        self.path = path
        self.folder = path.contains("/") ? String(path.split(separator: "/").dropLast().joined(separator: "/")) : "Raíz"
        self.name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

@MainActor @Observable
final class Store {
    private(set) var root: URL
    private(set) var weight = WeightData()
    private(set) var mounjaro = MounjaroData()
    private(set) var nala = NalaData()
    private(set) var plan = PlanData()
    private(set) var milestones: [Milestone] = []
    private(set) var habitDefs: [HabitDef] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var reviews: [String: WeekReview] = [:]
    private(set) var notes: [NoteFile] = []
    private(set) var casa = CasaData()
    private(set) var outLinks: [String: [String]] = [:]
    private(set) var backLinks: [String: [String]] = [:]
    private(set) var revision = 0
    private(set) var noteMeta: [String: [String: String]] = [:]
    private(set) var attachments: [String: String] = [:]
    private(set) var noteTags: [String: [String]] = [:]
    private(set) var snippets: [String: String] = [:]
    private(set) var modified: [String: Date] = [:]
    private(set) var aliasIndex: [String: String] = [:]
    var pinned: [String] = (UserDefaults.standard.stringArray(forKey: "pinnedNotes") ?? []) {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinnedNotes") }
    }
    var lastChange: Change?
    var screen: Screen? = Screen.allCases.first { String(describing: $0) == ProcessInfo.processInfo.environment["VOT_SCREEN"] }
        ?? Screen(rawValue: UserDefaults.standard.string(forKey: "lastScreen") ?? "") ?? .inicio {
        didSet { if let s = screen { UserDefaults.standard.set(s.rawValue, forKey: "lastScreen") } }
    }
    var showPalette = false
    var showQuickAdd = false
    var showCierre = false
    var pendingNote: String?
    var message: String?
    /// Día (AAAA-MM-DD) de la última copia automática comprobada; así la copia es de verdad diaria aunque la app siga abierta.
    var lastBackupDay: String?
    @ObservationIgnored var backupJob = DispatchGroup()
    enum UndoStep {
        /// `written` es lo último que escribió la app; si al deshacer el archivo ya no coincide, alguien más lo cambió.
        case write(rel: String, previous: String?, written: String?)
        case trash(rel: String, trashed: URL, links: [(rel: String, previous: String)])
        case rename(old: String, new: String, links: [(rel: String, previous: String)])
    }
    var undoStack: [UndoStep] = []
    var lastQuietWrite: (rel: String, at: Date)?
    private(set) var pendingDownloads: [String] = []
    /// Notas que existen pero no se pudieron leer (no son UTF-8, permisos…): la app no las ve, y se avisa.
    private(set) var unreadableFiles: [String] = []
    @ObservationIgnored var foldedTexts: [String: String] = [:]
    struct ParsedNote { var tasks: [TaskItem]; var meta: [String: String]; var tags: [String]; var snippet: String; var aliases: [String]; var links: [String] }
    struct CachedFile { var mtime: Date; var size: Int; var text: String; var parsed: ParsedNote }
    @ObservationIgnored var fileCache: [String: CachedFile] = [:]
    @ObservationIgnored var agendaCache: [String: [String: [AgendaItem]]] = [:]
    @ObservationIgnored var watcher: VaultWatcher?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var scanning = false
    @ObservationIgnored var rescanRequested = false
    private(set) var noteTexts: [String: String] = [:]
    private(set) var people: [Person] = []
    private(set) var labs: [LabResult] = []
    private(set) var documents: [(name: String, date: Date, section: String)] = []
    private(set) var events: [(name: String, date: Date, path: String)] = []

    struct Change: Equatable { var id = UUID(); var file: String; var undoable: Bool }

    /// Carpeta única donde van todas las copias de seguridad. Con una raíz explícita (tests) usa una carpeta temporal.
    let backupsFolder: URL
    /// Cuántas copias automáticas se conservan; las más viejas se borran solas.
    static let keepAutoBackups = 14

    init(root: URL? = nil, backups: URL? = nil) {
        self.backupsFolder = backups ?? (root == nil
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Copias VOTsidian")
            : FileManager.default.temporaryDirectory.appendingPathComponent("votsidian-backups-\(UUID().uuidString)"))
        self.root = root ?? Store.defaultRoot()
        if root == nil { moveLooseBackups() }
        reload()
        if root == nil { startWatching(); startDailyBackup() }
        pendingNote = ProcessInfo.processInfo.environment["VOT_NOTE"]
        let overlay = ProcessInfo.processInfo.environment["VOT_OVERLAY"]
        showPalette = overlay == "palette"
        showQuickAdd = overlay == "quickadd"
        showCierre = overlay == "cierre"
    }

    static func defaultRoot() -> URL {
        let fm = FileManager.default
        if let v = ProcessInfo.processInfo.environment["VOT_VAULT"], fm.fileExists(atPath: v) { return URL(fileURLWithPath: v) }   // para pruebas y capturas
        if let saved = UserDefaults.standard.string(forKey: "vaultPath"), fm.fileExists(atPath: saved) {
            return URL(fileURLWithPath: saved)
        }
        let home = fm.homeDirectoryForCurrentUser
        for p in ["Library/Mobile Documents/com~apple~CloudDocs/VOTsidian", "Library/Mobile Documents/iCloud~md~obsidian/Documents/VictorBrain", "Documents/VictorBrain"] {
            let url = home.appendingPathComponent(p)
            if fm.fileExists(atPath: url.appendingPathComponent(VaultPath.peso).path) { return url }
        }
        return home.appendingPathComponent("Documents/VictorBrain")
    }

    var vaultName: String { root.lastPathComponent }
    var isValid: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent(VaultPath.peso).path) }

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    /// Texto del archivo, o `nil` si no se puede leer (no existe, iCloud sin descargar, no es UTF-8).
    func readOptional(_ rel: String) -> String? { try? String(contentsOf: url(rel), encoding: .utf8) }
    /// Texto para mostrar; `""` si no se puede leer. Para comparar antes de escribir usa `readOptional`.
    func read(_ rel: String) -> String { readOptional(rel) ?? "" }

    // MARK: Carga

    /// Resultado de leer la carpeta: se calcula sin tocar el estado de la app, así puede hacerse en segundo plano.
    struct Scan: Sendable {
        var files: [NoteFile] = []
        var texts: [String: String] = [:]
        var metas: [String: [String: String]] = [:]
        var attachments: [String: String] = [:]
        var tags: [String: [String]] = [:]
        var snippets: [String: String] = [:]
        var modified: [String: Date] = [:]
        var aliases: [String: String] = [:]
        var cache: [String: CachedFile] = [:]
        var links: [String: [String]] = [:]
        var pending: [String] = []
        var unreadable: [String] = []
        var tasks: [TaskItem] = []
        /// `false` si no hay ningún archivo nuevo, borrado ni modificado respecto a la caché con que se empezó.
        var changed = true
    }

    /// Recarga completa y síncrona. Los archivos sin cambios salen de la caché (solo se consulta su fecha y tamaño).
    func reload() {
        generation += 1
        apply(Store.scan(root: root, cache: fileCache))
    }

    /// Recarga en segundo plano, para los cambios que llegan de fuera (otro programa, iCloud): leer y analizar
    /// los archivos nuevos no bloquea la ventana, y si no hay nada distinto no se toca la pantalla.
    func reloadInBackground() {
        if scanning { rescanRequested = true; return }
        scanning = true
        let (root, cache, gen) = (self.root, fileCache, generation)
        Task.detached(priority: .userInitiated) { [weak self] in
            let scan = Store.scan(root: root, cache: cache)
            await self?.finishBackgroundScan(scan, startedAt: gen, root: root)
        }
    }

    private func finishBackgroundScan(_ scan: Scan, startedAt gen: Int, root scanned: URL) {
        scanning = false
        // Si mientras tanto hubo otra recarga o se cambió de carpeta, este resultado ya es viejo: se repite.
        if gen != generation || scanned != root { rescanRequested = true }
        else if scan.changed || scan.attachments != attachments || scan.pending != pendingDownloads || scan.unreadable.sorted() != unreadableFiles {
            generation += 1
            apply(scan)
        }
        if rescanRequested { rescanRequested = false; reloadInBackground() }
    }

    nonisolated static func scan(root: URL, cache: [String: CachedFile]) -> Scan {
        var out = Scan()
        let skip = ["Plantillas", ".obsidian"]
        let base = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var reused = 0
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) {
            for case let u as URL in en {
                let rel = String(u.standardizedFileURL.path.dropFirst(base.count + 1))
                let comps = rel.split(separator: "/").map(String.init)
                let last = u.lastPathComponent
                if last.hasPrefix(".") {
                    if last.hasSuffix(".icloud") { out.pending.append((comps.dropLast().joined(separator: "/") + "/" + String(last.dropFirst().dropLast(7))).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
                    if u.hasDirectoryPath { en.skipDescendants() }
                    continue
                }
                if comps.contains(where: { skip.contains($0) }) || rel.hasSuffix(".excalidraw.md") { continue }
                guard u.pathExtension == "md" else {
                    if !u.hasDirectoryPath, !u.lastPathComponent.hasPrefix(".") { out.attachments[MD.fold(u.lastPathComponent)] = rel }
                    continue
                }
                let v = try? u.resourceValues(forKeys: Set(keys))
                let mtime = v?.contentModificationDate ?? .distantPast
                let size = v?.fileSize ?? 0
                let entry: CachedFile
                if let c = cache[rel], c.mtime == mtime, c.size == size {
                    entry = c   // sin cambios: no se vuelve a leer ni a analizar
                    reused += 1
                } else if let text = try? String(contentsOf: u, encoding: .utf8) {
                    entry = CachedFile(mtime: mtime, size: size, text: text, parsed: ParsedNote(
                        tasks: Parse.tasks(text, file: rel), meta: MD.frontmatter(text), tags: NoteInfo.tags(text),
                        snippet: NoteInfo.snippet(text), aliases: NoteInfo.aliases(text), links: Links.extract(text)))
                } else { out.unreadable.append(rel); continue }   // existe pero no es UTF-8 o no se puede leer
                out.cache[rel] = entry
                out.files.append(NoteFile(path: rel))
                out.texts[rel] = entry.text
                out.links[rel] = entry.parsed.links
                if entry.parsed.meta["tipo"] != "compra" { out.tasks += entry.parsed.tasks }   // la lista de la compra no son tareas
                out.metas[rel] = entry.parsed.meta
                out.tags[rel] = entry.parsed.tags
                out.snippets[rel] = entry.parsed.snippet
                out.modified[rel] = mtime
                for a in entry.parsed.aliases { out.aliases[MD.fold(a)] = rel }
            }
        }
        out.changed = reused != out.cache.count || out.cache.count != cache.count
        return out
    }

    private func apply(_ scan: Scan) {
        revision += 1
        agendaCache = [:]
        let allTasks = scan.tasks
        let files = scan.files
        let texts = scan.texts
        let metas = scan.metas
        let attach = scan.attachments
        let tagMap = scan.tags
        let snips = scan.snippets
        let mods = scan.modified
        let aliases = scan.aliases
        let linkMap = scan.links
        let pending = scan.pending
        fileCache = scan.cache
        noteTexts = texts
        func text(_ rel: String) -> String { texts[rel] ?? read(rel) }

        weight = Parse.weight(text(VaultPath.peso))
        mounjaro = Parse.mounjaro(text(VaultPath.mounjaro))
        nala = Parse.nala(text(VaultPath.nala))
        plan = Parse.plan(text(VaultPath.plan))
        milestones = Parse.milestones(text(VaultPath.proyecto))
        tasks = allTasks
        noteMeta = metas
        noteTags = tagMap
        snippets = snips
        modified = mods
        aliasIndex = aliases
        attachments = attach
        notes = files.sorted { ($0.folder, $0.name) < ($1.folder, $1.name) }
        casa = Parse.casa(text(VaultPath.casa))
        people = Parse.people(text(VaultPath.personas)).people
        labs = Labs.parse(texts[Labs.file] ?? "")
        documents = Parse.tables(text(VaultPath.documentos)).flatMap { t -> [(name: String, date: Date, section: String)] in
            guard let c = t.col("caduca") else { return [] }
            return t.rows.compactMap { r in
                guard let d = r.cells.first, !d.isEmpty, c < r.cells.count, let date = DayKey.date(r.cells[c]) ?? DayKey.dmyDate(r.cells[c]) else { return nil }
                return (d, date, t.title)
            }
        }
        events = metas.compactMap { path, m in
            guard m["tipo"] == "evento", let d = m["fecha_evento"].flatMap(DayKey.date) else { return nil }
            return (((path as NSString).lastPathComponent as NSString).deletingPathExtension, d, path)
        }
        buildLinks(links: linkMap)

        var found: [String: WeekReview] = [:]
        for (rel, t) in texts where rel.hasPrefix(VaultPath.revisiones + "/") {
            guard let m = (rel as NSString).lastPathComponent.firstMatch(of: /(\d{4}-W\d{2})/) else { continue }
            found[String(m.1)] = Parse.week(t, key: String(m.1))
        }
        reviews = found
        pendingDownloads = pending.sorted()
        unreadableFiles = scan.unreadable.sorted()
        foldedTexts = [:]
        // Los hábitos son los de la revisión más reciente; si no hay ninguna, los de siempre.
        if let latest = found.keys.sorted().last(where: { !(found[$0]?.habits.isEmpty ?? true) }), let r = found[latest] {
            habitDefs = r.habits.map { HabitDef(name: $0.name, criterion: $0.criterion) }
        } else {
            habitDefs = ["Proteína", "Pasos", "Agua", "Sueño", "Creatina"].map { HabitDef(name: $0) }
        }
    }

    /// Empieza a vigilar la carpeta: cualquier cambio externo recarga la app casi al instante.
    func startWatching() {
        watcher?.stop()
        watcher = VaultWatcher(path: root.path) { [weak self] in
            Task { @MainActor in self?.reloadInBackground() }
        }
    }

    var habitNames: [String] { habitDefs.map(\.name) }

    /// Pide a iCloud que descargue los archivos pendientes.
    func downloadPending() {
        for rel in pendingDownloads { try? FileManager.default.startDownloadingUbiquitousItem(at: url(rel)) }
        message = pendingDownloads.isEmpty ? nil : "Descargando \(pendingDownloads.count) archivos de iCloud. Pulsa recargar en unos segundos."
    }

    func buildLinks(links: [String: [String]]) {
        var index: [String: String] = [:]
        for n in notes where index[MD.fold(n.name)] == nil { index[MD.fold(n.name)] = n.path }
        var out: [String: [String]] = [:]
        var back: [String: [String]] = [:]
        for (path, names) in links {
            var seen = Set<String>()
            for name in names {
                guard let target = index[MD.fold(name)] ?? aliasIndex[MD.fold((name as NSString).lastPathComponent)], target != path, seen.insert(target).inserted else { continue }
                out[path, default: []].append(target)
                back[target, default: []].append(path)
            }
        }
        outLinks = out
        backLinks = back.mapValues { $0.sorted() }
    }

    func resolve(_ name: String) -> String? {
        let key = MD.fold((name as NSString).lastPathComponent)
        return notes.first { MD.fold($0.name) == key }?.path ?? aliasIndex[key]
    }

    /// Etiquetas de todo el vault con el número de notas que las usan.
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: (String, Int)] = [:]
        for tags in noteTags.values { for t in tags { counts[MD.fold(t), default: (t, 0)].1 += 1 } }
        return counts.values.map { (tag: $0.0, count: $0.1) }.sorted { ($1.count, $0.tag) < ($0.count, $1.tag) }
    }

    func notes(withTag tag: String) -> Set<String> {
        Set(noteTags.filter { $0.value.contains { MD.fold($0) == MD.fold(tag) } }.map(\.key))
    }

    func togglePin(_ path: String) {
        if let i = pinned.firstIndex(of: path) { pinned.remove(at: i) } else { pinned.insert(path, at: 0) }
    }

    /// Notas que nombran a esta en texto plano pero no la enlazan.
    func unlinkedMentions(of path: String) -> [NoteFile] {
        guard let me = notes.first(where: { $0.path == path }), me.name.count >= 4 else { return [] }
        let key = MD.fold(me.name)
        let linked = Set(backLinks[path] ?? [])
        return notes.filter { n in
            guard n.path != path, !linked.contains(n.path) else { return false }
            let t = noteTexts[n.path] ?? read(n.path)
            let folded: String
            if let f = foldedTexts[n.path] { folded = f } else { folded = MD.fold(t); foldedTexts[n.path] = folded }   // se pliega una vez por recarga, no por consulta
            return folded.contains(key) && Edit.linkMention(t, name: me.name) != nil
        }
    }

    func linkMention(in path: String, to name: String) {
        edit(path) { Edit.linkMention($0, name: name) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Elige la carpeta de tus notas"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        root = u
        UserDefaults.standard.set(u.path, forKey: "vaultPath")
        lastBackupDay = nil
        fileCache.removeAll()
        reload()
        startWatching()
        startDailyBackup()
    }
}
