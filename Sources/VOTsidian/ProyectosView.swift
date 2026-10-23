import SwiftUI

struct ProyectosView: View {
    @Environment(Store.self) private var store
    @State private var showNew = false
    @AppStorage("proyectosBoard") private var board = false

    private struct Row: Identifiable { var path: String; var name: String; var meta: [String: String]; var open: Int; var done: Int; var id: String { path } }

    private var rows: [Row] {
        let order = ["activo": 0, "pausado": 1, "completado": 2]
        return store.noteMeta.compactMap { path, m -> Row? in
            guard m["tipo"] == "proyecto" else { return nil }
            let t = store.tasks.filter { $0.file == path }
            return Row(path: path, name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, meta: m,
                       open: t.filter { !$0.done }.count, done: t.filter(\.done).count)
        }.sorted {
            let a = order[$0.meta["estado"] ?? ""] ?? 3, b = order[$1.meta["estado"] ?? ""] ?? 3
            if a != b { return a < b }
            let da = $0.meta["fecha_limite"].flatMap { $0.isEmpty ? nil : $0 } ?? "9999", db = $1.meta["fecha_limite"].flatMap { $0.isEmpty ? nil : $0 } ?? "9999"
            return da < db
        }
    }

    var body: some View {
        let items = rows
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Tile(title: "Activos", value: "\(items.filter { $0.meta["estado"] == "activo" }.count)")
                    Tile(title: "Pausados", value: "\(items.filter { $0.meta["estado"] == "pausado" }.count)")
                    Tile(title: "Completados", value: "\(items.filter { $0.meta["estado"] == "completado" }.count)", tint: Brand.accent)
                    Tile(title: "Tareas abiertas", value: "\(items.reduce(0) { $0 + $1.open })")
                }
                if items.isEmpty {
                    ContentUnavailableView("Todavía no hay proyectos", systemImage: "folder.badge.plus",
                                           description: Text("Crea el primero con el botón de abajo."))
                }
                Picker("", selection: $board) { Text("Lista").tag(false); Text("Tablero").tag(true) }.pickerStyle(.segmented).frame(width: 190).labelsHidden()
                if board {
                    StatusBoard(columns: ["activo", "pausado", "completado"],
                                cards: Dictionary(grouping: items, by: { $0.meta["estado"] ?? "activo" }).mapValues { rs in
                                    rs.map { BoardCard(id: $0.path, title: $0.name, subtitle: "\($0.open) abiertas · \($0.done) hechas", badge: ($0.meta["prioridad"] ?? "").capitalized, color: ($0.meta["prioridad"] ?? "") == "alta" ? Brand.bad : Brand.accent) }
                                },
                                columnWidth: 260, open: { store.pendingNote = $0 },
                                move: { id, col in store.setProperty(id, key: "estado", value: col) })
                }
                ForEach(board ? [] : items) { r in
                    Card(title: r.name, icon: "folder", actionTitle: "Abrir nota", action: { store.pendingNote = r.path }) {
                        HStack(spacing: 18) {
                            labeled("Estado") { PropertyPicker(file: r.path, key: "estado", options: ["activo", "pausado", "completado"]) }
                            labeled("Prioridad") { PropertyPicker(file: r.path, key: "prioridad", options: ["alta", "media", "baja"], width: 110) }
                            labeled("Área") { PropertyField(file: r.path, key: "area", width: 120) }
                            labeled("Fecha límite") { PropertyDateField(file: r.path, key: "fecha_limite") }
                        }
                        let total = r.open + r.done
                        if total > 0 {
                            ProgressView(value: Double(r.done), total: Double(total)).tint(Brand.accent)
                            Text("\(r.done) de \(total) tareas hechas").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(store.tasks.filter { $0.file == r.path && !$0.done }.prefix(4)) { TaskRow(task: $0) }
                    }
                }
                Button { showNew = true } label: { Label("Nuevo proyecto", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Proyectos")
        .sheet(isPresented: $showNew) {
            NewNoteSheet(folders: ["Proyectos"], template0: "Proyecto", folder0: "Proyectos") { store.pendingNote = $0; store.screen = .notas }
        }
    }

    private func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(t).font(.caption).foregroundStyle(.secondary); c() }
    }
}
