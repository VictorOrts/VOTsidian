import SwiftUI

struct RemindersView: View {
    @Environment(Store.self) private var store
    @AppStorage("remMounjaro") private var medicacion = true
    @AppStorage("remMounjaroMin") private var medicacionMin = 540
    @AppStorage("remReview") private var review = true
    @AppStorage("remReviewDay") private var reviewDay = 1
    @AppStorage("remReviewMin") private var reviewMin = 1140
    @AppStorage("remWeight") private var weightOn = true
    @AppStorage("remWeightMin") private var weightMin = 540
    @AppStorage("remTasks") private var tasksOn = true
    @AppStorage("remNala") private var mascotaOn = true
    @AppStorage("remBirthdays") private var birthdays = true
    @AppStorage("remDocs") private var docs = true
    @AppStorage("remEvents") private var eventsOn = true
    @AppStorage("remPayments") private var payments = true
    @AppStorage("systemNotifications") private var systemNotifications = false
    @State private var message = ""

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date())! },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
        )
    }

    private var plan: ReminderPlan {
        ReminderPlan(medicacion: medicacion, medicacionMinutes: medicacionMin, review: review, reviewWeekday: reviewDay, reviewMinutes: reviewMin,
                     monthlyWeight: weightOn, weightMinutes: weightMin, tasks: tasksOn, mascota: mascotaOn,
                     birthdays: birthdays, documents: docs, events: eventsOn, payments: payments)
    }

    /// Fila de un aviso: nombre, sus ajustes (día, hora) y el interruptor, todo en la misma línea.
    private func row<Extra: View>(_ title: String, _ on: Binding<Bool>, @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(on.wrappedValue ? .primary : .secondary)
            Spacer()
            extra().disabled(!on.wrappedValue).opacity(on.wrappedValue ? 1 : 0.4)
            Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func hour(_ minutes: Binding<Int>) -> some View {
        DatePicker("Hora", selection: time(minutes), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
    }

    var body: some View {
        let events = ICS.events(store.reminderSources(), plan: store.reminderPlan(plan))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let now = store.alerts()
                Card(title: now.isEmpty ? "Todo al día" : "Ahora mismo", icon: now.isEmpty ? "checkmark.seal" : "bell.badge",
                     info: "Lo que pide atención hoy, de más a menos urgente. Pulsa un aviso para ir a su pantalla; algunos se resuelven con su botón.") {
                    AlertList(alerts: now, go: { store.screen = $0 })
                }
                Card(title: "Qué recordar", icon: "bell") {
                    // Solo los de los módulos que se usan (y los de la base: revisión y tareas).
                    VStack(spacing: 6) {
                        if store.isVisible(.medicacion) {
                            row("Medicación (\(plural(store.medicacion.active().filter { !$0.asNeeded }.count, "medicamento", "medicamentos")); con hora, a esa hora)", $medicacion) { hour($medicacionMin) }
                            Divider()
                        }
                        row("Revisión semanal", $review) {
                            Picker("Día", selection: $reviewDay) {
                                ForEach([(2, "Lunes"), (3, "Martes"), (4, "Miércoles"), (5, "Jueves"), (6, "Viernes"), (7, "Sábado"), (1, "Domingo")], id: \.0) { Text($0.1).tag($0.0) }
                            }.labelsHidden().fixedSize()
                            hour($reviewMin)
                        }
                        Divider()
                        if store.isVisible(.peso) {
                            row("Pesaje mensual (último día del mes)", $weightOn) { hour($weightMin) }
                            Divider()
                        }
                        row("Tareas con fecha", $tasksOn)
                        if store.isVisible(.mascota) { Divider(); row("Citas y vacunas de \(store.mascota.name)", $mascotaOn) }
                        if store.isVisible(.personas) { Divider(); row("Cumpleaños (cada año)", $birthdays) }
                        if store.isVisible(.documentos) { Divider(); row("Caducidad de documentos (30 días antes)", $docs) }
                        if store.isVisible(.finanzas) || store.isVisible(.casa) { Divider(); row("Eventos y fechas de Casa (7 días antes)", $eventsOn) }
                        if store.isVisible(.gastos) { Divider(); row("Pagos fijos de Gastos (el día antes y el mismo día)", $payments) }
                    }
                }

                // Las dos formas de recibir los avisos, juntas.
                Card(title: "Cómo recibirlos", icon: "paperplane",
                     info: "Cada evento tiene un identificador fijo. Si vuelves a importar, Calendar actualiza los eventos en vez de duplicarlos. Las notificaciones de macOS solo funcionan en la app (build-app.sh), no con swift run.") {
                    HStack {
                        Label("Calendar", systemImage: "calendar")
                        Spacer()
                        Button("Añadir a Calendar") {
                            message = ICS.openInCalendar(events)
                                ? "Calendar se abrió con \(plural(events.count, "evento", "eventos")). Confirma la importación."
                                : "No se pudo crear el archivo de avisos."
                        }.buttonStyle(.borderedProminent)
                    }
                    Divider()
                    HStack {
                        Label("Notificaciones de macOS (próximos \(Notifier.horizonDays) días)", systemImage: "bell.badge")
                        Spacer()
                        Toggle("Notificaciones de macOS", isOn: $systemNotifications).labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .onChange(of: systemNotifications) { _, on in
                                Task {
                                    if on {
                                        if let n = await Notifier.schedule(events) { message = "\(n) avisos programados para los próximos \(Notifier.horizonDays) días." }
                                        else { systemNotifications = false; message = Notifier.available ? "macOS no dio permiso para notificar." : "Solo funcionan en la app (build-app.sh), no con swift run." }
                                    } else { Notifier.cancelAll() }
                                }
                            }
                    }
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                }

                Card(title: events.count == 1 ? "Se creará 1 evento" : "Se crearán \(events.count) eventos", icon: "list.bullet") {
                    ForEach(events.prefix(14)) { e in
                        HStack {
                            Text(MDParser.inline(e.title))
                            Spacer()
                            Text(dayLabel(e.start) + (e.minutes.map { String(format: " %02d:%02d", $0 / 60, $0 % 60) } ?? "") + (e.rule != nil ? " · se repite" : ""))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if events.count > 14 { Text("y \(events.count - 14) más").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Avisos")
    }
}
