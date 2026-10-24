import SwiftUI

/// Sugerencias de tareas de mantenimiento de la casa, que se repiten solas.
struct MaintenancePreset: Identifiable, Equatable {
    var title: String
    var rule: String        // «1 months», «year»…
    var id: String { title }
}

enum Maintenance {
    static let section = "Mantenimiento"

    /// Sugerencias generales y las que corresponden a los aparatos de la casa (nombre, marca).
    static func presets(appliances: [(name: String, brand: String)]) -> [MaintenancePreset] {
        var out: [MaintenancePreset] = [
            MaintenancePreset(title: "Revisar la caldera o el calentador", rule: "year"),
            MaintenancePreset(title: "Cambiar las pilas de los detectores de humo", rule: "6 months"),
            MaintenancePreset(title: "Limpiar el filtro de la campana extractora", rule: "3 months"),
        ]
        func with(_ a: (name: String, brand: String)) -> String { a.brand.isEmpty ? "" : " \(a.brand)" }
        for a in appliances {
            let n = MD.fold(a.name)
            if n.contains("lavadora") {
                out.append(MaintenancePreset(title: "Ciclo de limpieza de la lavadora\(with(a))", rule: "1 months"))
                out.append(MaintenancePreset(title: "Limpiar el filtro y la goma de la lavadora\(with(a))", rule: "3 months"))
            } else if n.contains("lavavajillas") {
                out.append(MaintenancePreset(title: "Limpiar el filtro del lavavajillas\(with(a))", rule: "1 months"))
                out.append(MaintenancePreset(title: "Ciclo de limpieza del lavavajillas\(with(a))", rule: "3 months"))
            } else if n.contains("cafetera") {
                out.append(MaintenancePreset(title: "Descalcificar la cafetera\(with(a))", rule: "3 months"))
                out.append(MaintenancePreset(title: "Limpiar el molinillo de la cafetera\(with(a))", rule: "1 months"))
            } else if n.contains("frigor") {
                out.append(MaintenancePreset(title: "Limpiar y revisar el frigorífico\(with(a))", rule: "6 months"))
            } else if n.contains("horno") {
                out.append(MaintenancePreset(title: "Limpiar el horno\(with(a))", rule: "3 months"))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// Línea de tarea con fecha y repetición.
    static func line(_ p: MaintenancePreset, first: Date) -> String {
        "- [ ] \(p.title) 📅 \(DayKey.string(first)) 🔁 every \(p.rule)"
    }
}

extension Store {
    /// Aparatos de las tablas de electrodomésticos de la nota Casa.
    var appliances: [(name: String, brand: String)] {
        (casa.electros.rows + casa.small.rows).compactMap { r in
            guard let n = r.cells.first, !n.isEmpty else { return nil }
            return (n, r.cells.count > 1 ? r.cells[1] : "")
        }
    }

    var maintenanceTasks: [TaskItem] {
        tasks.filter { $0.file == VaultPath.casa && $0.recurrence != nil && !$0.done }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    /// Añade a la nota Casa las tareas elegidas, con su primera fecha. Las que ya existen no se repiten.
    func addMaintenance(_ presets: [MaintenancePreset], first: Date) {
        let existing = Set(tasks.filter { $0.file == VaultPath.casa }.map { MD.fold($0.text) })
        let fresh = presets.filter { !existing.contains(MD.fold($0.title)) }
        edit(VaultPath.casa) { Edit.appendToSectionCreating($0, section: Maintenance.section, lines: fresh.map { Maintenance.line($0, first: first) }) }
    }
}

struct MantenimientoCard: View {
    @Environment(Store.self) private var store
    @State private var picked: Set<String> = []
    @State private var first = DayKey.adding(days: 7, to: DayKey.today())

    var body: some View {
        let active = store.maintenanceTasks
        let activeTitles = Set(store.tasks(in: VaultPath.casa).map { MD.fold($0.text) })
        let suggestions = Maintenance.presets(appliances: store.appliances).filter { !activeTitles.contains(MD.fold($0.title)) }
        Card(title: "Mantenimiento del hogar", icon: "wrench.and.screwdriver") {
            if active.isEmpty { EmptyNote("Sin tareas de mantenimiento. Elige abajo las que quieras: se repiten solas y salen en el calendario y los avisos.") }
            ForEach(active) { TaskRow(task: $0) }
            if !suggestions.isEmpty {
                Divider()
                Text("Sugerencias para tu casa").font(.subheadline.weight(.semibold))
                ForEach(suggestions) { p in
                    Toggle(isOn: Binding(get: { picked.contains(p.id) }, set: { if $0 { picked.insert(p.id) } else { picked.remove(p.id) } })) {
                        HStack { Text(p.title); Spacer(); Text(Recurrence.describe(p.rule)).font(.caption).foregroundStyle(.secondary) }
                    }.toggleStyle(.checkbox)
                }
                HStack {
                    DatePicker("Primera vez", selection: $first, in: DayKey.today()..., displayedComponents: .date).fixedSize()
                    Spacer()
                    Button("Añadir seleccionadas (\(picked.count))") {
                        store.addMaintenance(suggestions.filter { picked.contains($0.id) }, first: DayKey.calendar().startOfDay(for: first))
                        picked = []
                    }.buttonStyle(.borderedProminent).disabled(picked.isEmpty)
                }
            }
        }
    }
}
