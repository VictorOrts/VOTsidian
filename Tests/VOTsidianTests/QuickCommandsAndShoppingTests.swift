import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Órdenes rápidas y lista de la compra

@Test func quickCommands() {
    let today = DayKey.date("2026-10-19")!   // lunes
    func p(_ s: String) -> QuickCommand? { QuickCommand.parse(s, today: today) }
    #expect(p("peso 105,5") == .weight(105.5, today))
    #expect(p("Peso 105.5 ayer") == .weight(105.5, DayKey.date("2026-10-18")!))
    #expect(p("peso 20") == nil && p("peso") == nil && p("peso mucho") == nil)             // fuera de rango o sin número
    #expect(p("ánimo 4") == .mood(4, today) && p("animo 6") == nil && p("animo 3,5") == nil)
    #expect(p("dormí 7,5") == .sleep(7.5, today) && p("sueño 7 anteayer") == .sleep(7, DayKey.date("2026-10-17")!) && p("dormi 20") == nil)
    #expect(p("pinchazo") == .injection(today) && p("pinchazo hoy") == .injection(today) && p("pinché ayer") == .injection(DayKey.date("2026-10-18")!))
    #expect(p("pinchazo ayer") == .injection(DayKey.date("2026-10-18")!) && p("pinchazo lo que sea") == nil)
    if case .task(let t, let d, let r, let pr)? = p("tarea llamar al dentista el viernes urgente") { #expect(t == "llamar al dentista" && DayKey.string(d!) == "2026-10-23" && r == nil && pr == 3) } else { Issue.record("no es tarea") }
    if case .task(let t, _, let r, _)? = p("t pagar alquiler cada mes") { #expect(t == "pagar alquiler" && r == "month") } else { Issue.record("no es tarea") }
    #expect(p("idea app para el gato") == .idea("app para el gato") && p("nota hoy fui al médico") == .diary("hoy fui al médico"))
    #expect(p("cita dermatólogo el 29/10") == .appointment("dermatólogo", DayKey.date("2026-10-29")!) && p("cita dentista") == .appointment("dentista", today))
    #expect(p("cintura 98,5") == .measure("Cintura", 98.5, today) && p("grasa 27 ayer") == .measure("Grasa", 27, DayKey.date("2026-10-18")!))
    #expect(p("compra leche, huevos y pan") == .shopping(["leche", "huevos", "pan"]) && p("compra") == nil)
    #expect(p("buenos días") == nil && p("peso corporal 100") == nil)
    #expect(p("peso 105,5")?.summary == "Registrar peso 105,5 kg (hoy)" || p("peso 105,5")?.summary.hasPrefix("Registrar peso 105,5 kg") == true)
}

@Test func shoppingListLogic() throws {
    let list = Shopping.template
    let a = Shopping.addItems(list, items: ["pollo", "Leche", "pollo", "  "], category: "Carne y pescado")
    #expect(a.added == 2 && a.text.contains("## Carne y pescado\n- [ ] Pollo\n- [ ] Leche\n"))
    let b = Shopping.addItems(a.text, items: ["POLLO", "pavo"], category: "Carne y pescado")          // no repite, aunque cambie la capitalización
    #expect(b.added == 1)
    let c = Shopping.addItems(b.text, items: ["velas"], category: "Fiesta")                      // categoría nueva antes del pie
    #expect(c.added == 1 && c.text.contains("## Fiesta\n- [ ] Velas") && c.text.hasSuffix("## Fiesta\n- [ ] Velas\n\n---\n"))
    // sin pie, la sección nueva va al final y no dentro del encabezado
    let bare = Shopping.addItems("---\ntipo: compra\n---\n\n## Fruta\n", items: ["peras"], category: "Fiesta")
    #expect(bare.text.hasPrefix("---\ntipo: compra\n---\n") && Shopping.parse(bare.text).map(\.category) == ["Fiesta"])
    var items = Shopping.parse(c.text)
    #expect(items.map(\.text) == ["Pollo", "Leche", "Pavo", "Velas"] && items.map(\.category) == ["Carne y pescado", "Carne y pescado", "Carne y pescado", "Fiesta"])
    let checked = try #require(Edit.toggleCheckbox(c.text, line: items[0].line, expect: items[0].raw))
    items = Shopping.parse(checked)
    #expect(items[0].done && !items[1].done)
    #expect(Shopping.parse(Shopping.clearDone(checked)).map(\.text) == ["Leche", "Pavo", "Velas"])
    #expect(Shopping.parse(Shopping.uncheckAll(checked)).allSatisfy { !$0.done })
    let menu = "## 🛒 Lista de la compra\n- **Proteína:** pechuga de pollo y pavo, pescado blanco, huevos.\n- **Grasas:** aceite de oliva virgen extra (con medida), nueces.\n\n## ♻️ Otra\n- **X:** no\n"
    let groups = Shopping.fromMenu(menu)
    #expect(groups.map(\.category) == ["Proteína", "Grasas"] && groups[0].items == ["pechuga de pollo y pavo", "pescado blanco", "huevos"])
}

@MainActor @Test func shoppingAndCommandsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    // En la copia se parte sin lista de la compra ni medidas, tenga lo que tenga el vault.
    for rel in [Shopping.file, Measures.file] where store.exists(rel) { try FileManager.default.removeItem(at: store.url(rel)) }
    store.reload()
    let tasksBefore = store.tasks.count
    #expect(!store.shoppingExists)
    let n = store.generateShoppingFromMenu()
    print("COMPRA generada", n, Set(store.shoppingItems.map(\.category)).sorted())
    #expect(n > 10 && store.shoppingExists && store.tasks.count == tasksBefore)           // la lista no cuenta como tareas
    let first = try #require(store.shoppingItems.first)
    store.toggleShopping(first)
    #expect(store.shoppingItems.first?.done == true && store.tasks.count == tasksBefore)
    #expect(!store.read(Shopping.file).contains("completion") && store.shoppingItems.first?.text == first.text)   // marcar no ensucia el texto
    store.clearBought()
    #expect(store.shoppingItems.count == n - 1)
    #expect(store.generateShoppingFromMenu() == 1)                                         // solo repone lo que falta
    // órdenes
    let kgBefore = store.weight.records.count
    store.run(.weight(104.2, DayKey.today()))
    #expect(store.weight.last?.kg == 104.2 && store.weight.records.count == kgBefore + 1)
    store.run(.mood(5, DayKey.today())); store.run(.sleep(8, DayKey.today()))
    #expect(store.diaryValue(DayKey.today(), "animo") == 5 && store.diaryValue(DayKey.today(), "sueno_h") == 8)
    let dosesBefore = store.medicacion.doses.count, lastDose = store.medicacion.last?.dose
    store.run(.injection(DayKey.today()))
    #expect(store.medicacion.doses.count == dosesBefore + 1 && store.medicacion.last?.dose == lastDose)
    store.run(.task("Probar orden", DayKey.adding(days: 2, to: DayKey.today()), nil, 3))
    #expect(store.tasks.contains { $0.text == "Probar orden" && $0.priority == 3 })
    #expect(store.run(.shopping(["té", "Pan"])).contains("Añadido"))
    #expect(store.shoppingItems.contains { $0.text == "Té" && $0.category == "Otros" })
    #expect(store.run(.measure("Cintura", 98, DayKey.today())) == "Activa primero las medidas en Peso.")
    store.run(.appointment("Dentista", DayKey.adding(days: 3, to: DayKey.today())))
    #expect(store.tasks.contains { $0.file == VaultPath.medico && $0.text == "Dentista" })
}


@MainActor @Test func maintenancePresetsOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    let apps = store.appliances
    print("APARATOS", apps.map { "\($0.name)|\($0.brand)" })
    #expect(apps.count >= 8)
    let presets = Maintenance.presets(appliances: apps)
    print("PRESETS", presets.map(\.title))
    #expect(presets.contains { $0.title.hasPrefix("Ciclo de limpieza de la lavadora AEG") } && presets.contains { $0.title.contains("Descalcificar la cafetera Smeg") })
    #expect(presets.count == Set(presets.map(\.id)).count)                                  // sin repetidos
    let first = DayKey.adding(days: 7, to: DayKey.today())
    store.addMaintenance(Array(presets.prefix(3)), first: first)
    let mt = store.maintenanceTasks
    #expect(mt.count == 3 && mt.allSatisfy { $0.due == first && $0.recurrence != nil })
    #expect(store.read(VaultPath.casa).contains("## Mantenimiento\n- [ ] Revisar la caldera o el calentador 📅"))
    #expect(store.read(VaultPath.casa).hasSuffix("---\nRelacionado: [[Armario]] · [[Finanzas]]\n"))   // la sección va antes del pie
    store.addMaintenance(Array(presets.prefix(3)), first: first)                          // no se duplican
    #expect(store.maintenanceTasks.count == 3)
    // completar una repite la tarea
    let t = try #require(store.maintenanceTasks.first { $0.recurrence == "year" })
    store.setTask(t, done: true)
    #expect(store.maintenanceTasks.contains { $0.text == t.text && $0.due == DayKey.adding(days: 0, to: Recurrence.next(after: first, rule: "year")!) })
    // añadir de nuevo a una sección existente
    store.addMaintenance([presets[3]], first: first)
    #expect(store.maintenanceTasks.count == 4 && store.read(VaultPath.casa).components(separatedBy: "## Mantenimiento").count == 2)
}
