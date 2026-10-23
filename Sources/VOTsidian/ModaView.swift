import SwiftUI

private let modaEstados = ["", "Pendiente", "Investigando", "Presupuestado", "Comprado", "Descartado"]
private let modaPrioridades = ["", "Alta", "Media", "Baja"]

struct ModaView: View {
    @Environment(Store.self) private var store
    @State private var spec: RowSpec?
    @AppStorage("modaBoard") private var board = false
    @State private var prenda = ""
    @State private var modelo = ""
    @State private var prio = "Media"
    @State private var precio = ""
    @State private var fecha = ""

    private let file = VaultPath.moda

    private func buyTable(_ tables: [NamedTable]) -> NamedTable? { tables.first { MD.fold($0.title).contains("por comprar") } }

    var body: some View {
        let tables = Parse.tables(store.read(file))
        let buy = buyTable(tables)
        let rows = (buy?.rows ?? []).filter { !($0.cells.first ?? "").isEmpty }
        let open = rows.filter { r in
            let e = MD.fold(buy?.value(r, "estado") ?? "")
            return !e.contains("comprado") && !e.contains("descartado")
        }
        let budget = open.reduce(0.0) { $0 + Money.parse(buy?.value($1, "precio") ?? "") }
        let wardrobe = tables.first { MD.fold($0.title) == "armario" }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Tile(title: "Por comprar", value: "\(open.count)", note: "de \(rows.count) en la lista")
                    Tile(title: "Presupuesto", value: Money.format(budget), note: "sin comprado ni descartado")
                    Tile(title: "Comprado", value: "\(rows.count - open.count - rows.filter { MD.fold(buy?.value($0, "estado") ?? "").contains("descartado") }.count)", tint: Brand.accent)
                    Tile(title: "Categorías", value: "\(wardrobe?.rows.count ?? 0)", note: "en el armario")
                }

                Picker("", selection: $board) { Text("Lista").tag(false); Text("Tablero").tag(true) }.pickerStyle(.segmented).labelsHidden().fixedSize()
                if let buy, board {
                    StatusBoard(columns: modaEstados.filter { !$0.isEmpty },
                                cards: Dictionary(grouping: rows, by: { let e = buy.value($0, "estado"); return e.isEmpty ? "Pendiente" : e }).mapValues { rs in
                                    rs.map { BoardCard(id: "\($0.line)", title: buy.value($0, "prenda"), subtitle: buy.value($0, "modelo"), badge: Money.parse(buy.value($0, "precio")) > 0 ? Money.format(Money.parse(buy.value($0, "precio"))) : buy.value($0, "prioridad"), color: Brand.lime) }
                                },
                                move: { id, col in if let r = rows.first(where: { "\($0.line)" == id }) { set(buy, r, "estado", col) } })
                }
                if let buy, !board {
                    Card(title: "Por comprar", icon: "bag") {
                        if rows.isEmpty { EmptyNote("Nada en la lista.") }
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                            if !rows.isEmpty {
                                GridRow { Text("Prenda"); Text("Modelo"); Text("Prioridad"); Text("Precio"); Text("Objetivo"); Text("Estado"); Text("") }
                                    .font(.caption).foregroundStyle(.secondary)
                                Divider()
                            }
                            ForEach(rows) { r in
                                GridRow {
                                    Text(buy.value(r, "prenda")).fontWeight(.medium)
                                    Text(buy.value(r, "modelo")).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 230, alignment: .leading)
                                    ChoiceMenu(options: modaPrioridades, current: buy.value(r, "prioridad"), width: 100) { set(buy, r, "prioridad", $0) }
                                    Text(Money.parse(buy.value(r, "precio")) > 0 ? Money.format(Money.parse(buy.value(r, "precio"))) : "–").monospacedDigit()
                                    Text(buy.value(r, "fecha objetivo").isEmpty ? "–" : buy.value(r, "fecha objetivo")).monospacedDigit().foregroundStyle(.secondary)
                                    ChoiceMenu(options: modaEstados, current: buy.value(r, "estado"), width: 130) { set(buy, r, "estado", $0) }
                                    EditButton { spec = RowSpec(file: file, mode: .edit(line: r.line), title: "prenda") }
                                }
                            }
                        }
                    }
                    Card(title: "Añadir a la lista", icon: "plus.circle", info: "Con fecha objetivo se crea un evento en Calendar al activar los avisos.") {
                        HStack {
                            TextField("Prenda", text: $prenda)
                            TextField("Modelo sugerido", text: $modelo)
                        }
                        HStack {
                            HStack { Text("Prioridad").foregroundStyle(.secondary); ChoiceMenu(options: Array(modaPrioridades.dropFirst()), current: prio, width: 100) { prio = $0 } }
                            TextField("Precio estimado (€)", text: $precio).frame(width: 160)
                            TextField("Fecha objetivo (AAAA-MM-DD)", text: $fecha).frame(width: 200)
                            Spacer()
                            Button("Añadir") { add(buy) }.buttonStyle(.borderedProminent).disabled(prenda.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                NoteTables(file: file, icon: "tshirt", include: { $0.id != buy?.id })

                ListCard(file: file, section: "Estrategia", title: "Estrategia", icon: "lightbulb", placeholder: "Añadir regla de estilo")
                ListCard(file: file, section: "Calzado y accesorios", title: "Calzado y accesorios: notas", icon: "shoeprints.fill", placeholder: "Añadir nota")
                Button("Editar la nota completa") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Moda")
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    private func set(_ t: NamedTable, _ r: TableRow, _ col: String, _ value: String) {
        guard let c = t.col(col) else { return }
        var cells = r.cells
        while cells.count < t.header.count { cells.append("") }
        cells[c] = value
        store.updateRow(file: file, line: r.line, expectFirst: r.cells.first ?? "", cells: cells)
    }

    private func add(_ t: NamedTable) {
        var cells = [String](repeating: "", count: t.header.count)
        func put(_ col: String, _ v: String) { if let i = t.col(col), i < cells.count { cells[i] = v } }
        put("prenda", prenda.trimmingCharacters(in: .whitespaces)); put("modelo", modelo); put("prioridad", prio)
        put("precio", precio); put("fecha objetivo", fecha); put("estado", "Pendiente")
        store.insertRow(file: file, afterLine: t.lastLine, cells: cells)
        prenda = ""; modelo = ""; precio = ""; fecha = ""
    }
}
