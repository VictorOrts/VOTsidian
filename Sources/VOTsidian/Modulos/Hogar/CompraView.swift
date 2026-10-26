import SwiftUI

struct CompraView: View {
    @Environment(Store.self) private var store
    @State private var text = ""
    @State private var category = "Otros"
    @State private var message = ""

    var body: some View {
        let _ = BodyCounter.hit("CompraView")
        let items = store.shoppingItems
        let pending = items.filter { !$0.done }.count
        var order: [String] = []
        for i in items where !order.contains(i.category) { order.append(i.category) }
        let categories = Array(Set(Shopping.defaultCategories + order)).sorted { (Shopping.defaultCategories.firstIndex(of: $0) ?? 99, $0) < (Shopping.defaultCategories.firstIndex(of: $1) ?? 99, $1) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TileRow {
                    Tile(title: "Por comprar", value: "\(pending)", tint: pending > 0 ? nil : Brand.accent)
                    Tile(title: "Comprado", value: "\(items.count - pending)", tint: Brand.accent)
                    Tile(title: "Artículos", value: "\(items.count)", note: "\(order.count) \(order.count == 1 ? "sección" : "secciones")")
                }
                if !items.isEmpty { ProgressView(value: Double(items.count - pending), total: Double(items.count)).tint(Brand.accent) }

                Card(title: "Añadir", icon: "plus.circle", info: "También desde ⌘K: «compra leche, huevos». Los artículos no cuentan como tareas.") {
                    HStack {
                        TextField("Qué hace falta (varios separados por comas)", text: $text).onSubmit(add)
                        ChoiceMenu(options: categories, current: category, width: 150) { category = $0 }
                        Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Button(action: complete) { Label("Completar con el menú", systemImage: "wand.and.stars") }
                            .help("Añade lo que falte de la «Lista de la compra» de Menú y compra y los ingredientes de los platos de la semana")
                            .disabled(store.read(WeeklyMenu.file).isEmpty)   // sin la nota no hay nada que completar
                        Button("Vaciar comprados") { store.clearBought() }.disabled(items.allSatisfy { !$0.done })
                        Button("Desmarcar todo") { store.uncheckShopping() }.disabled(items.allSatisfy { !$0.done })
                        if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                    }.controlSize(.small)
                }

                MenuCard(complete: complete)

                if items.isEmpty {
                    ContentUnavailableView("Lista vacía", systemImage: "cart",
                                           description: Text("Añade artículos arriba o complétala con el menú de la semana."))
                }
                ForEach(order, id: \.self) { cat in
                    let list = items.filter { $0.category == cat }
                    Card(title: "\(cat) · \(list.filter { !$0.done }.count)", icon: "cart") {
                        ForEach(list) { it in
                            HStack(spacing: 10) {
                                Button { store.toggleShopping(it) } label: { Image(systemName: it.done ? "checkmark.circle.fill" : "circle").accessibilityLabel(it.done ? "Marcar como pendiente" : "Marcar como comprado").foregroundStyle(it.done ? Brand.good : Brand.accent) }
                                    .buttonStyle(.plain)
                                Text(it.text).strikethrough(it.done).foregroundStyle(it.done ? .secondary : .primary)
                                Spacer()
                                Button { store.deleteShopping(it) } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Quitar")
                            }
                        }
                    }
                }
                if store.shoppingExists { Button("Editar la nota completa") { store.pendingNote = Shopping.file }.buttonStyle(.accentLink) }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Compra")
    }

    private func complete() {
        let n = store.generateShoppingFromMenu()
        message = n == 0 ? "No falta nada del menú." : "Añadidos \(n) \(n == 1 ? "artículo" : "artículos") del menú."
    }

    private func add() {
        let items = text.replacingOccurrences(of: " y ", with: ",").split(separator: ",").map { String($0) }
        let n = store.addShopping(items, category: category)
        message = n == 0 ? "Ya estaba en la lista." : "Añadido (\(n))."
        text = ""
    }
}

/// El menú de la semana (tabla de Menú y compra) y lo que pide: cada ingrediente con en cuántas comidas sale y si ya está en la
/// lista. Vista aparte: lee la nota del menú, y escribir en el campo de añadir no la repinta.
private struct MenuCard: View {
    @Environment(Store.self) private var store
    let complete: () -> Void
    @State private var showWeek = false

    var body: some View {
        let _ = BodyCounter.hit("MenuCard")
        let menu = store.read(WeeklyMenu.file)
        let dishes = WeeklyMenu.dishes(menu)
        let needs = WeeklyMenu.needs(menu, list: store.shoppingItems)
        let missing = needs.filter { !$0.covered }
        Card(title: "Menú de la semana", icon: "fork.knife",
             info: "Sale de la tabla «Menú semanal» de la nota Menú y compra (Día | Comida | Cena). Cada plato se parte en ingredientes: «Pollo + patata + pepino, tomate y maíz». Lo que ya está en la lista, aunque esté comprado o con otro nombre («Pechuga de pollo y pavo» cubre «Pavo»), no se repite.") {
            if !store.exists(WeeklyMenu.file) {
                EmptyNote("Aún no tienes la nota Menú y compra.", icon: "fork.knife")
                Button("Crear el menú") { store.createMenu(); store.pendingNote = WeeklyMenu.file }.controlSize(.small)
            } else if dishes.isEmpty {
                EmptyNote("La tabla «Menú semanal» no tiene platos. Escríbelos con sus ingredientes: «Pollo + patata + ensalada».", icon: "fork.knife")
                Button("Editar el menú") { store.pendingNote = WeeklyMenu.file }.controlSize(.small)
            } else {
                Text(missing.isEmpty ? "Todo lo del menú está en la lista." : "Faltan \(missing.count) de \(needs.count) ingredientes.")
                    .font(.callout).foregroundStyle(.secondary)
                FlowLayout(spacing: 5) {
                    ForEach(needs) { n in
                        HStack(spacing: 4) {
                            Image(systemName: n.covered ? "checkmark" : "plus").font(.caption2.weight(.bold))
                            Text(n.name).fontWeight(n.covered ? .regular : .medium)
                            if n.count > 1 { Text("×\(n.count)").foregroundStyle(.secondary).monospacedDigit() }
                        }
                        .font(.caption).lineLimit(1)
                        .foregroundStyle(n.covered ? .secondary : .primary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((n.covered ? Color.primary.opacity(0.05) : Brand.accent.opacity(0.15)), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
                        .help(n.covered ? "Ya en la lista" : "Iría a «\(n.category)»")
                    }
                }
                .accessibilityElement(children: .combine)
                HStack {
                    Button(action: complete) { Label("Completar la lista", systemImage: "cart.badge.plus") }
                        .buttonStyle(.borderedProminent).disabled(missing.isEmpty && Shopping.fromMenu(menu).isEmpty)
                    Button(showWeek ? "Ocultar la semana" : "Ver la semana") { withAnimation(.snappy) { showWeek.toggle() } }
                    Spacer()
                    Button("Editar el menú") { store.pendingNote = WeeklyMenu.file }.buttonStyle(.accentLink)
                }.controlSize(.small)
                if showWeek { week(dishes) }
            }
        }
    }

    /// La semana en una rejilla: un día por fila y una columna por comida.
    private func week(_ dishes: [MenuDish]) -> some View {
        var days: [String] = [], meals: [String] = []
        for d in dishes {
            if !days.contains(d.day) { days.append(d.day) }
            if !meals.contains(d.meal) { meals.append(d.meal) }
        }
        return Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(meals, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(days, id: \.self) { day in
                GridRow {
                    Text(day).font(.callout.weight(.medium))
                    ForEach(meals, id: \.self) { meal in
                        Text(dishes.first { $0.day == day && $0.meal == meal }?.dish ?? "–").font(.callout).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}
