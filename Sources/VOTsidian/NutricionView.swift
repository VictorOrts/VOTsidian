import Charts
import SwiftUI

struct NutricionView: View {
    @Environment(Store.self) private var store
    @State private var spec: RowSpec?

    private var meals: [(name: String, kcal: Double, protein: Double)] {
        store.plan.meals.dropFirst().compactMap { r in
            guard r.count >= 3, !r[0].localizedCaseInsensitiveContains("total"), let k = MD.number(r[1]) else { return nil }
            return (r[0], k, MD.number(r[2]) ?? 0)
        }
    }

    var body: some View {
        let p = store.plan
        let w = store.weight
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if p.kcal > 0 {
                    HStack(spacing: 12) {
                        Tile(title: "Calorías", value: fmt(p.kcal, 0), note: "kcal al día")
                        Tile(title: "Proteína", value: fmt(p.protein, 0, unit: " g"), note: "\(Int(p.protein * 4 / p.kcal * 100)) % · \(fmt(p.protein * 4, 0)) kcal", tint: Brand.info)
                        Tile(title: "Carbohidratos", value: fmt(p.carbs, 0, unit: " g"), note: "\(Int(p.carbs * 4 / p.kcal * 100)) % · \(fmt(p.carbs * 4, 0)) kcal", tint: Brand.amber)
                        Tile(title: "Grasas", value: fmt(p.fat, 0, unit: " g"), note: "\(Int(p.fat * 9 / p.kcal * 100)) % · \(fmt(p.fat * 9, 0)) kcal", tint: Brand.violet)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        Card(title: "Reparto de calorías", icon: "chart.pie") {
                            Chart {
                                SectorMark(angle: .value("kcal", p.protein * 4), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(by: .value("Macro", "Proteína"))
                                SectorMark(angle: .value("kcal", p.carbs * 4), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(by: .value("Macro", "Hidratos"))
                                SectorMark(angle: .value("kcal", p.fat * 9), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(by: .value("Macro", "Grasas"))
                            }
                            .chartForegroundStyleScale(["Proteína": Brand.info, "Hidratos": Brand.amber, "Grasas": Brand.violet])
                            .chartBackground { _ in Text("\(fmt(p.kcal, 0))\nkcal").font(.title3.bold()).multilineTextAlignment(.center) }
                            .frame(height: 200)
                        }
                        Card(title: "Reparto del día", icon: "fork.knife") {
                            Chart(meals, id: \.name) { m in
                                BarMark(x: .value("Comida", m.name), y: .value("kcal", m.kcal)).foregroundStyle(Brand.accent.gradient).cornerRadius(5)
                                    .annotation(position: .top) { Text("\(fmt(m.kcal, 0))").font(.caption).foregroundStyle(.secondary) }
                            }
                            .chartYAxis(.hidden)
                            .frame(height: 200)
                            Text(meals.map { "\($0.name) \(fmt($0.protein, 0)) g" }.joined(separator: " · ") + " de proteína")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let l = w.last {
                        let mid = (l.kg + w.goalKg) / 2
                        Label("Con \(fmt(l.kg, unit: " kg")) son \(fmt(p.protein / l.kg)) g/kg de proteína; sobre el punto medio a tu objetivo (\(fmt(mid, 0)) kg) son \(fmt(p.protein / mid)) g/kg. El rango recomendado para conservar músculo es 1,6–2,2 g/kg.",
                              systemImage: "info.circle").font(.callout)
                    }
                }
                Card(title: "Objetivos diarios", icon: "slider.horizontal.3", info: "Pulsa intro para guardar. Consúltalo con tu médico o dietista.") {
                    HStack(spacing: 18) {
                        goal("Calorías", "kcal_objetivo")
                        goal("Proteína (g)", "proteina_g")
                        goal("Carbohidratos (g)", "carbohidratos_g")
                        goal("Grasas (g)", "grasas_g")
                    }
                }
                if !p.meals.isEmpty {
                    Card(title: "Detalle", icon: "list.bullet") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                            ForEach(Array(p.meals.enumerated()), id: \.offset) { i, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, c in Text(c).fontWeight(i == 0 || row[0].localizedCaseInsensitiveContains("total") ? .semibold : .regular) }
                                    if i > 0, i < p.mealLines.count { EditButton { spec = RowSpec(file: VaultPath.plan, mode: .edit(line: p.mealLines[i]), title: "comida") } }
                                    else { Color.clear.frame(width: 18, height: 1) }
                                }
                            }
                        }
                        if let last = p.mealLines.last {
                            Button { spec = RowSpec(file: VaultPath.plan, mode: store.addMode(file: VaultPath.plan, afterRowLine: last), title: "comidas") } label: { Label("Añadir fila", systemImage: "plus") }
                                .buttonStyle(.borderless).font(.callout)
                        }
                    }
                }
                HStack {
                    Button("Abrir la nota Plan Nutricional") { store.pendingNote = VaultPath.plan }
                    Button("Abrir Menú y compra") { store.pendingNote = "Cambio físico/Menú y compra.md" }
                }.buttonStyle(.accentLink)
                Text("Valores orientativos de tu nota. Confírmalos con tu médico o dietista, sobre todo mientras usas Mounjaro.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Plan nutricional")
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    private func goal(_ label: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            PropertyField(file: VaultPath.plan, key: key, width: 110)
        }
    }
}
