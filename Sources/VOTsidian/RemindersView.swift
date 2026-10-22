import SwiftUI

struct RemindersView: View {
    @Environment(Store.self) private var store
    @AppStorage("remMounjaro") private var mounjaro = true
    @AppStorage("remMounjaroMin") private var mounjaroMin = 540
    @AppStorage("remReview") private var review = true
    @AppStorage("remReviewDay") private var reviewDay = 1
    @AppStorage("remReviewMin") private var reviewMin = 1140
    @AppStorage("remWeight") private var weightOn = true
    @AppStorage("remWeightMin") private var weightMin = 540
    @AppStorage("remTasks") private var tasksOn = true
    @AppStorage("remNala") private var nalaOn = true
    @AppStorage("remBirthdays") private var birthdays = true
    @AppStorage("remDocs") private var docs = true
    @AppStorage("remEvents") private var eventsOn = true
    @AppStorage("systemNotifications") private var systemNotifications = false
    @State private var message = ""

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date())! },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
        )
    }

    private var plan: ReminderPlan {
        ReminderPlan(mounjaro: mounjaro, mounjaroMinutes: mounjaroMin, review: review, reviewWeekday: reviewDay, reviewMinutes: reviewMin,
                     monthlyWeight: weightOn, weightMinutes: weightMin, tasks: tasksOn, nala: nalaOn,
                     birthdays: birthdays, documents: docs, events: eventsOn)
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
        let events = ICS.events(store.reminderSources(), plan: plan)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Qué recordar", icon: "bell") {
                    VStack(spacing: 6) {
                        row("Pinchazo de Mounjaro (cada \(store.mounjaro.everyDays) días)", $mounjaro) { hour($mounjaroMin) }
                        Divider()
                        row("Revisión semanal", $review) {
                            Picker("Día", selection: $reviewDay) {
                                ForEach([(2, "Lunes"), (3, "Martes"), (4, "Miércoles"), (5, "Jueves"), (6, "Viernes"), (7, "Sábado"), (1, "Domingo")], id: \.0) { Text($0.1).tag($0.0) }
                            }.labelsHidden().fixedSize()
                            hour($reviewMin)
                        }
                        Divider()
                        row("Pesaje mensual (último día del mes)", $weightOn) { hour($weightMin) }
                        Divider()
                        row("Tareas con fecha", $tasksOn)
                        Divider()
                        row("Citas y vacunas de \(store.nala.name)", $nalaOn)
                        Divider()
                        row("Cumpleaños (cada año)", $birthdays)
                        Divider()
                        row("Caducidad de documentos (30 días antes)", $docs)
                        Divider()
                        row("Eventos y fechas de Casa (7 días antes)", $eventsOn)
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
                                ? "Calendar se abrió con \(events.count) eventos. Confirma la importación."
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

                Card(title: "Se crearán \(events.count) eventos", icon: "list.bullet") {
                    ForEach(events.prefix(14)) { e in
                        HStack {
                            Text(MDParser.inline(e.title))
                            Spacer()
                            Text(shortDate(e.start) + (e.minutes.map { String(format: " %02d:%02d", $0 / 60, $0 % 60) } ?? "") + (e.rule != nil ? " · se repite" : ""))
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
