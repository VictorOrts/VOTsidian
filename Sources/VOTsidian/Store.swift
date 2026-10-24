import AppKit
import Foundation
import Observation
import SwiftUI

/// Dónde está cada archivo en la carpeta. Si la tuya se organiza distinto, cambia la ruta en Ajustes → Módulos → Rutas de
/// las notas, o desde la terminal: `defaults write <id de la app> vaultPathOverrides -dict peso "Mis notas/Báscula.md"`
/// (claves: peso, medicacion, plan, proyecto, mascota, vehiculo, suscripciones, prestamos, lecturas, viajes, tramites, casa, moda, medico, inbox, documentos, personas, objetivos, finanzas, gastos, revisiones, compra, medidas).
enum VaultPath {
    static let defaults: [String: String] = [
        "peso": "Salud/Peso.md",
        "medidas": "Salud/Medidas.md",
        "medicacion": "Salud/Medicación.md",
        "plan": "Salud/Plan nutricional.md",
        "medico": "Salud/Médico.md",
        "proyecto": "Proyectos/Objetivo de peso.md",
        "mascota": "Mascota/Mascota.md",
        "vehiculo": "Vehículo/Vehículo.md",
        "suscripciones": "Finanzas/Suscripciones.md",
        "prestamos": "Finanzas/Préstamos.md",
        "lecturas": "Lecturas/Lecturas.md",
        "viajes": "Viajes/Viajes.md",
        "tramites": "Organización/Trámites y seguros.md",
        "casa": "Casa/Casa.md",
        "compra": "Casa/Lista de la compra.md",
        "moda": "Moda/Armario.md",
        "inbox": "Organización/Inbox.md",
        "documentos": "Organización/Documentos.md",
        "personas": "Organización/Personas.md",
        "objetivos": "Organización/Objetivos.md",
        "finanzas": "Finanzas/Finanzas.md",
        "gastos": "Finanzas/Gastos",
        "revisiones": "Revisiones",
    ]
    static func path(_ key: String) -> String {
        overrides[key].flatMap { $0.isEmpty ? nil : $0 } ?? defaults[key] ?? key
    }

    /// Carpeta de la nota de `key` («Salud» para peso), o `""` si está en la raíz.
    static func folder(_ key: String) -> String { (path(key) as NSString).deletingLastPathComponent }
    /// `name` en la misma carpeta que la nota de `key`: las fotos junto al peso, los análisis junto a Médico…
    static func beside(_ key: String, _ name: String) -> String { folder(key).isEmpty ? name : folder(key) + "/" + name }

    /// Rutas cambiadas (Ajustes → Módulos), por clave.
    static var overrides: [String: String] {
        (UserDefaults.standard.dictionary(forKey: "vaultPathOverrides") ?? [:]).compactMapValues { $0 as? String }
    }
    /// Cambia la ruta de una clave; `nil` vuelve a la de siempre.
    static func setOverride(_ key: String, _ value: String?) {
        var o = overrides
        o[key] = value
        if o.isEmpty { UserDefaults.standard.removeObject(forKey: "vaultPathOverrides") } else { UserDefaults.standard.set(o, forKey: "vaultPathOverrides") }
    }
    static var peso: String { path("peso") }
    static var medicacion: String { path("medicacion") }
    static var plan: String { path("plan") }
    static var proyecto: String { path("proyecto") }
    static var mascota: String { path("mascota") }
    static var vehiculo: String { path("vehiculo") }
    static var suscripciones: String { path("suscripciones") }
    static var prestamos: String { path("prestamos") }
    static var lecturas: String { path("lecturas") }
    static var viajes: String { path("viajes") }
    static var tramites: String { path("tramites") }
    static var casa: String { path("casa") }
    static var moda: String { path("moda") }
    static var medico: String { path("medico") }
    static var inbox: String { path("inbox") }
    static var documentos: String { path("documentos") }
    static var personas: String { path("personas") }
    static var objetivos: String { path("objetivos") }
    static var finanzas: String { path("finanzas") }
    static var revisiones: String { path("revisiones") }
    static var gastos: String { path("gastos") }
    static var compra: String { path("compra") }
    static var medidas: String { path("medidas") }
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

/// Una nota vista desde la interfaz: quien lee una nota (con `read`) depende solo de su caja, y la recarga solo avisa a las
/// cajas cuyo texto cambió. Así editar Peso no repinta las tablas de Vehículo.
@MainActor @Observable
final class NoteSlot {
    var version = 0
}

/// Lo que enseñan los indicadores de la barra lateral. Se publica entero y solo avisa si cambia.
struct SidebarState: Equatable {
    var counts: [Screen: Int] = [:]
    var medicationDays: Int?
    var tasksOverdue = false
}

@MainActor @Observable
final class Store {
    private(set) var root: URL
    private(set) var weight = WeightData()
    private(set) var medicacion = MedicacionData()
    private(set) var mascota = MascotaData()
    private(set) var vehiculo = VehiculoData()
    private(set) var suscripciones = SuscripcionesData()
    private(set) var prestamos = PrestamosData()
    private(set) var lecturas = LecturasData()
    private(set) var viajes = ViajesData()
    private(set) var tramites = TramitesData()
    private(set) var plan = PlanData()
    private(set) var milestones: [Milestone] = []
    private(set) var habitDefs: [HabitDef] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var reviews: [String: WeekReview] = [:]
    private(set) var notes: [NoteFile] = []
    private(set) var casa = CasaData()
    private(set) var outLinks: [String: [String]] = [:]
    private(set) var backLinks: [String: [String]] = [:]
    /// Sube con cada recarga. **No se observa**: una vista que lo leyera se repintaría con cualquier cambio en cualquier nota.
    /// Las vistas dependen de su nota (`read`), de los datos de su módulo o de los valores publicados de abajo.
    @ObservationIgnored private(set) var revision = 0
    /// Avisos e indicadores de la barra lateral, recalculados en cada recarga y publicados solo si cambian.
    private(set) var currentAlerts: [Alert] = []
    private(set) var sidebar = SidebarState()
    /// Suben cuando cambian las copias de seguridad, los enlaces entre notas o el texto de alguna nota.
    var backupsStamp = 0
    private(set) var linksVersion = 0
    private(set) var textsVersion = 0
    @ObservationIgnored var noteSlots: [String: NoteSlot] = [:]
    @ObservationIgnored var publishScheduled = false
    @ObservationIgnored var lastLinks: [String: [String]] = [:]
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
    /// Con una raíz explícita (tests) los módulos no se leen ni se guardan en las preferencias de la app.
    @ObservationIgnored private(set) var persistsModules = true
    /// Módulos que no se usan: sus pantallas, tarjetas y avisos no salen.
    var hiddenModules: Set<Module> = Set((UserDefaults.standard.stringArray(forKey: "hiddenModules") ?? []).compactMap(Module.init)) {
        didSet {
            agendaCache = [:]
            refreshPublished()
            if persistsModules { UserDefaults.standard.set(hiddenModules.map(\.rawValue).sorted(), forKey: "hiddenModules") }
        }
    }
    /// Ya se pasó por el asistente del principio.
    var modulesConfigured = UserDefaults.standard.bool(forKey: "modulesConfigured") {
        didSet { if persistsModules { UserDefaults.standard.set(modulesConfigured, forKey: "modulesConfigured") } }
    }
    var screen: Screen? = Screen.allCases.first { String(describing: $0) == ProcessInfo.processInfo.environment["VOT_SCREEN"] }
        ?? Screen(rawValue: UserDefaults.standard.string(forKey: "lastScreen") ?? "") ?? .inicio {
        didSet { if let s = screen { UserDefaults.standard.set(s.rawValue, forKey: "lastScreen") } }
    }
    var showPalette = false
    var showQuickAdd = false
    var showCierre = false
    var showEmpezar = false
    /// Día que «Mi día» debe enseñar al abrirse (desde la semana del Calendario o «Empezar el día»).
    var pendingPlanDay: Date?
    var pendingNote: String?
    /// Mes (AAAA-MM) que Gastos debe enseñar al abrirse: lo ponen Inicio y Finanzas para ir a un mes que no es el actual.
    var pendingGastosMonth: String?
    /// Año cuyo resumen debe enseñar Gastos al abrirse (desde Finanzas).
    var pendingGastosYear: Int?
    var message: String?
    /// Día (AAAA-MM-DD) de la última copia automática comprobada; así la copia es de verdad diaria aunque la app siga abierta.
    @ObservationIgnored var lastBackupDay: String?
    @ObservationIgnored var backupJob = DispatchGroup()
    /// Día en que ya se lanzó la copia automática en segundo plano.
    @ObservationIgnored var dailyBackupDay: String?
    /// Contraseña de las copias (del Llavero); si hay, las copias salen cifradas.
    private(set) var backupPassword: String?
    enum UndoStep {
        /// `written` es lo último que escribió la app; si al deshacer el archivo ya no coincide, alguien más lo cambió.
        case write(rel: String, previous: String?, written: String?)
        case trash(rel: String, trashed: URL, links: [(rel: String, previous: String)])
        case rename(old: String, new: String, links: [(rel: String, previous: String)])
        /// Varios pasos que se deshacen juntos (un cambio que toca más de un archivo).
        case batch([UndoStep])
    }
    /// Pila de deshacer. No se observa (cambia en cada edición); la interfaz solo necesita `canUndo`.
    @ObservationIgnored var undoStack: [UndoStep] = [] {
        didSet { if canUndo == undoStack.isEmpty { canUndo = !undoStack.isEmpty } }
    }
    private(set) var canUndo = false
    /// Mientras no es `nil`, los pasos de deshacer se juntan aquí para guardarse como uno solo (`grouped`).
    @ObservationIgnored var collectingUndo: [UndoStep]?
    /// Presupuestos ya analizados en esta recarga, por ruta.
    @ObservationIgnored var budgetCache: [String: Budget] = [:]
    /// Resúmenes del año por «AAAA|mes de hoy»: sumar todas las partidas de un año se nota al pasar el ratón por la gráfica.
    @ObservationIgnored var budgetYearCache: [String: BudgetYear] = [:]
    /// Por qué falló la última copia de seguridad automática; `nil` si fue bien.
    var backupFailure: String?
    @ObservationIgnored var lastQuietWrite: (rel: String, at: Date)?
    private(set) var pendingDownloads: [String] = []
    /// Notas que existen pero no se pudieron leer (no son UTF-8, permisos…): la app no las ve, y se avisa.
    private(set) var unreadableFiles: [String] = []
    @ObservationIgnored var foldedTexts: [String: String] = [:]
    /// Nombres de nota ya plegados; se rehacen en cada recarga.
    @ObservationIgnored var nameKeys: NameKeys?
    struct ParsedNote { var tasks: [TaskItem]; var meta: [String: String]; var tags: [String]; var snippet: String; var aliases: [String]; var links: [String] }
    struct CachedFile { var mtime: Date; var size: Int; var text: String; var parsed: ParsedNote }
    @ObservationIgnored var fileCache: [String: CachedFile] = [:]
    /// Último texto con que se calculó cada dato derivado (peso, plan, casa…); si no cambió, no se vuelve a analizar ni a publicar.
    @ObservationIgnored var derivedInputs: [String: String] = [:]
    @ObservationIgnored var reviewCache: [String: (text: String, week: WeekReview)] = [:]
    @ObservationIgnored var agendaCache: [String: [String: [AgendaItem]]] = [:]
    /// Nombre plegado → ruta (la primera en orden de carpeta), para resolver enlaces sin recorrer todas las notas.
    @ObservationIgnored var nameIndex: [String: String] = [:]
    @ObservationIgnored var watcher: VaultWatcher?
    /// Día en que se programaron por última vez los avisos del sistema.
    @ObservationIgnored var notificationsDay: String?
    /// Sincronización en curso con el calendario «VOTsidian» (EventKit).
    @ObservationIgnored var calendarSyncTask: Task<Void, Never>?
    /// Los avisos calculados por última vez y de qué dependían (ver `alerts()`).
    @ObservationIgnored var alertsCache: (key: String, alerts: [Alert])?
    @ObservationIgnored var brokenCountCache: (revision: Int, count: Int)?
    @ObservationIgnored var notesByNameCache: (revision: Int, list: [NoteFile])?

    /// Las notas por nombre (menús de «insertar enlace»): ordenarlas en cada pulsación del editor se notaba.
    var notesByName: [NoteFile] {
        _ = notes   // quien la usa depende de la lista de notas
        if let c = notesByNameCache, c.revision == revision { return c.list }
        let list = notes.sorted { MD.fold($0.name) < MD.fold($1.name) }
        notesByNameCache = (revision, list)
        return list
    }
    @ObservationIgnored var generation = 0
    @ObservationIgnored var scanning = false
    @ObservationIgnored var rescanRequested = false
    /// Texto de cada nota. No se observa entero: se lee con `read`, que registra solo la nota pedida.
    @ObservationIgnored private(set) var noteTexts: [String: String] = [:]
    private(set) var people: [Person] = []
    private(set) var documents: [(name: String, date: Date, section: String)] = []
    private(set) var events: [(name: String, date: Date, path: String)] = []

    /// Notas con casillas que no son tareas: la lista de la compra y el equipaje de los viajes.
    nonisolated static let notTaskTypes: Set<String> = ["compra", "viajes"]

    struct Change: Equatable { var id = UUID(); var file: String; var undoable: Bool }

    /// Carpeta única donde van todas las copias de seguridad. Con una raíz explícita (tests) usa una carpeta temporal.
    let backupsFolder: URL
    /// Cuántas copias automáticas se conservan; las más viejas se borran solas.
    static let keepAutoBackups = 14

    /// Activa el cifrado de las copias (guarda la contraseña en el Llavero) o lo quita con `nil`.
    @discardableResult
    func setBackupPassword(_ password: String?, keychain: Bool = true) -> Bool {
        if let password, !password.isEmpty {
            if keychain, !BackupKeychain.save(password) { message = "No se pudo guardar la contraseña en el Llavero."; return false }
            backupPassword = password
        } else {
            if keychain { BackupKeychain.delete() }
            backupPassword = nil
        }
        return true
    }

    init(root: URL? = nil, backups: URL? = nil) {
        self.backupsFolder = backups ?? (root == nil
            ? Store.defaultBackupsFolder
            : FileManager.default.temporaryDirectory.appendingPathComponent("votsidian-backups-\(UUID().uuidString)"))
        self.root = root ?? Store.defaultRoot()
        if root != nil { persistsModules = false; hiddenModules = []; modulesConfigured = false }
        if root == nil { backupPassword = BackupKeychain.load(); moveOldBackups(); moveLooseBackups() }
        reload()
        if root == nil {
            removeStaleStaging()
            registerNewModules()
            startWatching()
            startDailyBackup()
            Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.startDailyBackup(); self?.refreshSystemNotifications(); self?.refreshCalendarSync(force: true); self?.refreshPublished() }
            }
        }
        pendingNote = ProcessInfo.processInfo.environment["VOT_NOTE"]
        let overlay = ProcessInfo.processInfo.environment["VOT_OVERLAY"]
        showPalette = overlay == "palette"
        showQuickAdd = overlay == "quickadd"
        showCierre = overlay == "cierre"
        showEmpezar = overlay == "empezar"
    }

    static func defaultRoot() -> URL {
        let fm = FileManager.default
        if let v = ProcessInfo.processInfo.environment["VOT_VAULT"], fm.fileExists(atPath: v) { return URL(fileURLWithPath: v) }   // para pruebas y capturas
        if let saved = UserDefaults.standard.string(forKey: "vaultPath"), fm.fileExists(atPath: saved) {
            return URL(fileURLWithPath: saved)
        }
        let home = fm.homeDirectoryForCurrentUser
        // Sin carpeta elegida: VOTsidian en iCloud Drive (si está activado) para tenerla en todos los dispositivos.
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return fm.fileExists(atPath: icloud.path) ? icloud.appendingPathComponent("VOTsidian") : home.appendingPathComponent("Documents/VOTsidian")
    }

    var vaultName: String { root.lastPathComponent }
    /// Una carpeta sirve si tiene el archivo de peso o, al menos, alguna nota: el resto de pantallas funcionan vacías.
    var isValid: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: root.appendingPathComponent(VaultPath.peso).path) || !notes.isEmpty
    }

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    /// Texto del archivo, o `nil` si no se puede leer (no existe, iCloud sin descargar, no es UTF-8).
    func readOptional(_ rel: String) -> String? { try? String(contentsOf: url(rel), encoding: .utf8) }
    /// Texto para mostrar; `""` si no se puede leer. Las notas salen de lo ya cargado: las vistas lo piden en cada pintado
    /// y leer del disco (o esperar a iCloud) bloqueaba la ventana. Para comparar antes de escribir usa `readOptional`.
    func read(_ rel: String) -> String {
        touch(rel)
        return noteTexts[rel] ?? readOptional(rel) ?? ""
    }

    /// Registra que quien llama depende de la nota `rel` (aunque aún no exista: al crearla, se entera).
    /// Tareas de una nota, registrando solo esa nota y no la lista entera: la pantalla de un módulo no se repinta cuando se marca
    /// una tarea de otra nota. Las tareas salen del texto de la nota, así que cambian justo cuando cambia su `NoteSlot`.
    func tasks(in file: String) -> [TaskItem] {
        touch(file)
        return _tasks.filter { $0.file == file }
    }

    func touch(_ rel: String) {
        let slot = noteSlots[rel] ?? { let s = NoteSlot(); noteSlots[rel] = s; return s }()
        _ = slot.version
    }

    /// Como `refreshPublished`, en la siguiente vuelta del bucle principal: la edición termina antes y varias recargas seguidas
    /// (los autoguardados al escribir) se publican una sola vez.
    func refreshPublishedSoon() {
        guard !publishScheduled else { return }
        publishScheduled = true
        // En la siguiente vuelta del bucle principal (no `DispatchQueue.main.async`: dentro de un bloque de la cola principal, como
        // en los tests, eso no se ejecuta hasta que el bloque termina).
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.publishScheduled = false
                self.refreshPublished()
            }
        }
    }

    /// Avisos e indicadores de la barra lateral: se recalculan aquí y solo avisan a la interfaz si cambiaron.
    func refreshPublished() {
        currentAlerts = alerts()
        sidebar = SidebarState(counts: sidebarCounts(), medicationDays: medicacion.daysUntilNext,
                               tasksOverdue: tasks.contains { !$0.done && ($0.due.map { $0 < DayKey.today() } ?? false) })
    }

    // MARK: Carga

    /// Recarga completa y síncrona. Los archivos sin cambios salen de la caché (solo se consulta su fecha y tamaño).
    func reload() {
        generation += 1
        let started = Date()
        let scan = Store.scan(root: root, cache: fileCache)
        Log.notes.info("Carpeta leída: \(scan.files.count, privacy: .public) notas en \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public) ms")
        apply(scan)
    }

    /// Recarga tras escribir archivos que ya existían: solo se vuelven a leer esos, sin recorrer la carpeta.
    /// Si algo no cuadra (archivo nuevo, ilegible, fuera de las notas) cae en la recarga completa.
    func reload(changed rels: [String]) {
        let skip = ["Plantillas", ".obsidian"]
        guard !rels.isEmpty, rels.allSatisfy({ rel in
            fileCache[rel] != nil && rel.hasSuffix(".md") && !rel.hasSuffix(".excalidraw.md")
                && !rel.split(separator: "/").contains(where: { skip.contains(String($0)) })
        }) else { for r in rels { fileCache[r] = nil }; return reload() }
        var cache = fileCache
        var replaced: [String: [TaskItem]] = [:]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        for rel in rels {
            let u = url(rel)
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { for r in rels { fileCache[r] = nil }; return reload() }
            let v = try? u.resourceValues(forKeys: keys)
            let e = Store.makeEntry(text: text, rel: rel, mtime: v?.contentModificationDate ?? .distantPast, size: v?.fileSize ?? 0)
            cache[rel] = e
            replaced[rel] = Store.notTaskTypes.contains(e.parsed.meta["tipo"] ?? "") ? [] : e.parsed.tasks
        }
        var scan = Scan()
        scan.files = notes
        scan.texts = noteTexts
        scan.metas = noteMeta
        scan.tags = noteTags
        scan.snippets = snippets
        scan.modified = modified
        scan.attachments = attachments
        scan.pending = pendingDownloads
        scan.unreadable = unreadableFiles
        scan.cache = cache
        scan.links = cache.mapValues { $0.parsed.links }
        scan.aliases = aliasIndex.filter { !replaced.keys.contains($0.value) }
        // Las tareas conservan su orden: las de cada archivo cambiado se sustituyen donde estaban.
        var tasks: [TaskItem] = []
        var placed = Set<String>()
        for t in self.tasks {
            if let new = replaced[t.file] {
                if placed.insert(t.file).inserted { tasks += new }
            } else { tasks.append(t) }
        }
        for (rel, new) in replaced where !placed.contains(rel) { tasks += new }
        scan.tasks = tasks
        for (rel, e) in replaced.keys.compactMap({ r in cache[r].map { (r, $0) } }) {
            scan.texts[rel] = e.text
            scan.metas[rel] = e.parsed.meta
            scan.tags[rel] = e.parsed.tags
            scan.snippets[rel] = e.parsed.snippet
            scan.modified[rel] = e.mtime
            for a in e.parsed.aliases { scan.aliases[MD.fold(a)] = rel }
        }
        generation += 1
        apply(scan)
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
            Log.notes.debug("Cambios desde fuera de la app: se vuelve a leer la carpeta")
            if scan.pending.count != pendingDownloads.count { Log.icloud.notice("Archivos sin bajar de iCloud: \(scan.pending.count, privacy: .public)") }
            if scan.unreadable.count != unreadableFiles.count { Log.notes.error("Archivos que no se pueden leer: \(scan.unreadable.count, privacy: .public)") }
            generation += 1
            apply(scan)
        }
        if rescanRequested { rescanRequested = false; reloadInBackground() }
    }

    private func apply(_ scan: Scan) {
        revision += 1
        refreshCalendarSync()
        agendaCache = [:]
        budgetCache = [:]
        budgetYearCache = [:]
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
        let previousTexts = noteTexts
        noteTexts = texts
        // Solo se avisa a las notas que alguien está mirando y cuyo texto cambió.
        for (rel, slot) in noteSlots where previousTexts[rel] != texts[rel] { slot.version += 1 }
        if scan.changed { textsVersion += 1 }   // la recarga ya sabe si cambió algún archivo: no hace falta comparar todos los textos
        if linkMap != lastLinks { lastLinks = linkMap; linksVersion += 1 }
        func text(_ rel: String) -> String { texts[rel] ?? read(rel) }

        /// Analiza `rel` solo si su texto cambió desde la última vez; si no, deja el valor publicado como está.
        func derive(_ rel: String, _ body: (String) -> Void) {
            let t = text(rel)
            if derivedInputs[rel] != t { derivedInputs[rel] = t; body(t) }
        }
        derive(VaultPath.peso) { weight = Parse.weight($0) }
        derive(VaultPath.medicacion) { medicacion = Parse.medicacion($0) }
        derive(VaultPath.mascota) { mascota = Parse.mascota($0) }
        derive(VaultPath.vehiculo) { vehiculo = Parse.vehiculo($0) }
        derive(VaultPath.suscripciones) { suscripciones = Parse.suscripciones($0) }
        derive(VaultPath.prestamos) { prestamos = Parse.prestamos($0) }
        derive(VaultPath.lecturas) { lecturas = Parse.lecturas($0) }
        derive(VaultPath.viajes) { viajes = Parse.viajes($0) }
        derive(VaultPath.tramites) { tramites = Parse.tramites($0) }
        derive(VaultPath.plan) { plan = Parse.plan($0) }
        derive(VaultPath.proyecto) { milestones = Parse.milestones($0) }
        tasks = allTasks
        noteMeta = metas
        noteTags = tagMap
        snippets = snips
        modified = mods
        aliasIndex = aliases
        attachments = attach
        notes = files.sorted { ($0.folder, $0.name) < ($1.folder, $1.name) }
        derive(VaultPath.casa) { casa = Parse.casa($0) }
        derive(VaultPath.personas) { people = Parse.people($0).people }
        derive(VaultPath.documentos) { docsText in documents = Parse.tables(docsText).flatMap { t -> [(name: String, date: Date, section: String)] in
            guard let c = t.col("caduca") else { return [] }
            return t.rows.compactMap { r in
                guard let d = r.cells.first, !d.isEmpty, c < r.cells.count, let date = DayKey.date(r.cells[c]) ?? DayKey.dmyDate(r.cells[c]) else { return nil }
                return (d, date, t.title)
            }
        } }
        let newEvents: [(name: String, date: Date, path: String)] = metas.compactMap { path, m in
            guard m["tipo"] == "evento", let d = m["fecha_evento"].flatMap(DayKey.date) else { return nil }
            return (((path as NSString).lastPathComponent as NSString).deletingPathExtension, d, path)
        }.sorted { $0.path < $1.path }
        // Una lista de tuplas no se puede comparar sola: sin esto avisaría en cada recarga.
        if !newEvents.elementsEqual(events, by: { $0.name == $1.name && $0.date == $1.date && $0.path == $1.path }) { events = newEvents }
        buildLinks(links: linkMap)

        var found: [String: WeekReview] = [:]
        var weekCache: [String: (text: String, week: WeekReview)] = [:]
        for (rel, t) in texts where rel.hasPrefix(VaultPath.revisiones + "/") {
            guard let m = (rel as NSString).lastPathComponent.firstMatch(of: /(\d{4}-W\d{2})/) else { continue }
            let week: WeekReview
            if let c = reviewCache[rel], c.text == t { week = c.week } else { week = Parse.week(t, key: String(m.1)) }
            weekCache[rel] = (t, week)
            found[String(m.1)] = week
        }
        reviewCache = weekCache
        reviews = found
        pendingDownloads = pending.sorted()
        unreadableFiles = scan.unreadable.sorted()
        foldedTexts = [:]
        nameKeys = nil
        // Los hábitos son los de la revisión más reciente; si no hay ninguna, los de siempre.
        if let latest = found.keys.sorted().last(where: { !(found[$0]?.habits.isEmpty ?? true) }), let r = found[latest] {
            habitDefs = r.habits.map { HabitDef(name: $0.name, criterion: $0.criterion) }
        } else {
            habitDefs = ["Ejercicio", "Agua", "Sueño", "Leer"].map { HabitDef(name: $0) }
        }
        // Al abrir, ya: la primera pantalla sale con sus avisos. Después, en la siguiente vuelta.
        if revision == 1 { refreshPublished() } else { refreshPublishedSoon() }
    }

    /// Empieza a vigilar la carpeta: cualquier cambio externo recarga la app casi al instante.
    func startWatching() {
        watcher?.stop()
        watcher = VaultWatcher(path: root.path) { [weak self] in
            Task { @MainActor in self?.reloadInBackground() }
        }
    }

    var habitNames: [String] { habitDefs.map(\.name) }

    /// Reprograma los avisos de macOS (si están activados). Sin `force` solo actúa una vez al día: así la ventana
    /// de 30 días avanza aunque la app pase semanas abierta sin volver a primer plano.
    func refreshSystemNotifications(force: Bool = false) {
        guard UserDefaults.standard.bool(forKey: "systemNotifications") else { return }
        let day = Store.stamp("yyyy-MM-dd")
        guard force || notificationsDay != day else { return }
        notificationsDay = day
        let events = ICS.events(reminderSources(), plan: reminderPlan())
        Task {
            if let n = await Notifier.schedule(events) { Log.notifications.info("Notificaciones programadas: \(n, privacy: .public)") }
            else { Log.notifications.notice("Sin permiso para notificaciones (o fuera de la app)") }
        }
    }

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
        nameIndex = index
    }

    func resolve(_ name: String) -> String? {
        let key = MD.fold((name as NSString).lastPathComponent)
        return nameIndex[key] ?? aliasIndex[key]
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Elige la carpeta de tus notas (o crea una nueva)"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        root = u
        UserDefaults.standard.set(u.path, forKey: "vaultPath")
        lastBackupDay = nil
        dailyBackupDay = nil
        undoStack.removeAll()
        lastChange = nil
        fileCache.removeAll()
        derivedInputs.removeAll()
        reviewCache.removeAll()
        reload()
        startWatching()
        startDailyBackup()
    }
}
