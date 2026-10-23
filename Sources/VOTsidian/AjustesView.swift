import SwiftUI

struct AjustesView: View {
    @Environment(Store.self) private var store
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("menuBar") private var menuBar = true
    @State private var backupMessage = ""
    @State private var newPassword = ""
    @State private var repeatPassword = ""
    @State private var cryptoMessage = ""
    @State private var exportMessage = ""
    @State private var exportYear = Calendar.current.component(.year, from: Date())

    @ViewBuilder private var encryptionControls: some View {
        if store.backupPassword != nil {
            Label("Las copias nuevas van cifradas (AES-256). Se abren con doble clic en Finder y tu contraseña, sin la app.", systemImage: "lock.fill")
                .font(.callout).foregroundStyle(Brand.accent)
            Text("Las copias anteriores siguen como carpetas sin cifrar. Si quitas el cifrado, las cifradas siguen necesitando la contraseña de entonces.").font(.caption).foregroundStyle(.secondary)
            Button("Dejar de cifrar copias nuevas") { store.setBackupPassword(nil); cryptoMessage = "" }
        } else {
            Text("Cifrar las copias nuevas").font(.headline)
            SecureField("Contraseña", text: $newPassword).frame(width: 260)
            SecureField("Repite la contraseña", text: $repeatPassword).frame(width: 260)
            Text("Se guarda en el Llavero de macOS y no se vuelve a pedir. Apúntala también en otro sitio: sin ella las copias cifradas no se pueden abrir.").font(.caption).foregroundStyle(.secondary)
            Button("Activar cifrado") {
                if newPassword.count < 8 { cryptoMessage = "Mínimo 8 caracteres." }
                else if newPassword != repeatPassword { cryptoMessage = "Las contraseñas no coinciden." }
                else if store.setBackupPassword(newPassword) { newPassword = ""; repeatPassword = ""; cryptoMessage = "" }
            }
        }
        if !cryptoMessage.isEmpty { Text(cryptoMessage).font(.callout).foregroundStyle(Brand.bad) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Apariencia", icon: "paintbrush", info: "Sistema sigue el modo claro u oscuro de macOS.") {
                    Picker("", selection: $appearance) {
                        ForEach(Appearance.allCases) { Label($0.title, systemImage: $0.icon).tag($0.rawValue) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 340)
                }
                Card(title: "Tus datos", icon: "externaldrive") {
                    Text(store.root.path).font(.callout.monospaced()).textSelection(.enabled)
                    if store.root.path.contains("com~apple~CloudDocs") { Label("Está en iCloud Drive: se sincroniza con tus otros dispositivos.", systemImage: "icloud").font(.callout).foregroundStyle(Brand.accent) }
                    Text("\(store.notes.count) notas · \(store.tasks.filter { !$0.done }.count) tareas abiertas · \(store.outLinks.values.reduce(0) { $0 + $1.count }) enlaces").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Cambiar carpeta…") { store.chooseFolder() }
                        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.root]) }
                    }
                }
                Card(title: "Copias de seguridad", icon: "clock.arrow.circlepath", info: "Cada cambio también se puede deshacer con el botón del aviso o con ⌥⌘Z. El historial de una sola nota está en Notas → ⋯ → Historial.") {
                    Text("Antes del primer cambio de cada día la app copia tus notas a una sola carpeta («Ver copias en Finder»), fuera de Documentos para que no ocupen iCloud. Guarda las últimas \(Store.keepAutoBackups) copias automáticas y borra las más viejas. Las copias manuales no se borran solas.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Hacer copia ahora") {
                            backupMessage = store.backupNow().map { "Creando: \($0.lastPathComponent) (aparece al terminar)" } ?? "No se pudo crear."
                        }
                        Button("Ver copias en Finder") { try? FileManager.default.createDirectory(at: store.backupsFolder, withIntermediateDirectories: true); NSWorkspace.shared.open(store.backupsFolder) }
                        Text(backupMessage).foregroundStyle(.secondary)
                    }
                    Text("\(store.allBackups().count) copias guardadas (\(store.autoBackups().count) automáticas).").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    BackupsList()
                    Divider()
                    encryptionControls
                }
                if !store.pendingDownloads.isEmpty {
                    Card(title: "iCloud", icon: "icloud.and.arrow.down") {
                        Text("\(store.pendingDownloads.count) archivos están en iCloud pero no en este Mac, así que la app no los ve todavía.").foregroundStyle(.secondary)
                        ForEach(store.pendingDownloads.prefix(6), id: \.self) { Text($0).font(.caption.monospaced()) }
                        Button("Descargar ahora") { store.downloadPending() }
                    }
                }
                brokenLinksCard
                Card(title: "Exportar", icon: "square.and.arrow.up", info: "El CSV incluye peso, pinchazos, medidas, hábitos, tareas y ánimo y sueño; se abre con Numbers o Excel. El resumen sirve para enseñarlo en una consulta.") {
                    HStack {
                        Picker("Año", selection: $exportYear) { ForEach(Array((exportYear - 4)...(Calendar.current.component(.year, from: Date()) + 0)), id: \.self) { Text(String($0)).tag($0) } }.frame(width: 140)
                        Button("Resumen del año (PDF)…") { exportYearPDF() }
                    }
                    HStack {
                        Button("Mis datos en CSV…") { exportCSV() }
                        Button("Todas las notas (.zip)…") { exportZip() }
                    }
                    if !exportMessage.isEmpty { Text(exportMessage).font(.callout).foregroundStyle(.secondary) }
                }
                Card(title: "Barra de menús", icon: "menubar.rectangle") {
                    Toggle("Mostrar peso y próximo pinchazo en la barra de menús", isOn: $menuBar)
                }
                Card(title: "Atajos", icon: "keyboard") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                        shortcut("⌘K", "Buscar notas, pantallas y acciones")
                        shortcut("⇧⌘N", "Captura rápida: tarea, peso, pinchazo o idea")
                        shortcut("⌘1 … ⌘9", "Ir a una pantalla")
                        shortcut("⌘S", "Guardar la nota que editas")
                        shortcut("⌥⌘Z", "Deshacer el último cambio de la app")
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Ajustes")
    }

    private var brokenLinksCard: some View {
        let broken = store.brokenLinks()
        return Card(title: "Enlaces entre notas", icon: "link", actionTitle: "Abrir", action: { store.screen = .enlaces }) {
            if broken.isEmpty { Label("Todos los enlaces funcionan.", systemImage: "checkmark.seal").foregroundStyle(Brand.accent) }
            else { Text("\(broken.count) \(broken.count == 1 ? "enlace roto" : "enlaces rotos"). Arréglalos uno a uno en «Enlaces rotos».").foregroundStyle(Brand.warn) }
        }
    }

    private func exportYearPDF() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Resumen \(exportYear).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        PDFExport.write(YearSummaryView(stats: store.yearStats(exportYear), vaultName: store.vaultName), to: url)
        exportMessage = "Resumen guardado: \(url.lastPathComponent)"
        NSWorkspace.shared.open(url)
    }

    private func exportCSV() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Exportar aquí"; panel.message = "Elige la carpeta donde guardar los CSV"
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let dir = base.appendingPathComponent("Datos VOTsidian \(DayKey.string(Date()))")
        do { let files = try store.exportData(to: dir); exportMessage = "\(files.count) archivos en \(dir.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([dir]) }
        catch { exportMessage = "No se pudo exportar: \(error.localizedDescription)" }
    }

    private func exportZip() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Notas \(DayKey.string(Date())).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportMessage = store.exportNotesZip(to: url) ? "Copia guardada: \(url.lastPathComponent)" : "No se pudo crear el zip."
    }

    private func shortcut(_ k: String, _ t: String) -> some View {
        GridRow { Text(k).font(.callout.monospaced()).foregroundStyle(Brand.accent); Text(t) }
    }
}
