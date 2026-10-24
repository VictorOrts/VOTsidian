import SwiftUI

struct TramitesView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.tramites
    @State private var toGastos = true
    @State private var message = ""

    var body: some View {
        let d = store.tramites
        let today = DayKey.today()
        let pending = d.pendingProcedures
        let done = d.procedures.filter { $0.pending == nil }
        let renewals = d.insurances.compactMap { i in i.nextRenewal(from: today).map { (i, $0) } }.sorted { $0.1 < $1.1 }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .tramites)
                HStack(spacing: 12) {
                    Tile(title: "Próximo plazo", value: pending.first?.procedure.name ?? "–",
                         note: pending.first.map { "\(relativeDays(DayKey.days(from: today, to: $0.due))) · \(DayKey.dmy($0.due))" },
                         tint: pending.first.map { $0.due < today ? Brand.bad : nil } ?? nil)
                    Tile(title: "Seguros al año", value: Money.format(d.yearlyInsurance), note: d.insurances.isEmpty ? nil : plural(d.insurances.count, "póliza", "pólizas"))
                    Tile(title: "Pendientes", value: "\(pending.filter { DayKey.days(from: today, to: $0.due) <= 60 }.count)", note: "en los próximos 60 días")
                }
                Card(title: "Avisos", icon: "bell",
                     info: "Avisa 30 días antes de cada plazo (y cuando ya pasó sin marcarlo hecho) y 30 días antes de que se renueve un seguro, para que compares ofertas.") {
                    AlertList(alerts: store.tramiteAlerts(today: today), emptyText: "Ningún plazo cerca.")
                }
                Card(title: "Plazos", icon: "building.columns",
                     info: "«Hecho» pone la fecha de hoy y calcula el siguiente plazo de los que se repiten. Con «Apuntar también en Gastos», el importe va al mes.") {
                    if pending.isEmpty { EmptyNote("Ningún trámite pendiente. Añade la renta, el IBI… abajo.", icon: "building.columns") }
                    ForEach(pending, id: \.procedure.id) { entry in
                        let p = entry.procedure, n = DayKey.days(from: today, to: entry.due)
                        HStack(spacing: 10) {
                            Image(systemName: n < 0 ? "exclamationmark.octagon.fill" : n <= 30 ? "exclamationmark.triangle.fill" : "calendar")
                                .foregroundStyle(n < 0 ? Brand.bad : n <= 30 ? Brand.warn : Brand.accent).frame(width: 18)
                                .accessibilityLabel(n < 0 ? "Plazo vencido" : n <= 30 ? "Plazo cerca" : "Con tiempo")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).fontWeight(.medium)
                                Text([p.period?.label, p.done.map { "hecho por última vez el \(DayKey.dmy($0))" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let a = p.amount { Text(Money.exact(a)).monospacedDigit() }
                            Text(DayKey.dmy(entry.due)).monospacedDigit().foregroundStyle(.secondary)
                            Text(n < 0 ? "venció \(relativeDays(n))" : relativeDays(n)).foregroundStyle(n < 0 ? Brand.bad : .secondary).lineLimit(1).frame(width: 140, alignment: .trailing)
                            Button("Hecho") { store.markTramiteDone(p, expense: toGastos && store.isVisible(.gastos)) }.controlSize(.small)
                        }
                    }
                    if !done.isEmpty {
                        Divider()
                        ForEach(done) { p in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.good).frame(width: 18).accessibilityLabel("Hecho")
                                Text(p.name).foregroundStyle(.secondary)
                                Spacer()
                                Text(p.done.map { "hecho el \(DayKey.dmy($0))" } ?? "").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.isVisible(.gastos) { Toggle("Apuntar también en Gastos al marcarlo hecho", isOn: $toGastos).toggleStyle(.checkbox).font(.callout) }
                }
                Card(title: "Seguros", icon: "shield.lefthalf.filled",
                     info: "La renovación es el día que se renueva y se cobra. «Apuntar pago» lleva la prima a Gastos, a la partida de la fila o a la de seguros.") {
                    if d.insurances.isEmpty { EmptyNote("Añade tus pólizas abajo: hogar, coche, salud, vida…", icon: "shield") }
                    ForEach(d.insurances) { i in
                        let r = renewals.first { $0.0.id == i.id }?.1
                        HStack(spacing: 10) {
                            Image(systemName: "shield.lefthalf.filled").foregroundStyle(Brand.info).frame(width: 18).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.name).fontWeight(.medium)
                                Text([i.company, i.policy.isEmpty ? nil : "póliza \(i.policy)", i.phone.isEmpty ? nil : "☎ \(i.phone)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            if i.premium > 0 { Text("\(Money.exact(i.premium)) \(i.period.label)").monospacedDigit() }
                            if let r { Text("renueva \(relativeDays(DayKey.days(from: today, to: r)))").foregroundStyle(DayKey.days(from: today, to: r) <= 30 ? Brand.warn : .secondary) }
                            if store.isVisible(.gastos), i.premium > 0 {
                                if store.seguroLogged(i) { Label("Apuntado", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary) }
                                else { Button("Apuntar pago") { message = store.logSeguroPayment(i).map { "Apuntado en \($0)." } ?? "No hay partidas en Gastos." }.controlSize(.small) }
                            }
                        }
                    }
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                Card(title: "Añadir trámite", icon: "plus.circle") { TramiteForm() }
                Card(title: "Añadir seguro", icon: "plus.circle") { SeguroForm() }
                NoteTables(file: file, icon: "tablecells")
                Button("Abrir la nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Trámites y seguros")
    }
}

private struct TramiteForm: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var due = Date()
    @State private var every = "Anual"
    @State private var amount = ""

    var body: some View {
        HStack {
            TextField("Trámite (renta, IBI, basuras…)", text: $name)
            DatePicker("Plazo", selection: $due, displayedComponents: .date).fixedSize()
            ChoiceMenu(options: ["Una vez", "Anual", "Semestral", "Trimestral", "Mensual"], current: every, width: 110) { every = $0 }
            TextField("Importe", text: $amount).frame(width: 90)
            Button("Guardar") {
                store.addTramite(name: name.trimmingCharacters(in: .whitespaces), due: DayKey.calendar().startOfDay(for: due), every: every == "Una vez" ? "" : every,
                                 amount: Money.parse(amount) > 0 ? Money.parse(amount) : nil)
                name = ""; amount = ""
            }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

private struct SeguroForm: View {
    @Environment(Store.self) private var store
    @State private var name = ""
    @State private var company = ""
    @State private var premium = ""
    @State private var every = "Anual"
    @State private var hasRenewal = true
    @State private var renewal = Date()
    @State private var phone = ""
    @State private var category = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Seguro (hogar, coche…)", text: $name)
                TextField("Compañía", text: $company)
                TextField("Prima", text: $premium).frame(width: 90)
                ChoiceMenu(options: ["Anual", "Semestral", "Trimestral", "Mensual"], current: every, width: 110) { every = $0 }
            }
            HStack {
                Toggle("Renovación", isOn: $hasRenewal).toggleStyle(.checkbox)
                DatePicker("", selection: $renewal, displayedComponents: .date).labelsHidden().disabled(!hasRenewal).fixedSize()
                TextField("Teléfono de asistencia", text: $phone).frame(width: 180)
                ChoiceMenu(options: [""] + store.expenseCategories, current: category, width: 180, emptyLabel: "Partida de Gastos") { category = $0 }
                Spacer()
                Button("Guardar") {
                    store.addSeguro(name: name.trimmingCharacters(in: .whitespaces), company: company, premium: Money.parse(premium), every: every,
                                    renewal: hasRenewal ? DayKey.calendar().startOfDay(for: renewal) : nil, phone: phone, category: category)
                    name = ""; company = ""; premium = ""; phone = ""
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
