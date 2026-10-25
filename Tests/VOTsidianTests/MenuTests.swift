import Foundation
import Testing
@testable import VOTsidian

// MARK: - Menú semanal → lista de la compra

private let menu = """
---
tipo: menu
---

# 🍽️ Menú y compra

## 📆 Menú semanal
| Día | Comida | Cena |
| :-- | :----- | :--- |
| Lunes | Pollo + patata + pepino, tomate y maíz + YoPRO natural con arándanos | Salmón fresco + cottage + verduras |
| Martes | Pavo + batata + ensalada | 2 huevos + 150–200 g de claras + tomate |
| Miércoles | Pollo o pavo + patatas + melocotón | Comer fuera |
| Jueves | 200 g de pollo + batata + sandía | — |

## 🛒 Lista de la compra
- **Proteína:** pechuga de pollo y pavo, salmón fresco y ahumado, huevos, claras, queso cottage, YoPRO.
- **Verdura y fruta:** tomate, pepino, ensalada, melocotones, sandía, arándanos.
"""

@Test func menuDishesSplitIntoIngredients() {
    #expect(WeeklyMenu.ingredients(of: "Pollo + patata + pepino, tomate y maíz + YoPRO natural con arándanos")
            == ["Pollo", "Patata", "Pepino", "Tomate", "Maíz", "YoPRO natural", "Arándanos"])
    #expect(WeeklyMenu.ingredients(of: "2 huevos + 150–200 g de claras + 50 g de salmón ahumado") == ["Huevos", "Claras", "Salmón ahumado"])
    #expect(WeeklyMenu.ingredients(of: "Pollo o pavo") == ["Pollo", "Pavo"])
    #expect(WeeklyMenu.ingredients(of: "Salmón (al horno) + verdura, sin aceite") == ["Salmón", "Verdura"])
    #expect(WeeklyMenu.ingredients(of: "[[Lentejas|lentejas]] con chorizo") == ["Lentejas", "Chorizo"])
    let dishes = WeeklyMenu.dishes(menu)
    #expect(dishes.count == 6)   // «Comer fuera» y «—» no son platos
    #expect(dishes.first == MenuDish(day: "Lunes", meal: "Comida", dish: "Pollo + patata + pepino, tomate y maíz + YoPRO natural con arándanos"))
}

@Test func menuNamesCompareInSingularAndPlural() {
    #expect(WeeklyMenu.covers("Pechuga de pollo y pavo", "Pavo"))
    #expect(WeeklyMenu.covers("Melocotones", "melocotón") && WeeklyMenu.covers("Nueces", "nuez") && WeeklyMenu.covers("Patatas", "patata"))
    #expect(!WeeklyMenu.covers("YoPRO", "YoPRO de fresa") && !WeeklyMenu.covers("Sal", "Salmón"))
    #expect(WeeklyMenu.key("Patatas") == WeeklyMenu.key("patata") && WeeklyMenu.key("Tomates") == WeeklyMenu.key("tomate"))
    #expect(WeeklyMenu.aisle("Salmón") == "Carne y pescado" && WeeklyMenu.aisle("Atún al natural") == "Despensa"
            && WeeklyMenu.aisle("YoPRO de fresa") == "Lácteos y huevos" && WeeklyMenu.aisle("Velas") == nil)
}

@Test func menuNeedsCountMealsAndKnowWhatIsListed() {
    let list = Shopping.parse("## Proteína\n- [ ] Huevos\n- [x] Pechuga de pollo\n\n## Verdura y fruta\n- [ ] Tomate\n")
    let needs = WeeklyMenu.needs(menu, list: list)
    let byName = Dictionary(uniqueKeysWithValues: needs.map { ($0.name, $0) })
    #expect(needs.first?.name == "Pollo" && byName["Pollo"]?.count == 3 && byName["Pollo"]?.covered == true)   // comprado también cuenta
    #expect(byName["Patata"]?.count == 2 && byName["Patata"]?.covered == false)                          // «patatas» es la misma
    #expect(byName["Tomate"]?.covered == true && byName["Huevos"]?.covered == true)
    // sección: la del grupo de la nota que comparte palabra; si no, la de la lista; si no, «Otros» (la lista no usa pasillos)
    #expect(byName["Pavo"]?.category == "Proteína" && byName["Verduras"]?.category == "Verdura y fruta" && byName["Batata"]?.category == "Otros")
    // con una lista por pasillos, el pasillo
    let aisles = WeeklyMenu.needs(menu.replacingOccurrences(of: "## 🛒 Lista de la compra", with: "## Otra"), list: Shopping.parse(Shopping.template))
    #expect(aisles.first { $0.name == "Batata" }?.category == "Fruta y verdura")
    #expect(WeeklyMenu.needs("# Sin menú\n", list: []).isEmpty)
}

@MainActor @Test func completeShoppingFromMenuAddsWhatIsMissingOnce() throws {
    let store = Store(root: try syntheticVault())
    try menu.write(to: store.url(WeeklyMenu.file), atomically: true, encoding: .utf8)
    store.reload()
    let n = store.generateShoppingFromMenu()
    let names = Set(store.shoppingItems.map { MD.fold($0.text) })
    #expect(n == store.shoppingItems.count && n > 0)
    #expect(names.contains("pechuga de pollo y pavo") && names.contains("patata") && names.contains("yopro natural"))
    #expect(!names.contains("pollo") && !names.contains("pavo") && !names.contains("tomate frito"))   // los básicos ya lo cubren
    let allCovered = store.menuNeeds.allSatisfy(\.covered)
    #expect(allCovered)
    #expect(store.generateShoppingFromMenu() == 0)   // ya no falta nada
    store.undo()
    store.undo()
    #expect(!store.shoppingExists || store.shoppingItems.isEmpty)   // se deshace de una vez
}

@MainActor @Test func createMenuWritesTheWeekTable() throws {
    let store = Store(root: try syntheticVault())
    store.createMenu()
    let dishes = WeeklyMenu.dishes(store.read(WeeklyMenu.file))
    #expect(store.exists(WeeklyMenu.file) && dishes.isEmpty)   // tabla vacía: aún no hay platos
    #expect(Parse.tables(store.read(WeeklyMenu.file)).first?.rows.count == 7)
}
