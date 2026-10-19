import SwiftUI

struct CompraView: View {
    @Environment(Store.self) private var store
    @State private var text = ""
    @State private var category = "Otros"
    @State private var message = ""

    var body: some View {
        let items = store.shoppingItems
        let pending = items.filter { !$0.done }.count
        var order: [String] = []
        for i in items where !order.contains(i.category) { order.append(i.category) }
        let categories = Array(Set(Shopping.defaultCategories + order)).sorted { (Shopping.defaultCategories.firstIndex(of: $0) ?? 99, $0) < (Shopping.defaultCategories.firstIndex(of: $1) ?? 99, $1) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Tile(title: "Por comprar", value: "\(pending)", tint: pending > 0 ? nil : Brand.accent)
                    Tile(title: "Comprado", value: "\(items.count - pending)", tint: Brand.accent)
                    Tile(title: "Artículos", value: "\(items.count)", note: "\(order.count) \(order.count == 1 ? "sección" : "secciones")")
                }
                if !items.isEmpty { ProgressView(value: Double(items.count - pending), total: Double(items.count)).tint(Brand.accent) }

                Card(title: "Añadir", icon: "plus.circle") {
                    HStack {
                        TextField("Qué hace falta (varios separados por comas)", text: $text).onSubmit(add)
                        ChoiceMenu(options: categories, current: category, width: 150) { category = $0 }
                        Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Button { let n = store.generateShoppingFromMenu(); message = n == 0 ? "No hay nada nuevo en Menú y compra." : "Añadidos \(n) artículos de Menú y compra." } label: {
                            Label("Generar desde Menú y compra", systemImage: "wand.and.stars")
                        }
                        Button("Vaciar comprados") { store.clearBought() }.disabled(items.allSatisfy { !$0.done })
                        Button("Desmarcar todo") { store.uncheckShopping() }.disabled(items.allSatisfy { !$0.done })
                        if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
                    }.controlSize(.small)
                    Text("También desde ⌘K: «compra leche, huevos». Los artículos no cuentan como tareas.").font(.caption).foregroundStyle(.secondary)
                }

                if items.isEmpty {
                    ContentUnavailableView("Lista vacía", systemImage: "cart",
                                           description: Text("Añade artículos arriba o genera la lista desde tu nota Menú y compra."))
                }
                ForEach(order, id: \.self) { cat in
                    let list = items.filter { $0.category == cat }
                    Card(title: "\(cat) · \(list.filter { !$0.done }.count)", icon: "cart") {
                        ForEach(list) { it in
                            HStack(spacing: 10) {
                                Button { store.toggleShopping(it) } label: { Image(systemName: it.done ? "checkmark.circle.fill" : "circle").accessibilityLabel(it.done ? "Marcar como pendiente" : "Marcar como comprado").foregroundStyle(it.done ? Color.green : Brand.accent) }
                                    .buttonStyle(.plain)
                                Text(it.text).strikethrough(it.done).foregroundStyle(it.done ? .secondary : .primary)
                                Spacer()
                                Button { store.deleteShopping(it) } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Quitar")
                            }
                        }
                    }
                }
                if store.shoppingExists { Button("Editar la nota completa") { store.pendingNote = Shopping.file }.buttonStyle(.link) }
            }
            .padding(24)
        }
        .navigationTitle("Compra")
    }

    private func add() {
        let items = text.replacingOccurrences(of: " y ", with: ",").split(separator: ",").map { String($0) }
        let n = store.addShopping(items, category: category)
        message = n == 0 ? "Ya estaba en la lista." : "Añadido (\(n))."
        text = ""
    }
}
