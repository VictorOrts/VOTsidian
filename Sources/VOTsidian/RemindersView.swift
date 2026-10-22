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

    var body: some View {
        let events = ICS.events(store.reminderSources(), plan: plan)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Qué quieres que te recuerde Calendar").font(.title3.weight(.semibold))
                Form {
                    Toggle("Pinchazo de Mounjaro (cada \(store.mounjaro.everyDays) días)", isOn: $mounjaro)
                    DatePicker("Hora", selection: time($mounjaroMin), displayedComponents: .hourAndMinute).disabled(!mounjaro)
                    Toggle("Revisión semanal", isOn: $review)
                    Picker("Día", selection: $reviewDay) {
                        ForEach([(2, "Lunes"), (3, "Martes"), (4, "Miércoles"), (5, "Jueves"), (6, "Viernes"), (7, "Sábado"), (1, "Domingo")], id: \.0) { Text($0.1).tag($0.0) }
                    }.disabled(!review)
                    DatePicker("Hora", selection: time($reviewMin), displayedComponents: .hourAndMinute).disabled(!review)
                    Toggle("Pesaje mensual (último día del mes)", isOn: $weightOn)
                    DatePicker("Hora", selection: time($weightMin), displayedComponents: .hourAndMinute).disabled(!weightOn)
                    Toggle("Tareas con fecha 📅", isOn: $tasksOn)
                    Toggle("Citas y vacunas de \(store.nala.name)", isOn: $nalaOn)
                    Toggle("Cumpleaños (se repiten cada año)", isOn: $birthdays)
                    Toggle("Caducidad de documentos (aviso 30 días antes)", isOn: $docs)
                    Toggle("Eventos y fechas de Casa (aviso 7 días antes)", isOn: $eventsOn)
                }.formStyle(.grouped).scrollDisabled(true).frame(maxWidth: 560, minHeight: 560)

                HStack {
                    Button("Añadir a Calendar") {
                        message = ICS.openInCalendar(events)
                            ? "Calendar se abrió con \(events.count) eventos. Confirma la importación."
                            : "No se pudo crear el archivo de avisos."
                    }.buttonStyle(.borderedProminent)
                    Text(message).foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("Avisos del sistema (notificaciones de macOS)", isOn: $systemNotifications)
                        .onChange(of: systemNotifications) { _, on in
                            Task {
                                if on {
                                    if let n = await Notifier.schedule(events) { message = "\(n) avisos programados para los próximos \(Notifier.horizonDays) días." }
                                    else { systemNotifications = false; message = Notifier.available ? "macOS no dio permiso para notificar." : "Solo funcionan en la app (build-app.sh), no con swift run." }
                                } else { Notifier.cancelAll() }
                            }
                        }
                }
                Text("Cada evento tiene un identificador fijo. Si vuelves a importar, Calendar actualiza los eventos en vez de duplicarlos.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("Se crearán \(events.count) eventos").font(.headline)
                ForEach(events.prefix(14)) { e in
                    HStack {
                        Text(e.title)
                        Spacer()
                        Text(shortDate(e.start) + (e.minutes.map { String(format: " %02d:%02d", $0 / 60, $0 % 60) } ?? "") + (e.rule != nil ? " · se repite" : ""))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Avisos")
    }
}
