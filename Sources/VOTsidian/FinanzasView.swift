import SwiftUI

struct FinanzasView: View {
    @Environment(Store.self) private var store
    @State private var showNew = false
    private let file = VaultPath.finanzas

    private var eventos: [(path: String, meta: [String: String])] {
        store.noteMeta.filter { $0.value["tipo"] == "evento" }.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        let total = eventos.reduce(0.0) { $0 + Money.parse($1.meta["aportacion_eur"] ?? "") }
        let pending = eventos.filter { $0.meta["estado"] != "pagado" }.reduce(0.0) { $0 + Money.parse($1.meta["aportacion_eur"] ?? "") }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Tile(title: "Eventos", value: "\(eventos.count)")
                    Tile(title: "Aportaciones", value: Money.format(total))
                    Tile(title: "Por pagar", value: Money.format(pending), tint: pending > 0 ? Brand.warn : Brand.accent)
                }
                Card(title: "Hoja de cuentas", icon: "tablecells.badge.ellipsis", info: "Las cuentas siguen en Numbers: la app no puede leer ni editar ese formato.") {
                    if let u = store.attachmentURL("Simple.numbers") {
                        Button { NSWorkspace.shared.open(u) } label: { Label("Abrir Simple.numbers en Numbers", systemImage: "arrow.up.forward.app") }
                    } else { Text("No encuentro Simple.numbers en tu vault.").foregroundStyle(.secondary) }
                }
                ForEach(eventos, id: \.path) { e in
                    Card(title: ((e.path as NSString).lastPathComponent as NSString).deletingPathExtension, icon: "party.popper", actionTitle: "Abrir nota", action: { store.pendingNote = e.path }) {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 3) { Text("Estado").font(.caption).foregroundStyle(.secondary); PropertyPicker(file: e.path, key: "estado", options: ["pendiente", "pagado", "cancelado"]) }
                            VStack(alignment: .leading, spacing: 3) { Text("Fecha").font(.caption).foregroundStyle(.secondary); PropertyDateField(file: e.path, key: "fecha_evento") }
                            VStack(alignment: .leading, spacing: 3) { Text("Aportación (€)").font(.caption).foregroundStyle(.secondary); PropertyField(file: e.path, key: "aportacion_eur", width: 100) }
                        }
                        ForEach(store.tasks.filter { $0.file == e.path && !$0.done }) { TaskRow(task: $0) }
                    }
                }
                Button { showNew = true } label: { Label("Nuevo evento o pago", systemImage: "plus") }.buttonStyle(.borderedProminent)
                Card(title: "Objetivos de ahorro y pagos", icon: "list.bullet") {
                    ForEach(store.tasks.filter { $0.file == file && !$0.done }) { TaskRow(task: $0) }
                    if store.tasks.filter({ $0.file == file && !$0.done }).isEmpty { Text("Sin tareas.").foregroundStyle(.secondary) }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Finanzas")
        .sheet(isPresented: $showNew) {
            NewNoteSheet(folders: ["Finanzas"], template0: "Evento", folder0: "Finanzas") { store.pendingNote = $0; store.screen = .notas }
        }
    }
}
