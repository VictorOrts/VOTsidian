import SwiftUI

struct FinanzasView: View {
    @Environment(Store.self) private var store
    @State private var showNew = false
    private let file = VaultPath.finanzas

    private var eventos: [(path: String, meta: [String: String])] {
        store.noteMeta.filter { $0.value["tipo"] == "evento" }.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    /// Resumen del mes de Gastos: lo justo para saber cómo va sin cambiar de pantalla.
    @ViewBuilder private var gastosCard: some View {
        let month = Budget.monthKey(DayKey.today())
        let year = DayKey.calendar().component(.year, from: DayKey.today())
        let y = store.budgetYear(year)
        Card(title: "Gastos de \(Budget.title(month).lowercased())", icon: "creditcard", actionTitle: "Abrir Gastos", action: { store.screen = .gastos }) {
            if let b = store.budget(month) {
                let s = BudgetStatus(b)
                TileRow {
                    Tile(title: "Gastado", value: Money.format(b.spent), note: "de \(Money.format(b.plannedExpenses)) previstos")
                    Tile(title: "Puedes gastar hoy", value: Money.format(s.leftToday), tint: s.leftToday > 0 ? Brand.accent : Brand.bad)
                    Tile(title: "Sobrará el \(s.days)", value: Money.format(s.endLeft), tint: s.endLeft < 0 ? Brand.bad : nil)
                }
            } else {
                EmptyNote("Aún no hay presupuesto de este mes.", icon: "calendar.badge.plus")
                HStack {
                    Button("Crear el presupuesto") { store.createBudget(month); store.screen = .gastos }.buttonStyle(.borderedProminent)
                    if let near = store.nearestBudgetMonth(to: month) {
                        Button("Ver \(Budget.title(near).lowercased())") { store.pendingGastosMonth = near; store.screen = .gastos }.buttonStyle(.accentLink)
                    }
                }
            }
            if !y.months.isEmpty {
                Divider()
                HStack {
                    Text("En \(String(year)): ingresos \(Money.format(y.income)) · gastos \(Money.format(y.spent)) · queda \(Money.format(y.left))" + (y.future.isEmpty ? "" : " (con lo previsto)"))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Resumen del año") { store.pendingGastosYear = year; store.screen = .gastos }.buttonStyle(.accentLink)
                }
            }
        }
    }

    var body: some View {
        let _ = BodyCounter.hit("FinanzasView")
        // Los cancelados no cuentan ni en el total ni en lo que falta por pagar.
        let vivos = eventos.filter { $0.meta["estado"] != "cancelado" }
        let total = vivos.reduce(0.0) { $0 + Money.parse($1.meta["aportacion_eur"] ?? "") }
        let pending = vivos.filter { $0.meta["estado"] != "pagado" }.reduce(0.0) { $0 + Money.parse($1.meta["aportacion_eur"] ?? "") }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MissingNoteBanner(module: .finanzas)
                TileRow {
                    Tile(title: "Eventos", value: "\(eventos.count)")
                    Tile(title: "Aportaciones", value: Money.format(total))
                    // Un evento pendiente sin importe no está «resuelto»: 0 € en verde lo daría a entender.
                    let unknown = vivos.filter { $0.meta["estado"] != "pagado" && Money.parse($0.meta["aportacion_eur"] ?? "") == 0 }.count
                    Tile(title: "Por pagar", value: Money.format(pending), note: unknown == 0 ? nil : plural(unknown, "evento sin importe", "eventos sin importe"),
                         tint: pending > 0 || unknown > 0 ? Brand.warn : Brand.accent)
                }
                gastosCard
                // Hojas de cálculo que haya en la carpeta de Finanzas (de antes de llevar el presupuesto en Gastos).
                let folder = VaultPath.folder("finanzas")
                let sheets = store.attachments.values.filter { rel in
                    (folder.isEmpty || rel.hasPrefix(folder + "/")) && ["numbers", "xlsx", "xls", "ods"].contains((rel as NSString).pathExtension.lowercased())
                }.sorted()
                if !sheets.isEmpty {
                    Card(title: "Hojas de cálculo", icon: "tablecells.badge.ellipsis", info: "La app no lee hojas de cálculo: se abren con su programa. El presupuesto de cada mes se lleva en Gastos.") {
                        ForEach(sheets, id: \.self) { rel in
                            Button { NSWorkspace.shared.open(store.url(rel)) } label: { Label("Abrir \((rel as NSString).lastPathComponent)", systemImage: "arrow.up.forward.app") }
                        }
                    }
                }
                ForEach(eventos, id: \.path) { e in
                    Card(title: ((e.path as NSString).lastPathComponent as NSString).deletingPathExtension, icon: "party.popper", actionTitle: "Abrir nota", action: { store.pendingNote = e.path }) {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 3) { Text("Estado").font(.caption).foregroundStyle(.secondary); PropertyPicker(file: e.path, key: "estado", options: ["pendiente", "pagado", "cancelado"]) }
                            VStack(alignment: .leading, spacing: 3) { Text("Fecha").font(.caption).foregroundStyle(.secondary); PropertyDateField(file: e.path, key: "fecha_evento") }
                            VStack(alignment: .leading, spacing: 3) { Text("Aportación (€)").font(.caption).foregroundStyle(.secondary); PropertyField(file: e.path, key: "aportacion_eur", width: 100) }
                            // Pagar una aportación es un gasto: con un clic queda apuntado en Gastos y el evento, pagado.
                            let amount = Money.parse(e.meta["aportacion_eur"] ?? "")
                            if amount > 0, e.meta["estado"] != "pagado", e.meta["estado"] != "cancelado" {
                                Button("Ya pagada: apuntar en Gastos") { store.payContribution(path: e.path, amount: amount) }
                                    .buttonStyle(.borderedProminent).controlSize(.small).padding(.top, 14)
                            }
                        }
                        ForEach(store.tasks(in: e.path).filter { !$0.done }) { TaskRow(task: $0) }
                    }
                }
                Button { showNew = true } label: { Label("Nuevo evento o pago", systemImage: "plus") }.buttonStyle(.borderedProminent)
                Card(title: "Objetivos de ahorro y pagos", icon: "list.bullet") {
                    ForEach(store.tasks(in: file).filter { !$0.done }) { TaskRow(task: $0) }
                    if store.tasks(in: file).filter({ !$0.done }).isEmpty { EmptyNote("Sin tareas.") }
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Finanzas")
        .sheet(isPresented: $showNew) {
            NewNoteSheet(folders: ["Finanzas"], template0: "Evento", folder0: "Finanzas") { store.pendingNote = $0; store.screen = .notas }
        }
    }
}
