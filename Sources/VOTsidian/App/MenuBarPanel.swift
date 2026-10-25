import SwiftUI

/// Resumen rápido en la barra de menús: lo de hoy, sin abrir la ventana principal.
struct MenuBarPanel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var message = ""

    private var today: Date { DayKey.today() }

    private var tasksToday: [TaskItem] {
        store.tasks.filter { !$0.done && ($0.due.map { $0 <= today } ?? false) }
            .sorted { a, b in a.priority != b.priority ? a.priority > b.priority : (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
    }

    var body: some View {
        let _ = BodyCounter.hit("MenuBarPanel")
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            quickAdd
            habitsRow
            medsRow
            tasksList
            Divider()
            HStack {
                Button { show() } label: { Label("Abrir", systemImage: "macwindow") }
                Button { show(); store.openToday() } label: { Label("Nota de hoy", systemImage: "note.text") }
                Button { show(); store.showEmpezar = true } label: { Label("Empezar", systemImage: "sunrise") }
                Button { show(); store.showCierre = true } label: { Label("Cerrar el día", systemImage: "moon.stars") }
                Spacer()
            }.controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: Partes

    /// Peso y medicación periódica, si se usan; si no, la fecha de hoy.
    @ViewBuilder private var header: some View {
        let showWeight = store.isVisible(.peso) && store.weight.last != nil
        let showMed = store.isVisible(.medicacion) && store.medicacion.main != nil
        if !showWeight && !showMed {
            Text(capitalizedFirst(longDate(Date()))).font(.headline)
        } else {
            medsAndWeight(showWeight: showWeight, showMed: showMed)
        }
    }

    private func medsAndWeight(showWeight: Bool, showMed: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if showWeight {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PESO").font(.caption2).foregroundStyle(.secondary)
                    Text(store.weight.last.map { fmt($0.kg, unit: " kg") } ?? "–").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    if store.weight.hasGoal { Text("faltan \(fmt(store.weight.remainingKg)) kg").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if showWeight && showMed { Divider().frame(height: 44) }
            if showMed {
                VStack(alignment: .leading, spacing: 2) {
                    Text((store.medicacion.main?.act ?? "medicación").uppercased()).font(.caption2).foregroundStyle(.secondary)
                    if let n = store.medicacion.next, let d = store.medicacion.daysUntilNext {
                        Text(shortDate(n)).font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(d < 0 ? Brand.bad : d == 0 ? Brand.warn : Color.primary)
                        Text(dueDays(d)).font(.caption).foregroundStyle(.secondary)
                    } else { Text("–").font(.title2) }
                }
            }
            Spacer()
            if showMed, let main = store.medicacion.main, let d = store.medicacion.daysUntilNext, d <= 1, store.medicacion.last?.date != today {
                Button(main.isInjection ? "Me pinché hoy" : "Tomada hoy") { store.injectToday(); message = main.isInjection ? "Pinchazo registrado" : "Toma registrada" }
                    .controlSize(.small).buttonStyle(.borderedProminent)
            }
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptureField(compact: true)
            if !message.isEmpty { Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Brand.accent) }
        }
    }

    @ViewBuilder private var habitsRow: some View {
        let key = DayKey.weekKey(today)
        let dayIndex = (Calendar(identifier: .iso8601).component(.weekday, from: today) + 5) % 7
        if let r = store.reviews[key], !r.habits.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hábitos de hoy").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(r.habits, id: \.name) { h in
                        Button { store.toggleHabit(key: key, habit: h.name, day: dayIndex) } label: {
                            Text(h.name).font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(h.days[dayIndex] ? Brand.accent : Color.primary.opacity(0.08), in: Capsule())
                                .foregroundStyle(h.days[dayIndex] ? Color.white : Color.primary)
                        }.buttonStyle(.plain).help(h.criterion)
                    }
                }
            }
        }
    }

    /// Tomas diarias de hoy, con una casilla por toma.
    @ViewBuilder private var medsRow: some View {
        let daily = store.isVisible(.medicacion) ? store.medicacion.active(on: today).filter { $0.every == 1 } : []
        if !daily.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEDICACIÓN DE HOY").font(.caption2).foregroundStyle(.secondary)
                ForEach(daily) { med in
                    HStack(spacing: 8) { Text(med.name).lineLimit(1); Spacer(); IntakeChecks(med: med) }.font(.callout)
                }
            }
        }
    }

    @ViewBuilder private var tasksList: some View {
        let list = tasksToday
        VStack(alignment: .leading, spacing: 6) {
            Text(list.isEmpty ? "Sin tareas para hoy" : "Para hoy o vencidas (\(list.count))").font(.caption).foregroundStyle(.secondary)
            ForEach(list.prefix(6)) { t in
                HStack(spacing: 8) {
                    Button { store.setTask(t, done: true) } label: { Image(systemName: "circle").accessibilityLabel("Completar") }.buttonStyle(.plain).foregroundStyle(Brand.accent)
                    Text(MDParser.inline(t.text)).lineLimit(1).font(.callout)
                    Spacer()
                    if let d = t.due, d < today { Text("vencida").font(.caption2).foregroundStyle(Brand.bad) }
                }
            }
            if list.count > 6 { Text("y \(list.count - 6) más…").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func show() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
