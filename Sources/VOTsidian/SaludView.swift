import SwiftUI
import UniformTypeIdentifiers

struct SaludView: View {
    @Environment(Store.self) private var store
    @State private var reason = ""
    @State private var date = Date().addingTimeInterval(7 * 86400)
    @State private var medication = ""
    @State private var showNewVisit = false
    @State private var showSummary = false
    @State private var spec: RowSpec?
    private let file = VaultPath.medico

    private var visits: [(path: String, date: Date?, especialidad: String)] {
        store.noteMeta.compactMap { path, m in
            guard m["tipo"] == "cita_medica" else { return nil }
            return (path, m["fecha"].flatMap(DayKey.date), m["especialidad"] ?? "")
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var appointments: [TaskItem] {
        store.tasks.filter { $0.file == file && !$0.done }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    var body: some View {
        let today = DayKey.today()
        let text = store.read(file)
        let meds = Parse.listItems(text, section: "Tratamientos")
        let analyses = Parse.tables(text).first { $0.title.localizedCaseInsensitiveContains("nálisis") || $0.title.localizedCaseInsensitiveContains("analisis") }
        let lastAnalysis = analyses?.rows.compactMap { r -> (Date, String)? in
            guard let d = DayKey.dmyDate(r.cells.first ?? "") ?? DayKey.date(r.cells.first ?? "") else { return nil }
            return (d, analyses!.value(r, "prueba"))
        }.max { $0.0 < $1.0 }
        let next = appointments.first { $0.due != nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .salud)
                HStack(spacing: 12) {
                    Tile(title: "Próxima cita", value: next?.due.map { dayLabel($0) } ?? "–",
                         note: next.map { "\($0.text) · \(relativeDays(DayKey.days(from: today, to: $0.due!)))" }, tint: (next?.due.map { DayKey.days(from: today, to: $0) <= 7 } ?? false) ? Brand.warn : nil)
                    Tile(title: "Citas pendientes", value: "\(appointments.count)")
                    Tile(title: "Último análisis", value: lastAnalysis.map { dayLabel($0.0) } ?? "–", note: lastAnalysis?.1)
                    Tile(title: "Tratamientos", value: "\(meds.count + (store.isVisible(.medicacion) ? store.medicacion.active().count : 0))")
                }

                Button { showSummary = true } label: { Label("Resumen para la consulta (copiar)", systemImage: "doc.on.clipboard") }
                Card(title: "Próximas citas", icon: "calendar.badge.clock", info: "Se guarda con fecha en Médico y aparece en Tareas y en los avisos de Calendar.") {
                    if appointments.isEmpty { EmptyNote("Sin citas pendientes.") }
                    ForEach(appointments) { TaskRow(task: $0) }
                    Divider()
                    HStack {
                        TextField("Nueva cita (médico, motivo)", text: $reason).onSubmit(addAppointment)
                        DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                        Button("Añadir cita", action: addAppointment).buttonStyle(.borderedProminent).disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Card(title: "Tratamientos y medicación", icon: "pills", info: "La medicación la decide tu médico. Aquí solo queda anotada.") {
                    // Los de la pantalla de medicación, con su frecuencia y, si es periódico, cuándo toca.
                    ForEach(store.isVisible(.medicacion) ? store.medicacion.active() : []) { med in
                        let mc = store.medicacion
                        Button { store.screen = .medicacion } label: {
                            HStack {
                                Image(systemName: med.icon).foregroundStyle(Brand.accent)
                                Text([med.name, mc.last(of: med)?.dose ?? med.dose].filter { !$0.isEmpty }.joined(separator: " ")).fontWeight(.medium)
                                Text(med.frequencyText.lowercased()).foregroundStyle(.secondary)
                                Spacer()
                                if med.every > 1, let n = mc.next(of: med), let d = mc.daysUntil(med) { Text("próximo \(shortDate(n)) · \(relativeDays(d))").foregroundStyle(d < 0 ? Brand.bad : .secondary) }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    ForEach(meds) { m in
                        HStack {
                            Image(systemName: "pills").foregroundStyle(Brand.accent)
                            Text(MDParser.inline(m.text))
                            Spacer()
                            Button { store.edit(file) { Edit.deleteLine($0, raw: m.raw, hint: m.line) } } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Quitar")
                        }
                    }
                    HStack {
                        TextField("Añadir tratamiento o suplemento (nombre, dosis, pauta)", text: $medication).onSubmit(addMedication)
                        Button("Añadir", action: addMedication).buttonStyle(.borderedProminent).disabled(medication.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Card(title: "Citas y visitas anotadas", icon: "stethoscope") {
                    if visits.isEmpty { EmptyNote("Todavía no hay notas de visita. Crea una con el botón.") }
                    ForEach(visits, id: \.path) { v in
                        Button { store.pendingNote = v.path } label: {
                            HStack {
                                Text(((v.path as NSString).lastPathComponent as NSString).deletingPathExtension).fontWeight(.medium)
                                Text(v.especialidad).foregroundStyle(.secondary)
                                Spacer()
                                Text(v.date.map { DayKey.dmy($0) } ?? "sin fecha").foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Button { showNewVisit = true } label: { Label("Nueva nota de visita", systemImage: "plus") }.buttonStyle(.borderless).font(.callout)
                }

                if analyses != nil {
                    NoteTables(file: file, icon: "doc.text.magnifyingglass", include: { $0.title.localizedCaseInsensitiveContains("nálisis") })
                    Button { addAnalysis(analyses!) } label: { Label("Añadir análisis (PDF)…", systemImage: "doc.badge.plus") }
                        .help("Los PDF se copian a \(VaultPath.beside("medico", "Análisis")) y se abren desde el enlace de la tabla.")
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Salud y médicos")
        .sheet(item: $spec) { RowSheet(spec: $0) }
        .sheet(isPresented: $showSummary) { SummarySheet(text: store.doctorSummary()) }
        .sheet(isPresented: $showNewVisit) {
            NewNoteSheet(folders: [VaultPath.folder("medico")], template0: "Cita médica", folder0: VaultPath.folder("medico")) { store.pendingNote = $0 }
        }
    }

    private func addAppointment() {
        let t = reason.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let d = DayKey.calendar().startOfDay(for: date)
        store.edit(file) { Edit.appendToSection($0, section: "Próximas citas", line: "- [ ] \(t) 📅 \(DayKey.string(d))") }
        reason = ""
    }

    private func addMedication() {
        let t = medication.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.edit(file) { Edit.appendToSection($0, section: "Tratamientos", line: "- \(t)") }
        medication = ""
    }

    private func addAnalysis(_ table: NamedTable) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]
        panel.message = "Elige el PDF o la imagen del análisis"
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let dir = store.url(VaultPath.beside("medico", "Análisis"))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(src.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: src, to: dest) }
        store.reload()
        var cells = [String](repeating: "", count: table.header.count)
        if cells.count > 0 { cells[0] = DayKey.dmy(Date()) }
        if cells.count > 1 { cells[1] = "Análisis" }
        if cells.count > 2 { cells[2] = "[[\(src.lastPathComponent)]]" }
        spec = RowSpec(file: file, mode: .add(afterLine: table.lastLine, headerLine: table.headerLine), title: "análisis", prefill: cells)
    }
}


struct SummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resumen para la consulta").font(.title3.weight(.semibold))
            ScrollView {
                Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Brand.radius))
            HStack {
                Text("Se genera con tus datos actuales. Revísalo antes de compartirlo.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(copied ? "Copiado ✓" : "Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 620, height: 520)
    }
}
