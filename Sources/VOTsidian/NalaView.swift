import SwiftUI

struct NalaView: View {
    @Environment(Store.self) private var store
    @State private var date = Date()
    @State private var tipo = ""
    @State private var detalle = ""
    @State private var hasNext = false
    @State private var next = Date()
    @State private var coste = ""
    @State private var spec: RowSpec?

    var body: some View {
        let n = store.nala
        let tasks = store.tasks.filter { $0.file == VaultPath.nala && !$0.done }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .mascota)
                HStack(spacing: 12) {
                    Tile(title: "Edad", value: n.ageText ?? "–", note: n.birth.map { "nació el \(dayLabel($0))" })
                    Tile(title: "Comida", value: n.food.isEmpty ? "–" : n.food)
                }
                Card(title: "Avisos", icon: "bell") {
                    ForEach(Array(n.overdue.enumerated()), id: \.offset) { _, o in
                        Label("\(o.title) vencida el \(DayKey.dmy(o.date))", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn)
                    }
                    ForEach(Array(n.upcoming.enumerated()), id: \.offset) { _, u in
                        Text("\(u.title): \(DayKey.dmy(u.date)) (\(relativeDays(DayKey.days(from: DayKey.today(), to: u.date))))")
                    }
                    if n.overdue.isEmpty && n.upcoming.isEmpty { EmptyNote("Sin citas ni vacunas programadas.") }
                    ForEach(tasks) { TaskRow(task: $0) }
                }
                Card(title: "Registrar visita o vacuna", icon: "plus.circle") {
                    HStack {
                        DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).frame(width: 220)
                        TextField("Tipo (vacuna, revisión…)", text: $tipo)
                        TextField("Detalle", text: $detalle)
                    }
                    HStack {
                        Toggle("Próxima", isOn: $hasNext).toggleStyle(.checkbox)
                        DatePicker("", selection: $next, displayedComponents: .date).labelsHidden().disabled(!hasNext)
                        TextField("Coste", text: $coste).frame(width: 90)
                        Spacer()
                        Button("Guardar") {
                            store.addNalaVisit(date: DayKey.calendar().startOfDay(for: date), tipo: tipo, detalle: detalle,
                                               proxima: hasNext ? DayKey.calendar().startOfDay(for: next) : nil, coste: coste)
                            tipo = ""; detalle = ""; coste = ""; hasNext = false
                        }.buttonStyle(.borderedProminent).disabled(tipo.isEmpty)
                    }
                }
                Card(title: "Ficha", icon: "pawprint", info: "Pulsa intro para guardar cada campo.") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        ficha("Nacimiento (DD/MM/AAAA)", "nacimiento")
                        ficha("Comida", "comida")
                        ficha("Veterinario", "veterinario")
                        ficha("Teléfono del veterinario", "telefono_veterinario")
                        ficha("Chip", "chip")
                    }
                }
                Text("Salud").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow { Text("Fecha"); Text("Tipo"); Text("Detalle"); Text("Próxima"); Text("Coste"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(n.visits.reversed()) { v in
                        GridRow {
                            Text(DayKey.string(v.date)).monospacedDigit(); Text(v.tipo); Text(v.detalle).foregroundStyle(.secondary)
                            Text(v.proxima.map(DayKey.string) ?? ""); Text(v.coste)
                            EditButton { spec = RowSpec(file: VaultPath.nala, mode: .edit(line: v.line), title: "visita") }
                        }
                    }
                }
                Button("Abrir la nota Nala") { store.pendingNote = VaultPath.nala }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(n.name)
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    private func ficha(_ label: String, _ key: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing); PropertyField(file: VaultPath.nala, key: key, width: 320) }
    }
}
