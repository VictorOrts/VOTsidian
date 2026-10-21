import SwiftUI

/// Vista de base de datos (como Notion): todas las notas de un mismo `tipo` en una tabla con sus propiedades editables.
struct BasesView: View {
    @Environment(Store.self) private var store
    @AppStorage("basesType") private var type = ""
    @State private var query = BaseView(name: "")
    @State private var saved: [BaseView] = []
    @State private var showNew = false
    @State private var showSave = false
    @State private var newViewName = ""

    private static let templateForType = ["proyecto": "Proyecto", "cita_medica": "Cita médica", "evento": "Evento", "casa_item": "Reforma o compra"]

    private var types: [(name: String, count: Int)] {
        var c: [String: Int] = [:]
        for m in store.noteMeta.values { if let t = m["tipo"], !t.isEmpty { c[t, default: 0] += 1 } }
        return c.map { (name: $0.key, count: $0.value) }.sorted { ($1.count, $0.name) < ($0.count, $1.name) }
    }

    var body: some View {
        let all = types
        let current = all.contains { $0.name == type } ? type : (all.first?.name ?? "")
        var freq: [String: Int] = [:]
        for p in store.noteMeta.filter({ $0.value["tipo"] == current }).keys { for k in store.noteMeta[p]?.keys ?? [:].keys where !["tipo", "tags", "aliases"].contains(k) { freq[k, default: 0] += 1 } }
        let columns = freq.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(7).map(\.key)
        let allKeys = freq.keys.sorted()
        let notes = BaseQuery.apply(query, paths: store.noteMeta.filter { $0.value["tipo"] == current }.keys.sorted(), meta: store.noteMeta, modified: store.modified)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cada nota con la propiedad «tipo» forma parte de una base. Edita las celdas sin abrir la nota.").foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(all, id: \.name) { t in
                            Button { type = t.name; query = BaseView(name: ""); saved = BaseViewStore.load(t.name) } label: {
                                Text("\(t.name) · \(t.count)").padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(t.name == current ? Brand.accent.opacity(0.25) : Color.primary.opacity(0.07), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("Filtrar por nombre", text: $query.text).frame(width: 240)
                    Button { query.conditions.append(BaseCondition(key: allKeys.first ?? "")) } label: { Label("Filtro", systemImage: "line.3.horizontal.decrease") }.disabled(allKeys.isEmpty)
                    viewsMenu(current)
                    Spacer()
                    Button { showNew = true } label: { Label("Nueva nota de este tipo", systemImage: "plus") }.disabled(current.isEmpty)
                }
                ForEach($query.conditions) { $c in
                    HStack {
                        Picker("", selection: $c.key) { ForEach(allKeys, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 150)
                        Picker("", selection: $c.op) { ForEach(BaseCondition.Op.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 110)
                        if c.op.needsValue { TextField("valor", text: $c.value).frame(width: 160) }
                        Button { query.conditions.removeAll { $0.id == c.id } } label: { Image(systemName: "xmark.circle.fill").accessibilityLabel("Quitar filtro") }.buttonStyle(.borderless)
                    }
                }
                Card(title: current.isEmpty ? "Sin bases" : current.capitalized, icon: "square.grid.3x3") {
                    if notes.isEmpty { Text("No hay notas de este tipo.").foregroundStyle(.secondary) }
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            if !notes.isEmpty {
                                GridRow { header(BaseQuery.nameKey); header(BaseQuery.modifiedKey); Text("Etiquetas"); ForEach(columns, id: \.self) { header($0) } }.font(.caption).foregroundStyle(.secondary)
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
        .onAppear { saved = BaseViewStore.load(type) }
        .sheet(isPresented: $showNew) {
            NewNoteSheet(folders: Array(Set(store.notes.map(\.folder).filter { $0 != "Raíz" })).sorted(),
                         template0: Self.templateForType[current] ?? "En blanco",
                         folder0: NoteTemplates.defaultFolder(Self.templateForType[current] ?? "")) { store.pendingNote = $0 }
        }
    }

    private func header(_ key: String) -> some View {
        Button { toggleSort(key) } label: {
            HStack(spacing: 2) {
                Text(key)
                if query.sortKey == key { Image(systemName: query.ascending ? "chevron.up" : "chevron.down").font(.caption2) }
            }
        }.buttonStyle(.plain).help("Ordenar por \(key)")
    }

    private func toggleSort(_ key: String) {
        if query.sortKey == key { query.ascending.toggle() } else { query.sortKey = key; query.ascending = true }
    }

    private func viewsMenu(_ current: String) -> some View {
        Menu {
            Button("Guardar vista actual…") { newViewName = ""; showSave = true }.disabled(current.isEmpty)
            if !saved.isEmpty { Divider() }
            ForEach(saved) { v in Button(v.name) { query = v } }
            if !saved.isEmpty {
                Divider()
                Menu("Borrar vista") {
                    ForEach(saved) { v in Button(v.name, role: .destructive) { saved.removeAll { $0.name == v.name }; BaseViewStore.save(saved, for: current) } }
                }
            }
            if query != BaseView(name: "") { Divider(); Button("Quitar filtros y orden") { query = BaseView(name: "") } }
        } label: { Label("Vistas", systemImage: "rectangle.stack") }
        .fixedSize()
        .popover(isPresented: $showSave) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nombre de la vista").font(.headline)
                TextField("p. ej. Pendientes por fecha", text: $newViewName).frame(width: 240).onSubmit { saveView(current) }
                Button("Guardar") { saveView(current) }.buttonStyle(.borderedProminent).disabled(newViewName.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(14)
        }
    }

    private func saveView(_ current: String) {
        let name = newViewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var v = query
        v.name = name
        saved.removeAll { $0.name == name }
        saved.append(v)
        query = v
        BaseViewStore.save(saved, for: current)
        showSave = false
    }
}
