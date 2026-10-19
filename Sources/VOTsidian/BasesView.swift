import SwiftUI

/// Vista de base de datos (como Notion): todas las notas de un mismo `tipo` en una tabla con sus propiedades editables.
struct BasesView: View {
    @Environment(Store.self) private var store
    @AppStorage("basesType") private var type = ""
    @State private var filter = ""
    @State private var showNew = false

    private static let templateForType = ["proyecto": "Proyecto", "cita_medica": "Cita médica", "evento": "Evento", "casa_item": "Reforma o compra"]

    private var types: [(name: String, count: Int)] {
        var c: [String: Int] = [:]
        for m in store.noteMeta.values { if let t = m["tipo"], !t.isEmpty { c[t, default: 0] += 1 } }
        return c.map { (name: $0.key, count: $0.value) }.sorted { ($1.count, $0.name) < ($0.count, $1.name) }
    }

    var body: some View {
        let all = types
        let current = all.contains { $0.name == type } ? type : (all.first?.name ?? "")
        let notes = store.noteMeta.filter { $0.value["tipo"] == current }.keys.sorted()
            .filter { filter.isEmpty || MD.fold($0).contains(MD.fold(filter)) }
        var freq: [String: Int] = [:]
        for p in store.noteMeta.filter({ $0.value["tipo"] == current }).keys { for k in store.noteMeta[p]?.keys ?? [:].keys where !["tipo", "tags", "aliases"].contains(k) { freq[k, default: 0] += 1 } }
        let columns = freq.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(7).map(\.key)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cada nota con la propiedad «tipo» forma parte de una base. Edita las celdas sin abrir la nota.").foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(all, id: \.name) { t in
                            Button { type = t.name } label: {
                                Text("\(t.name) · \(t.count)").padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(t.name == current ? Brand.accent.opacity(0.25) : Color.primary.opacity(0.07), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("Filtrar por nombre", text: $filter).frame(width: 240)
                    Spacer()
                    Button { showNew = true } label: { Label("Nueva nota de este tipo", systemImage: "plus") }.disabled(current.isEmpty)
                }
                Card(title: current.isEmpty ? "Sin bases" : current.capitalized, icon: "square.grid.3x3") {
                    if notes.isEmpty { Text("No hay notas de este tipo.").foregroundStyle(.secondary) }
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            if !notes.isEmpty {
                                GridRow { Text("Nota"); Text("Modificada"); Text("Etiquetas"); ForEach(columns, id: \.self) { Text($0) } }.font(.caption).foregroundStyle(.secondary)
                                Divider()
                            }
                            ForEach(notes, id: \.self) { path in
                                GridRow {
                                    Button(((path as NSString).lastPathComponent as NSString).deletingPathExtension) { store.pendingNote = path }
                                        .buttonStyle(.link).frame(width: 190, alignment: .leading)
                                    Text(store.modified[path].map { shortDate($0) } ?? "–").foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                                    Text((store.noteTags[path] ?? []).map { "#\($0)" }.joined(separator: " ")).font(.caption).foregroundStyle(Brand.accent).frame(width: 150, alignment: .leading).lineLimit(2)
                                    ForEach(columns, id: \.self) { col in PropertyField(file: path, key: col, width: 130) }
                                }
                            }
                        }
                    }
                }
                if !all.isEmpty {
                    Text("Las propiedades se guardan en el encabezado de cada nota. Para crear una propiedad nueva, ábrela en Notas y añádela en «Propiedades».").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle("Bases")
        .sheet(isPresented: $showNew) {
            NewNoteSheet(folders: Array(Set(store.notes.map(\.folder).filter { $0 != "Raíz" })).sorted(),
                         template0: Self.templateForType[current] ?? "En blanco",
                         folder0: NoteTemplates.defaultFolder(Self.templateForType[current] ?? "")) { store.pendingNote = $0 }
        }
    }
}
