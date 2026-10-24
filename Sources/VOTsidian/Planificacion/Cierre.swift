import SwiftUI

/// Repaso de fin de día (como Sunsama): lo vencido y lo de hoy, con un toque para completar o aplazar, y preparar mañana.
struct CierreSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tomorrow = ""
    @State private var message = ""

    private var pending: [TaskItem] {
        let today = DayKey.today()
        return store.tasks.filter { !$0.done && ($0.due.map { $0 <= today } ?? false) }
            .sorted { a, b in a.priority != b.priority ? a.priority > b.priority : (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
    }

    var body: some View {
        let list = pending
        let doneToday = store.tasks.filter { $0.done && $0.completed == DayKey.today() }
        VStack(alignment: .leading, spacing: 14) {
            Text("Cerrar el día").font(.title2.weight(.semibold))
            Text(doneToday.isEmpty ? "Hoy aún no has completado tareas con fecha." : "Hoy completaste \(doneToday.count) \(doneToday.count == 1 ? "tarea" : "tareas"). Buen trabajo.")
                .foregroundStyle(.secondary)
            if list.isEmpty {
                Label("No queda nada vencido ni para hoy.", systemImage: "checkmark.seal.fill").foregroundStyle(Brand.accent)
            } else {
                Text("Pendiente (\(list.count))").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(list) { t in
                            HStack(spacing: 8) {
                                if t.priority > 0 { Image(systemName: "flag.fill").font(.caption).foregroundStyle(t.priority == 3 ? Brand.bad : Brand.warn) }
                                Text(MDParser.inline(t.text)).lineLimit(2)
                                if let d = t.due, d < DayKey.today() { Text("vencida \(dayLabel(d))").font(.caption).foregroundStyle(Brand.bad) }
                                Spacer()
                                Button("Hecha") { store.setTask(t, done: true) }.controlSize(.small)
                                Button("Mañana") { store.reschedule(t, to: DayKey.adding(days: 1, to: DayKey.today())) }.controlSize(.small)
                                Button("Lunes") { store.reschedule(t, to: nextMonday()) }.controlSize(.small)
                            }
                        }
                    }
                }.frame(maxHeight: 260)
            }
            Divider()
            Text("Preparar mañana").font(.headline)
            HStack {
                TextField("Una tarea para mañana (puedes escribir «el viernes», «urgente»…)", text: $tomorrow).onSubmit(add)
                Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(tomorrow.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !message.isEmpty { Label(message, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent) }
            HStack {
                Button { store.openToday(); dismiss() } label: { Label("Escribir la nota de hoy", systemImage: "note.text") }
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 660)
    }

    private func nextMonday() -> Date {
        let wd = DayKey.calendar().component(.weekday, from: DayKey.today())
        let delta = (9 - wd) % 7
        return DayKey.adding(days: delta == 0 ? 7 : delta, to: DayKey.today())
    }

    private func add() {
        let raw = tomorrow.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        message = store.addTask(NaturalDate.extractTask(raw), defaultDue: DayKey.adding(days: 1, to: DayKey.today()))
        tomorrow = ""
    }
}
