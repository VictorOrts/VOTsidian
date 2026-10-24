import SwiftUI
import UniformTypeIdentifiers

struct NewNoteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folders: [String]
    var template0 = "En blanco"
    var folder0 = ""
    let created: (String) -> Void
    @State private var name = ""
    @State private var folder = ""
    @State private var template = "En blanco"
    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nueva nota").font(.title3.weight(.semibold))
            TextField("Nombre", text: $name).frame(minWidth: 380)
            Picker("Plantilla", selection: $template) {
                ForEach(NoteTemplates.names, id: \.self) { Text($0).tag($0) }
                let mine = store.userTemplates()
                if !mine.isEmpty { Divider(); ForEach(mine, id: \.self) { Text("★ \($0)").tag($0) } }
            }
            .onChange(of: template) {
                let f = NoteTemplates.names.contains(template) ? NoteTemplates.defaultFolder(template) : (store.userTemplate(template, title: "")?.folder ?? "")
                if !f.isEmpty { folder = f }
            }
            let questions = NoteTemplates.names.contains(template) ? [] : store.templateQuestions(template)
            if !questions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Datos de la plantilla").font(.subheadline.weight(.semibold))
                    ForEach(questions) { q in
                        TextField(q.label, text: Binding(get: { answers[q.label] ?? q.defaultValue }, set: { answers[q.label] = $0 }))
                    }
                }
            }
            if store.userTemplates().isEmpty {
                Button("Crear plantillas de ejemplo (\(SampleTemplates.names.joined(separator: ", ")))") { store.createSampleTemplates() }.buttonStyle(.accentLink).font(.caption)
            } else {
                Text("Tus plantillas están en la carpeta Plantillas. Variables: {{titulo}} {{fecha}} {{hora}} {{dia}} {{semana}}.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Carpeta", selection: $folder) {
                Text("(raíz)").tag("")
                ForEach(Array(Set(folders + [NoteTemplates.defaultFolder(template)].filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Crear") {
                    if let p = store.createNote(folder: folder, name: name, template: template, answers: answers) { dismiss(); created(p) }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(22)
         .onAppear { template = template0; folder = folder0 }
    }
}

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: String
    let rename: (String) -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Renombrar nota").font(.title3.weight(.semibold))
            TextField("Nombre", text: $name).frame(minWidth: 380)
            Text("Los enlaces [[\(current)]] de las demás notas se actualizan solos.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Renombrar") { dismiss(); rename(name) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == current)
            }
        }.padding(22).onAppear { name = current }
    }
}

/// Fila que salta de línea.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    var minimum: CGFloat = 120
    let content: (Item) -> Content
    init(_ items: [Item], minimum: CGFloat = 120, @ViewBuilder content: @escaping (Item) -> Content) { self.items = items; self.minimum = minimum; self.content = content }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 260), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}
