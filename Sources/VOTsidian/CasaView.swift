import Charts
import SwiftUI

private let estados = ["", "Idea", "Investigando", "Presupuestado", "Comprado", "Hecho", "Descartado"]
private let prioridades = ["", "Alta", "Media", "Baja"]
private let cerrados: Set<String> = ["comprado", "hecho", "descartado"]

struct CasaItem: Identifiable {
    var id: String
    var name: String
    var room: String
    var cost: Double
    var kind: String
    var estado: String
    var prioridad: String
}

struct CasaView: View {
    @Environment(Store.self) private var store
    @State private var addKind = "Reformas"
    @State private var name = ""
    @State private var room = ""
    @State private var prio = "Media"
    @State private var cost = ""
    @State private var extra = ""
    @State private var spec: RowSpec?
    @AppStorage("casaBoard") private var board = false

    private func items(_ t: SectionTable, costCol: String, kind: String) -> [CasaItem] {
        t.rows.filter { !($0.cells.first ?? "").isEmpty }.map { r in
            CasaItem(id: "\(kind)\(r.line)", name: t.value(r, "Qué"), room: t.value(r, "Estancia"), cost: Money.parse(t.value(r, costCol)),
                     kind: kind, estado: t.value(r, "Estado"), prioridad: t.value(r, "Prioridad"))
        }
    }

    var body: some View {
        let c = store.casa
        let reformas = items(c.reformas, costCol: "Coste estimado", kind: "Reforma")
        let compras = items(c.compras, costCol: "Precio estimado", kind: "Compra")
        let all = (reformas + compras).sorted { $0.cost > $1.cost }
        let totalR = reformas.reduce(0) { $0 + $1.cost }, totalC = compras.reduce(0) { $0 + $1.cost }
        let pending = all.filter { !cerrados.contains(MD.fold($0.estado)) }.reduce(0) { $0 + $1.cost }
        let spent = all.filter { ["comprado", "hecho"].contains(MD.fold($0.estado)) }.reduce(0) { $0 + $1.cost }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Tile(title: "Reformas", value: Money.format(totalR), note: reformas.count == 1 ? "1 idea" : "\(reformas.count) ideas")
                    Tile(title: "Compras", value: Money.format(totalC), note: compras.count == 1 ? "1 idea" : "\(compras.count) ideas")
                    // «Por gastar» ya dice el total cuando no hay nada cerrado: no se repite la misma cifra en dos tarjetas.
                    Tile(title: "Por gastar", value: Money.format(pending), note: pending == totalR + totalC ? "todo pendiente" : "de \(Money.format(totalR + totalC)) estimados", tint: Brand.accent)
                    Tile(title: "Hecho o comprado", value: Money.format(spent), note: spent == 0 ? "nada cerrado todavía" : "ya gastado")
                }

                if !all.isEmpty {
                    Card(title: "Coste estimado por elemento", icon: "chart.bar") {
                        Chart(all) { i in
                            BarMark(x: .value("€", i.cost), y: .value("Qué", i.name))
                                .foregroundStyle(by: .value("Tipo", i.kind))
                                .cornerRadius(4)
                                .annotation(position: .trailing) { Text(Money.format(i.cost)).font(.caption).foregroundStyle(.secondary) }
                        }
                        .chartForegroundStyleScale(["Reforma": Brand.accent, "Compra": Brand.amber])
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(max(100, all.count * 42)))
                    }
                }

                Picker("", selection: $board) { Text("Tablas").tag(false); Text("Tablero").tag(true) }.pickerStyle(.segmented).frame(width: 190).labelsHidden()
                if board {
                    let tables: [(String, SectionTable)] = [("Reformas", c.reformas), ("Compras", c.compras)]
                    let all = tables.flatMap { sec, t in t.rows.filter { !($0.cells.first ?? "").isEmpty }.map { (sec, t, $0) } }
                    StatusBoard(columns: estados, cards: Dictionary(grouping: all, by: { $0.1.value($0.2, "Estado") }).mapValues { rows in
                        rows.map { sec, t, r in BoardCard(id: "\(sec)|\(r.line)", title: t.value(r, "Qué"), subtitle: t.value(r, "Estancia"),
                                                          badge: Money.parse(t.value(r, sec == "Reformas" ? "Coste estimado" : "Precio estimado")) > 0 ? Money.format(Money.parse(t.value(r, sec == "Reformas" ? "Coste estimado" : "Precio estimado"))) : "",
                                                          color: sec == "Reformas" ? Brand.accent : Brand.amber) }
                    }, move: { id, col in
                        let parts = id.split(separator: "|")
                        guard parts.count == 2, let line = Int(parts[1]), let t = tables.first(where: { $0.0 == parts[0] })?.1, let r = t.rows.first(where: { $0.line == line }) else { return }
                        store.setCasaCell(section: String(parts[0]), row: r, column: "Estado", value: col)
                    })
                } else {
                    section("Reformas", icon: "hammer", table: c.reformas, costCol: "Coste estimado", extraCols: ["Cuándo"])
                    section("Compras", icon: "cart", table: c.compras, costCol: "Precio estimado", extraCols: ["Dónde"])
                }

                Card(title: "Añadir", icon: "plus.circle") {
                    HStack {
                        Picker("", selection: $addKind) { Text("Reforma").tag("Reformas"); Text("Compra").tag("Compras") }
                            .pickerStyle(.segmented).frame(width: 190).labelsHidden()
                        TextField("Qué", text: $name)
                        TextField("Estancia", text: $room).frame(width: 150)
                    }
                    HStack {
                        HStack { Text("Prioridad").foregroundStyle(.secondary); ChoiceMenu(options: Array(prioridades.dropFirst()), current: prio, width: 110) { prio = $0 } }.frame(width: 190, alignment: .leading)
                        TextField("Coste estimado (€)", text: $cost).frame(width: 160)
                        TextField(addKind == "Reformas" ? "Cuándo" : "Dónde", text: $extra)
                        Button("Añadir") { add() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                MantenimientoCard()

                NoteTables(file: VaultPath.casa, icon: "refrigerator", include: { $0.title.localizedCaseInsensitiveContains("electrodom") })

                Button("Abrir la nota Casa") { store.pendingNote = VaultPath.casa }.buttonStyle(.accentLink)
            }
            .padding(24)
        }
        .navigationTitle("Casa")
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    private func add() {
        let t = addKind == "Reformas" ? store.casa.reformas : store.casa.compras
        let money = cost.trimmingCharacters(in: .whitespaces)
        var cells = [String](repeating: "", count: t.header.count)
        func put(_ col: String, _ v: String) { if let i = t.col(col), i < cells.count { cells[i] = v } }
        put("Qué", name.trimmingCharacters(in: .whitespaces)); put("Estancia", room); put("Prioridad", prio)
        put(addKind == "Reformas" ? "Coste estimado" : "Precio estimado", money)
        put(addKind == "Reformas" ? "Cuándo" : "Dónde", extra)
        put("Estado", "Idea")
        store.addCasaRow(section: addKind, cells: cells)
        name = ""; room = ""; cost = ""; extra = ""
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, table t: SectionTable, costCol: String, extraCols: [String]) -> some View {
        Card(title: title, icon: icon) {
            let rows = t.rows.filter { !($0.cells.first ?? "").isEmpty }
            if rows.isEmpty { Text("Sin elementos.").foregroundStyle(.secondary) }
            else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Qué"); Text("Estancia"); Text("Prioridad"); Text(costCol == "Coste estimado" ? "Coste" : "Precio"); ForEach(extraCols, id: \.self) { Text($0) }; Text("Estado"); Text("")
                    }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                    ForEach(rows) { r in
                        GridRow {
                            Text(t.value(r, "Qué")).fontWeight(.medium)
                            Text(t.value(r, "Estancia")).foregroundStyle(.secondary)
                            picker(prioridades, t.value(r, "Prioridad")) { store.setCasaCell(section: title, row: r, column: "Prioridad", value: $0) }
                            Text(Money.format(Money.parse(t.value(r, costCol)))).monospacedDigit()
                            ForEach(extraCols, id: \.self) { Text(t.value(r, $0)).foregroundStyle(.secondary) }
                            picker(estados, t.value(r, "Estado")) { store.setCasaCell(section: title, row: r, column: "Estado", value: $0) }
                            EditButton { spec = RowSpec(file: VaultPath.casa, mode: .edit(line: r.line), title: title == "Reformas" ? "reforma" : "compra") }
                        }
                    }
                }
            }
        }
    }

    private func picker(_ options: [String], _ current: String, set: @escaping (String) -> Void) -> some View {
        ChoiceMenu(options: options, current: current, width: 130, set: set)
    }
}
