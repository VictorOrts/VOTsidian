import Foundation
import Testing
@testable import VOTsidian

// MARK: - Vehículo: fechas, mantenimiento por km o meses, repostajes y consumo

@Test func vehiculoParsesTheThreeTables() throws {
    let v = Parse.vehiculo(vehiculoFixture)
    #expect(v.name == "Coche" && v.plate == "1234 ABC" && v.kmProperty == nil)
    #expect(v.dues.map(\.name) == ["ITV", "Seguro"])                     // sin fecha no cuenta
    #expect(v.services.count == 2 && v.services[0].km == 100_000 && v.services[0].everyKm == 15_000 && v.services[0].everyMonths == 12)
    #expect(v.services[0].cost == 180 && v.services[1].everyKm == nil)
    #expect(v.refuels.count == 2 && v.refuels[1].amount == 47.4)
    #expect(v.currentKm == 114_100)
    // 30 L en 500 km (los litros del primer repostaje no cuentan)
    #expect(abs((v.consumption ?? 0) - 6) < 0.001)
    let spent = v.spent(year: 2026)
    #expect(spent.service == 420 && abs(spent.fuel - 109.4) < 0.001)
}

@Test func vehiculoKmIgnoresThousandsSeparators() {
    #expect(Vehiculo.km("123.456") == 123_456 && Vehiculo.km("123 456 km") == 123_456 && Vehiculo.km("") == nil && Vehiculo.km("0") == nil)
    #expect(Vehiculo.kmText(1500) == "1.500 km" && Vehiculo.kmText(123_456) == "123.456 km" && Vehiculo.kmText(900) == "900 km")
}

@Test func vehiculoNextServiceByKmOrMonths() throws {
    let today = try #require(DayKey.date("2026-10-23"))
    let next = Parse.vehiculo(vehiculoFixture).nextServices(today: today)
    #expect(next.count == 1)                                           // las ruedas no tienen intervalo
    let oil = try #require(next.first)
    #expect(oil.km == 115_000 && oil.kmLeft == 900 && oil.date == DayKey.date("2027-01-10"))
    #expect(oil.isSoon && !oil.isDue)                                  // faltan menos de 1.000 km
    // el último registro manda: tras cambiar el aceite ya no avisa
    let done = try #require(Edit.addVehiculoRow(vehiculoFixture, section: "Mantenimiento", cells: ["2026-10-20", "114.200", "Aceite y filtros", "", "", "15.000", "12"]))
    let after = try #require(Parse.vehiculo(done).nextServices(today: today).first)
    #expect(after.km == 129_200 && !after.isSoon && !after.isDue)
    // por km ya se pasó
    let late = Parse.vehiculo(vehiculoFixture.replacingOccurrences(of: "| 2026-09-20 | 114.100 |", with: "| 2026-09-20 | 115.300 |"))
    #expect(late.nextServices(today: today).first?.isDue == true)
}

@Test func vehiculoTemplateTakesTheFirstEntries() throws {
    let t = try #require(Starter.text(forKey: "vehiculo"))
    #expect(Parse.vehiculo(t).name == "Vehículo" && Parse.vehiculo(t).dues.isEmpty)
    let a = try #require(Edit.addVehiculoRow(t, section: "Repostajes", cells: ["2026-10-01", "50000", "35", "55 €"]))
    let b = try #require(Edit.addVehiculoRow(a, section: "Mantenimiento", cells: ["2026-10-02", "50100", "ITV | revisión", "", "", "", "24"]))
    let v = Parse.vehiculo(b)
    #expect(v.refuels.count == 1 && v.refuels[0].liters == 35)
    #expect(v.services.count == 1 && v.services[0].what == "ITV | revisión" && v.services[0].everyMonths == 24)
}

@MainActor @Test func vehiculoAlertsAgendaAndCalendar() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let alerts = store.vehiculoAlerts(today: today)
    #expect(alerts.contains { $0.text == "Coche: ITV vence en 20 días" && $0.level == .soon })
    #expect(store.alerts(today: today).contains { $0.screen == .vehiculo })
    let days = store.agenda(from: today, to: DayKey.adding(days: 30, to: today))
    #expect(days.values.joined().contains { $0.kind == .vehiculo && $0.title == "Coche: vence ITV" })
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(medicacion: false, review: false, monthlyWeight: false, tasks: false, mascota: false,
                                                                    birthdays: false, documents: false, events: false, payments: false, monthlyReview: false), today: today)
    #expect(ev.contains { $0.title == "Coche: vence ITV" && $0.extraTriggers == ["-P30D"] })
    // módulo oculto: ni avisos ni eventos
    store.hiddenModules.insert(.vehiculo)
    #expect(!store.alerts(today: today).contains { $0.screen == .vehiculo })
    #expect(ICS.events(store.reminderSources(), plan: ReminderPlan(), today: today).allSatisfy { !$0.uid.hasPrefix("vehiculo") })
}

@MainActor @Test func vehiculoRefuelAlsoGoesToGastos() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let month = Budget.monthKey(today)
    let before = store.budget(month)?.moves.count ?? 0
    store.addRepostaje(date: today, km: 114_600, liters: 32, amount: 50.5, expense: true)
    #expect(store.vehiculo.refuels.count == 3 && store.vehiculo.currentKm == 114_600)
    let moves = try #require(store.budget(month)?.moves)
    #expect(moves.count == before + 1 && moves.contains { $0.amount == 50.5 && $0.category == "Transporte" && $0.note == "gasolina" })
    // se deshacen juntos
    store.undo()
    #expect(store.vehiculo.refuels.count == 2 && store.budget(month)?.moves.count == before)
    // sin Gastos solo va a la nota
    store.addMantenimiento(date: today, km: nil, what: "Lavado", shop: "", cost: 10, everyKm: nil, everyMonths: nil, expense: false)
    #expect(store.vehiculo.services.count == 3 && store.budget(month)?.moves.count == before)
}
