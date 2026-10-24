import SwiftUI

// MARK: - Edición de filas y tareas

struct RowSpec: Identifiable {
    enum Mode { case edit(line: Int), add(afterLine: Int, headerLine: Int) }
    let id = UUID()
    var file: String
    var mode: Mode
    var title: String = "Fila"
    var prefill: [String]? = nil
}

struct RowSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let spec: RowSpec
    @State private var header: [String] = []
    @State private var cells: [String] = []
    @State private var first = ""
    @State private var confirmDelete = false

    private var isEdit: Bool { if case .edit = spec.mode { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEdit ? "Editar \(spec.title)" : "Añadir a \(spec.title)").font(.title3.weight(.semibold))
            if header.isEmpty {
                Text("No encuentro la tabla. Puede haber cambiado en otro sitio.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(header.indices, id: \.self) { i in
                        GridRow {
                            Text(header[i]).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            TextField("", text: Binding(get: { i < cells.count ? cells[i] : "" }, set: { if i < cells.count { cells[i] = $0 } }))
                                .frame(minWidth: 320)
                        }
                    }
                }
            }
            HStack {
                if isEdit {
                    if confirmDelete {
                        Button("Confirmar eliminar", role: .destructive) { delete() }
                    } else {
                        Button("Eliminar", role: .destructive) { confirmDelete = true }
                    }
                }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(header.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 520)
        .onAppear(perform: load)
    }

    private func load() {
        switch spec.mode {
        case .edit(let line):
            guard let r = store.rowCells(file: spec.file, line: line) else { return }
            header = r.header; cells = r.cells; first = r.cells.first ?? ""
            while cells.count < header.count { cells.append("") }
        case .add(_, let headerLine):
            header = store.tableHeader(file: spec.file, headerLine: headerLine)
            cells = [String](repeating: "", count: header.count)
            if let p = spec.prefill { for (i, v) in p.enumerated() where i < cells.count { cells[i] = v } }
        }
    }

    private func save() {
        switch spec.mode {
        case .edit(let line): store.updateRow(file: spec.file, line: line, expectFirst: first, cells: cells)
        case .add(let after, _): store.insertRow(file: spec.file, afterLine: after, cells: cells)
        }
        dismiss()
    }

    private func delete() {
        if case .edit(let line) = spec.mode { store.deleteRow(file: spec.file, line: line, expectFirst: first) }
        dismiss()
    }
}

struct TaskSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    @State private var text = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var priority = 0
    @State private var hasTime = false
    @State private var time = TimeOfDay.date(10 * 60)
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Editar tarea").font(.title3.weight(.semibold))
            TextField("Texto", text: $text).frame(minWidth: 420)
            Picker("Prioridad", selection: $priority) { Text("Ninguna").tag(0); Text("Baja").tag(1); Text("Media").tag(2); Text("Alta").tag(3) }.pickerStyle(.segmented).frame(width: 360)
            HStack {
                Toggle("Fecha límite", isOn: $hasDue).toggleStyle(.checkbox)
                DatePicker("", selection: $due, displayedComponents: .date).labelsHidden().disabled(!hasDue)
                Toggle("A las", isOn: $hasTime).toggleStyle(.checkbox).disabled(!hasDue)
                DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute).labelsHidden().disabled(!hasDue || !hasTime).fixedSize()
            }
            Text("Está en la nota \(task.noteName).").font(.caption).foregroundStyle(.secondary)
            HStack {
                if confirmDelete { Button("Confirmar eliminar", role: .destructive) { store.deleteTask(task); dismiss() } }
                else { Button("Eliminar", role: .destructive) { confirmDelete = true } }
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    store.updateTask(task, text: text, due: hasDue ? DayKey.calendar().startOfDay(for: due) : nil, priority: priority,
                                     time: .some(hasDue && hasTime ? TimeOfDay.minutes(of: time) : nil))
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .onAppear {
            text = task.text; hasDue = task.due != nil; due = task.due ?? Date(); priority = task.priority
            hasTime = task.time != nil; if let t = task.time { time = TimeOfDay.date(t) }
        }
    }
}

struct EditButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "pencil").accessibilityLabel("Editar") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Editar")
    }
}
