import SwiftUI

struct PrestamosView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.prestamos
    @State private var name = ""
    @State private var pending = ""
    @State private var installment = ""
    @State private var day = ""
    @State private var category = ""
    @State private var toGastos = true
    @State private var message = ""

    var body: some View {
        let p = store.prestamos
        let today = DayKey.today()
        let statuses = p.statuses(today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .prestamos)
                HStack(spacing: 12) {
                    Tile(title: "Debes", value: Money.format(p.totalRemaining(today: today)), note: statuses.isEmpty ? nil : "\(plural(statuses.filter { !$0.isPaidOff }.count, "préstamo o deuda", "préstamos o deudas"))")
                    Tile(title: "Cuotas al mes", value: Money.format(p.monthlyInstallments(today: today)))
                    Tile(title: "Acabas", value: statuses.compactMap(\.estimatedEnd).max().map { DayKey.esLong($0, .dateTime.month(.abbreviated).year()) } ?? "–",
                         note: statuses.compactMap(\.estimatedEnd).max() == nil ? nil : "cuando termines el último")
                }
                Card(title: "Avisos", icon: "bell", info: "Avisa 3 días antes de la cuota si aún no la has apuntado este mes.") {
                    let alerts = store.prestamoAlerts(today: today)
                    AlertList(alerts: alerts, emptyText: "No hay cuotas cerca.")
                }
                if statuses.isEmpty {
                    Card(title: "Préstamos y deudas", icon: "creditcard.and.123") {
                        EmptyNote("Añade un préstamo o una deuda abajo.", icon: "creditcard.and.123")
                    }
                }
                ForEach(statuses) { s in
                    Card(title: s.loan.name, icon: s.isPaidOff ? "checkmark.seal" : "creditcard.and.123") {
                        if s.loan.initial > 0 { ProgressView(value: s.progress).tint(s.isPaidOff ? Brand.good : Brand.accent) }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.isPaidOff ? "Pagado" : "Quedan \(Money.exact(s.remaining))").font(.title3.weight(.semibold))
                                Text("de \(Money.exact(s.loan.initial)) · pagado \(Money.exact(s.paid))").font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let n = s.installmentsLeft { Text("\(plural(n, "cuota", "cuotas")) de \(Money.exact(s.loan.installment))") }
                                if let e = s.estimatedEnd { Text("acabas en \(DayKey.esLong(e, .dateTime.month(.wide).year()))").font(.callout).foregroundStyle(.secondary) }
                            }
                        }
                        HStack {
                            if let d = s.nextDue {
                                let n = DayKey.days(from: today, to: d)
                                Label("Próxima cuota: \(DayKey.dmy(d)) (\(relativeDays(n)))", systemImage: "calendar").foregroundStyle(n <= 3 ? Brand.warn : .secondary)
                            }
                            if s.missed { Label("La de este mes no está apuntada", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn) }
                            Spacer()
                            if !s.isPaidOff {
                                let amount = s.loan.installment > 0 ? min(s.loan.installment, s.remaining) : 0
                                if s.paidThisMonth && amount > 0 {
                                    Label("Cuota de este mes apuntada", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                                } else if amount > 0 {
                                    Button("Apuntar cuota (\(Money.exact(amount)))") {
                                        store.addPrestamoPago(s.loan, amount: amount, expense: toGastos && store.isVisible(.gastos))
                                        message = ""
                                    }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Card(title: "Apuntar un pago", icon: "plus.circle", info: "Para una cuota distinta o un pago extra. Baja lo que debes en la nota Pagos.") {
                    PagoForm(loans: p.loans, toGastos: $toGastos)
                }
                Card(title: "Añadir préstamo o deuda", icon: "plus.circle") {
                    HStack {
                        TextField("Nombre (Hipoteca, Coche, Ana…)", text: $name)
                        TextField("Debes ahora", text: $pending).frame(width: 110)
                        TextField("Cuota", text: $installment).frame(width: 90)
                        TextField("Día", text: $day).frame(width: 50)
                    }
                    HStack {
                        ChoiceMenu(options: [""] + store.expenseCategories, current: category, width: 200, emptyLabel: "Partida de Gastos") { category = $0 }
                        Spacer()
                        Button("Guardar") {
                            store.addPrestamo(name: name.trimmingCharacters(in: .whitespaces), initial: Money.parse(pending), installment: Money.parse(installment) > 0 ? Money.parse(installment) : nil,
                                              day: MD.int(MD.number(day)).flatMap { (1...31).contains($0) ? $0 : nil }, until: nil, category: category)
                            name = ""; pending = ""; installment = ""; day = ""
                        }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money.parse(pending) <= 0)
                    }
                }
                if store.isVisible(.gastos) {
                    Toggle("Apuntar también las cuotas en Gastos", isOn: $toGastos).toggleStyle(.checkbox)
                }
                NoteTables(file: file, icon: "tablecells")
                Button("Abrir la nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Préstamos y deudas")
    }
}

/// Un pago suelto de cualquier importe a uno de los préstamos.
private struct PagoForm: View {
    @Environment(Store.self) private var store
    let loans: [PrestamosData.Loan]
    @Binding var toGastos: Bool
    @State private var loan = ""
    @State private var amount = ""
    @State private var date = Date()

    var body: some View {
        let chosen = loans.first { $0.name == loan } ?? loans.first
        HStack {
            ChoiceMenu(options: loans.map(\.name), current: chosen?.name ?? "", width: 180) { loan = $0 }
            TextField("Importe", text: $amount).frame(width: 100)
            DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).fixedSize()
            Spacer()
            Button("Guardar") {
                guard let chosen else { return }
                store.addPrestamoPago(chosen, amount: Money.parse(amount), date: DayKey.calendar().startOfDay(for: date), expense: toGastos && store.isVisible(.gastos))
                amount = ""
            }.buttonStyle(.borderedProminent).disabled(chosen == nil || Money.parse(amount) <= 0)
        }
    }
}
