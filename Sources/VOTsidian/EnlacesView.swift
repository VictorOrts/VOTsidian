import SwiftUI

/// Enlaces `[[…]]` que no llevan a ninguna nota, agrupados por la nota donde están, con arreglo uno a uno.
struct EnlacesView: View {
    @Environment(Store.self) private var store
    @State private var broken: [Store.BrokenLink] = []
    @State private var isolated: [NoteFile] = []
    @State private var repairMessage = ""

    private var groups: [(path: String, links: [Store.BrokenLink])] {
        Dictionary(grouping: broken, by: \.path).map { ($0.key, $0.value) }.sorted { MD.fold($0.path) < MD.fold($1.path) }
    }

    var body: some View {
        let _ = BodyCounter.hit("EnlacesView")
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Enlaces rotos", icon: "link", info: "Los enlaces a pantallas de la app (Tareas, Calendario, Hábitos…) funcionan y no cuentan como rotos.") {
                    if broken.isEmpty {
                        Label("Todos los enlaces funcionan.", systemImage: "checkmark.seal").foregroundStyle(Brand.accent)
                    } else {
                        Text("\(broken.count) \(broken.count == 1 ? "enlace no lleva" : "enlaces no llevan") a ninguna nota. Elige la nota que querías, crea la que falta o abre la nota para corregirlo a mano.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Reparar los que tienen sugerencia clara") { repairMessage = "Reparados: \(store.repairLinks())" }
                                .disabled(!broken.contains { $0.suggestion != nil })
                            Text(repairMessage).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(groups, id: \.path) { g in
                    Card(title: ((g.path as NSString).lastPathComponent as NSString).deletingPathExtension, icon: "doc.text",
                         actionTitle: "Abrir", action: { store.pendingNote = g.path }) {
                        ForEach(g.links) { b in row(b) }
                    }
                }
                if !isolated.isEmpty {
                    Card(title: "Notas sin ningún enlace", icon: "point.3.connected.trianglepath.dotted", info: "Ni enlazan ni las enlaza nadie.") {
                        FlowLinks(names: isolated.map(\.name)) { name in
                            if let n = isolated.first(where: { $0.name == name }) { store.pendingNote = n.path }
                        }
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Enlaces rotos")
        // Cambian los enlaces o la lista de notas (también un renombrado hecho fuera de la app, que no cambia cuántas hay).
        .task(id: [store.linksVersion, store.notes.map(\.path).hashValue]) {
            broken = store.brokenLinks()
            isolated = store.isolatedNotes()
        }
    }

    private func row(_ b: Store.BrokenLink) -> some View {
        HStack(spacing: 8) {
            Text("[[\(b.target)]]").font(.callout.monospaced())
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            if b.candidates.isEmpty { Text("sin notas parecidas").foregroundStyle(Brand.warn) }
            ForEach(b.candidates, id: \.self) { c in
                Button(c) { store.fixLink(b, to: c) }
                    .help("Cambiar el enlace por [[\(c)]]")
                    .tint(c == b.suggestion ? Brand.accent : nil)
            }
            Spacer()
            Button("Crear nota") { store.createMissingNote(b) }.help("Crea «\(b.target)» en la misma carpeta")
        }
    }
}

/// Nombres pulsables que ocupan varias líneas si hace falta.
private struct FlowLinks: View {
    let names: [String]
    let open: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(names, id: \.self) { n in Button(n) { open(n) }.buttonStyle(.accentLink).lineLimit(1) }
        }
    }
}
