import Foundation
import Testing
@testable import VOTsidian

// MARK: - Suscripciones, Préstamos y deudas, Lecturas y Viajes

private func D(_ s: String) -> Date { DayKey.date(s)! }
private func tpl(_ key: String) throws -> String { try #require(Starter.text(forKey: key)) }

// MARK: Suscripciones

@Test func subscriptionPeriodsAreUnderstood() {
    typealias P = SuscripcionesData.Period
    #expect(P.parse("") == .months(1) && P.parse("Mensual") == .months(1) && P.parse("trimestral") == .months(3))
    #expect(P.parse("Anual") == .months(12) && P.parse("cada 2 años") == .months(24) && P.parse("semestral") == .months(6))
    #expect(P.parse("semanal") == .weeks(1) && P.parse("cada 2 semanas") == .weeks(2) && P.parse("quincenal") == .weeks(2) && P.parse("3") == .months(3))
    #expect(P.months(12).label == "cada año" && P.weeks(2).label == "cada 2 semanas" && P.months(24).label == "cada 2 años")
}

@Test func subscriptionNextChargeCountsFromTheAnchor() throws {
    func item(_ anchor: String, _ period: SuscripcionesData.Period, _ status: SuscripcionesData.Status = .active, amount: Double = 12) -> SuscripcionesData.Item {
        .init(name: "X", amount: amount, period: period, anchor: D(anchor), category: "", status: status, notes: "", line: 1)
    }
    // mensual: de una ancla antigua al próximo cobro; hoy cuenta
    #expect(item("2026-01-15", .months(1)).next(from: D("2026-10-23")) == D("2026-11-15"))
    #expect(item("2026-01-15", .months(1)).next(from: D("2026-10-15")) == D("2026-10-15"))
    // fin de mes: febrero se queda en el 28 y marzo vuelve al 31
    #expect(item("2026-01-31", .months(1)).next(from: D("2026-02-10")) == D("2026-02-28"))
    #expect(item("2026-01-31", .months(1)).next(from: D("2026-03-01")) == D("2026-03-31"))
    // anual, semanal y ancla en el futuro
    #expect(item("2025-12-01", .months(12)).next(from: D("2026-10-23")) == D("2026-12-01"))
    #expect(item("2026-10-01", .weeks(2)).next(from: D("2026-10-23")) == D("2026-10-29"))
    #expect(item("2026-12-24", .months(1)).next(from: D("2026-10-23")) == D("2026-12-24"))
    // la prueba va a su fecha; la cancelada no cobra
    #expect(item("2026-11-01", .months(1), .trial).next(from: D("2026-10-23")) == D("2026-11-01"))
    #expect(item("2026-01-15", .months(1), .cancelled).next(from: D("2026-10-23")) == nil)
    #expect(item("2026-01-15", .months(1)).occurrences(from: D("2026-10-01"), to: D("2027-01-31")) == [D("2026-10-15"), D("2026-11-15"), D("2026-12-15"), D("2027-01-15")])
    // coste mensual y anual
    #expect(abs(item("2026-01-15", .months(12), amount: 120).monthlyCost - 10) < 0.001 && abs(item("2026-01-15", .months(3), amount: 30).yearlyCost - 120) < 0.001)
    #expect(abs(item("2026-01-15", .weeks(1), amount: 3).yearlyCost - 156) < 0.001)
}

@Test func subscriptionNoteIsParsed() {
    let s = Parse.suscripciones(suscripcionesFixture)
    #expect(s.items.map(\.name) == ["Netflix", "Spotify", "Cloud", "Curso", "Gimnasio"])
    #expect(s.active.count == 3 && s.trials.map(\.name) == ["Curso"] && s.items[4].status == .cancelled)
    #expect(s.items[0].category == "Suscripciones (música y nube)" && abs(s.items[0].amount - 12.99) < 0.001)
    // 12,99 + 10,99 + 99/12 al mes; la prueba y la cancelada no cuentan
    #expect(abs(s.monthlyTotal - (12.99 + 10.99 + 8.25)) < 0.001 && abs(s.yearlyTotal - s.monthlyTotal * 12) < 0.001)
}

@MainActor @Test func subscriptionAlertsAndCharges() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let alerts = store.suscripcionAlerts(today: today)
    #expect(alerts.contains { $0.text.hasPrefix("Spotify se renueva en 3 días") && $0.level == .info })
    #expect(alerts.contains { $0.text.hasPrefix("La prueba de Curso acaba en 2 días") && $0.level == .urgent })
    #expect(!alerts.contains { $0.text.contains("Gimnasio") })
    #expect(store.alerts(today: today).contains { $0.screen == .suscripciones })
    // un cobro va a la partida de la fila y se deshace
    let month = Budget.monthKey(today)
    let before = store.budget(month)?.moves.count ?? 0
    let netflix = try #require(store.suscripciones.items.first { $0.name == "Netflix" })
    #expect(store.logSuscripcionCharge(netflix) == "Suscripciones (música y nube)")
    let moves = try #require(store.budget(month)?.moves)
    #expect(moves.count == before + 1 && moves.contains { abs($0.amount - 12.99) < 0.001 && $0.category == "Suscripciones (música y nube)" && $0.note == "Netflix" })
    store.undo()
    #expect(store.budget(month)?.moves.count == before)
    // cambiar el estado reescribe solo esa fila
    store.setSuscripcionStatus(netflix, to: "Cancelada")
    #expect(store.suscripciones.items.first { $0.name == "Netflix" }?.status == .cancelled && store.suscripciones.items.count == 5)
    // calendario y avisos de Calendar
    let days = store.agenda(from: today, to: DayKey.adding(days: 30, to: today))
    #expect(days.values.joined().contains { $0.kind == .suscripcion && $0.title == "Se renueva Spotify" })
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(medicacion: false, review: false, monthlyWeight: false, tasks: false, mascota: false, birthdays: false, documents: false,
                                                                    events: false, payments: false, monthlyReview: false, vehiculo: false, prestamos: false, viajes: false), today: today)
    #expect(ev.contains { $0.title.hasPrefix("Renueva: Spotify") && $0.extraTriggers == ["-P1D"] } && ev.contains { $0.title.hasPrefix("Acaba la prueba: Curso") })
    #expect(!ev.contains { $0.title.contains("Netflix") || $0.title.contains("Gimnasio") })
    store.hiddenModules.insert(.suscripciones)
    #expect(!store.alerts(today: today).contains { $0.screen == .suscripciones })
    #expect(ICS.events(store.reminderSources(), plan: ReminderPlan(), today: today).allSatisfy { !$0.uid.hasPrefix("susc") })
}

// MARK: Préstamos y deudas

@Test func loanStatusCountsPaymentsAndInstallments() throws {
    let p = Parse.prestamos(prestamosFixture)
    #expect(p.loans.map(\.name) == ["Coche", "Ana"] && p.payments.count == 2 && p.loans[0].day == 15 && p.loans[1].installment == 0)
    let today = D("2026-10-23")
    let car = try #require(p.statuses(today: today).first)
    #expect(car.paid == 1000 && car.remaining == 5000 && abs(car.progress - 1000.0 / 6000) < 0.001)
    #expect(car.missed && !car.paidThisMonth && car.nextDue == (D("2026-11-15")))   // el 15 de octubre pasó sin apuntar
    #expect(car.installmentsLeft == 10 && car.estimatedEnd == (D("2027-08-15")))
    let debt = try #require(p.statuses(today: today).last)
    #expect(debt.remaining == 200 && debt.nextDue == nil && debt.installmentsLeft == nil && !debt.missed)
    #expect(p.totalRemaining(today: today) == 5200 && p.monthlyInstallments(today: today) == 500)
    // si aún no llega el día de este mes, la próxima es la de este mes
    #expect(p.statuses(today: D("2026-10-10")).first?.nextDue == D("2026-10-15"))
    // y si ya se pagó este mes, la del mes que viene
    let paid = Parse.prestamos(prestamosFixture.replacingOccurrences(of: "| 2026-09-15 |", with: "| 2026-10-12 |"))
    let s = try #require(paid.statuses(today: D("2026-10-13")).first)
    #expect(s.paidThisMonth && !s.missed && s.nextDue == (D("2026-11-15")))
    // cuotas que faltan, una por mes; el día 31 se queda en fin de mes
    #expect(p.dueDates(car, upTo: D("2027-01-31")) == [D("2026-11-15"), D("2026-12-15"), D("2027-01-15")])
    #expect(PrestamosData.dueDate(day: 31, monthOf: D("2026-01-10"), plus: 1) == D("2026-02-28"))
    #expect(PrestamosData.dueDate(day: 31, monthOf: D("2026-12-10"), plus: 2) == D("2027-02-28"))
}

@Test func loanPaidOffAndEndDate() throws {
    let text = prestamosFixture.replacingOccurrences(of: "| 6.000 € | 500 € | 15 | |", with: "| 1.000 € | 500 € | 15 | 2026-12-31 |")
    let car = try #require(Parse.prestamos(text).statuses(today: D("2026-10-23")).first)
    #expect(car.isPaidOff && car.remaining == 0 && car.nextDue == nil && car.installmentsLeft == nil)
    let until = Parse.prestamos(prestamosFixture.replacingOccurrences(of: "| 15 | |", with: "| 15 | 2026-12-31 |"))
    let s = try #require(until.statuses(today: D("2026-10-23")).first)
    #expect(until.dueDates(s, upTo: D("2030-01-01")) == [D("2026-11-15"), D("2026-12-15")])   // «Hasta» corta la serie
}

@MainActor @Test func loanPaymentsAlertsAndGastos() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let month = Budget.monthKey(today)
    let before = store.budget(month)?.moves.count ?? 0
    let car = try #require(store.prestamos.loans.first { $0.name == "Coche" })
    store.addPrestamoPago(car, amount: 500, date: today, expense: true)
    #expect(store.prestamos.payments.count == 3 && store.prestamos.paid(car) == 1500)
    let moves = try #require(store.budget(month)?.moves)
    #expect(moves.count == before + 1 && moves.contains { $0.amount == 500 && $0.category == "Préstamo personal" && $0.note == "Coche" })
    // se deshacen juntos
    store.undo()
    #expect(store.prestamos.payments.count == 2 && store.budget(month)?.moves.count == before)
    // sin Gastos solo va a la nota
    store.addPrestamoPago(car, amount: 100, date: today, expense: false)
    #expect(store.prestamos.payments.count == 3 && store.budget(month)?.moves.count == before)
    // el aviso salta si la cuota (día 15) es en 3 días o menos y no se apuntó este mes; la de octubre aún no está apuntada
    let fresh = Store(root: try syntheticVault())
    #expect(fresh.prestamoAlerts(today: D("2026-10-13")).contains { $0.text.hasPrefix("Cuota de Coche en 2 días") })
    #expect(fresh.prestamoAlerts(today: D("2026-10-05")).isEmpty)                                          // faltan 10 días
    #expect(fresh.prestamoAlerts(today: D("2026-10-23")).contains { $0.text == "Cuota de Coche sin apuntar este mes" })
    // calendario
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(medicacion: false, review: false, monthlyWeight: false, tasks: false, mascota: false, birthdays: false, documents: false,
                                                                    events: false, payments: false, monthlyReview: false, vehiculo: false, suscripciones: false, viajes: false), today: today)
    #expect(ev.filter { $0.title.hasPrefix("Cuota: Coche") }.count > 1 && ev.allSatisfy { !$0.title.contains("Ana") })
    store.hiddenModules.insert(.prestamos)
    #expect(!store.alerts(today: today).contains { $0.screen == .prestamos })
}

// MARK: Lecturas

@Test func booksAreParsedWithStateRatingAndPace() throws {
    let text = """
    ---
    objetivo_anual: 12
    ---

    ## Libros

    | Título | Autor | Estado | Empezado | Terminado | Nota | Páginas |
    | :----- | :---- | :----- | :------- | :-------- | :--- | ------: |
    | Dune | Herbert | Terminado | 2026-01-01 | 2026-01-31 | ⭐⭐⭐⭐ | 600 |
    | Emma | Austen | | 2026-02-01 | 2026-02-11 | 5 | 300 |
    | Ulises | Joyce | Abandonado | 2026-03-01 | | | |
    | Sapiens | Harari | | | | | |
    | Neuromante | Gibson | Leyendo | 2026-09-01 | | | |
    | Viejo | X | Terminado | 2025-05-01 | 2025-05-20 | | 100 |
    """
    let l = Parse.lecturas(text)
    #expect(l.goal == 12 && l.books.count == 6)
    #expect(l.books.map(\.status) == [.finished, .finished, .dropped, .pending, .reading, .finished])   // sin Estado manda la fecha
    #expect(l.books[0].rating == 4 && l.books[1].rating == 5 && l.books[2].rating == nil && l.books[0].pages == 600)
    #expect(l.finished(in: 2026).map(\.title) == ["Emma", "Dune"] && l.pages(in: 2026) == 900 && l.pages(in: 2025) == 100)
    #expect(l.reading.map(\.title) == ["Neuromante"] && l.pending.map(\.title) == ["Sapiens"])
    #expect(l.averageDays == 20)   // 30, 10 y 19 días
    // a fin de año al ritmo de ahora: 2 libros en 200 días son unos 4
    #expect(l.projection(today: D("2026-07-20")) == 4)
    #expect(l.projection(today: D("2026-01-20")) == nil)   // muy pronto para decir nada
    #expect(Parse.lecturas("").goal == 0 && Parse.lecturas("").books.isEmpty)
}

@MainActor @Test func bookEditsKeepTheRestOfTheRow() throws {
    let store = Store(root: try syntheticVault())
    let year = DayKey.calendar().component(.year, from: DayKey.today())
    #expect(store.lecturas.finished(in: year).count == 1 && store.lecturas.reading.count == 1 && store.lecturas.goal == 12)
    store.addLibro(title: "Cien años | de soledad", author: "García Márquez", pages: 450)
    let added = try #require(store.lecturas.books.first { $0.title == "Cien años | de soledad" })
    #expect(added.status == .pending && added.pages == 450 && store.lecturas.books.count == 4)
    store.startBook(added)
    let started = try #require(store.lecturas.books.first { $0.title == added.title })
    #expect(started.status == .reading && started.started == DayKey.today() && started.author == "García Márquez" && started.pages == 450)
    store.finishBook(started, rating: 5)
    let done = try #require(store.lecturas.books.first { $0.title == added.title })
    #expect(done.status == .finished && done.finished == DayKey.today() && done.rating == 5 && done.author == "García Márquez")
    #expect(store.lecturas.finished(in: year).count == 2)
    // terminar uno que no tenía fecha de inicio la pone
    let sapiens = try #require(store.lecturas.books.first { $0.title == "Sapiens" })
    store.finishBook(sapiens)
    #expect(store.lecturas.books.first { $0.title == "Sapiens" }.map { $0.started == DayKey.today() && $0.rating == nil } == true)
    let habits = try #require(store.lecturas.books.first { $0.title == "Hábitos atómicos" })
    store.dropBook(habits)
    #expect(store.lecturas.books.first { $0.title == "Hábitos atómicos" }?.status == .dropped)
    // un cambio sobre una fila que ya no es la misma no toca otra
    #expect(Edit.setRowValues(store.read(VaultPath.lecturas), line: habits.line, expectFirst: "Otro título", values: ["estado": "Leyendo"]) == nil)
    #expect(Edit.setRowValues(store.read(VaultPath.lecturas), line: habits.line, expectFirst: habits.title, values: ["columna inventada": "x"]) == nil)
    // las lecturas terminadas salen en el calendario
    let days = store.agenda(from: DayKey.today(), to: DayKey.today())
    #expect(days.values.joined().contains { $0.kind == .lectura && $0.title.hasPrefix("Terminado:") })
}

// MARK: Viajes

@Test func tripsAreParsedWithExpensesAndPacking() throws {
    let v = Parse.viajes(viajesFixture)
    #expect(v.trips.map(\.name) == ["Lisboa", "Roma"] && v.trips[0].budget == 800 && v.trips[0].days == 6 && v.trips[1].isClosed && !v.trips[0].isClosed)
    #expect(v.expenses.count == 1 && v.spent(v.trips[0]) == 120 && v.spent(v.trips[1]) == 0)
    #expect(v.packing.map(\.text) == ["Cargador", "DNI"] && v.packing.map(\.done) == [false, true])
    #expect(v.upcoming().map(\.name) == ["Lisboa"])
    #expect(v.isOngoing(v.trips[0]) == false)
    let starting = Parse.viajes(viajesFixture.replacingOccurrences(of: "| \(isoDay(20)) | \(isoDay(25)) |", with: "| \(isoDay(-1)) | \(isoDay(2)) |"))
    #expect(starting.isOngoing(starting.trips[0]) && starting.upcoming().first?.name == "Lisboa")
    #expect(Parse.viajes("").trips.isEmpty && Parse.viajes("").packing.isEmpty)
}

@MainActor @Test func tripActionsAndPackingList() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let month = Budget.monthKey(today)
    // el equipaje no son tareas
    #expect(!store.tasks.contains { $0.text.contains("Cargador") })
    store.addPacking("Botiquín")
    #expect(store.viajes.packing.map(\.text) == ["Cargador", "DNI", "Botiquín"] && !store.tasks.contains { $0.text.contains("Botiquín") })
    store.togglePacking(try #require(store.viajes.packing.first))
    #expect(store.viajes.packing.map(\.done) == [true, true, false])
    store.uncheckPacking()
    #expect(store.viajes.packing.allSatisfy { !$0.done })
    store.deletePacking(try #require(store.viajes.packing.last))
    #expect(store.viajes.packing.count == 2)
    // gasto del viaje: solo nota, o nota y Gastos (juntos al deshacer)
    let lisboa = try #require(store.viajes.trips.first)
    let before = store.budget(month)?.moves.count ?? 0
    store.addViajeGasto(lisboa, concept: "Hotel", amount: 300, expense: false)
    #expect(store.viajes.spent(lisboa) == 420 && store.budget(month)?.moves.count == before)
    store.addViajeGasto(lisboa, concept: "Cena", amount: 40, expense: true)
    #expect(store.viajes.spent(lisboa) == 460 && store.budget(month)?.moves.count == before + 1)
    store.undo()
    #expect(store.viajes.spent(lisboa) == 420 && store.budget(month)?.moves.count == before)
    // alertas: viaje en 20 días, presupuesto pasado
    #expect(store.viajeAlerts(today: today).contains { $0.text == "Viaje a Lisboa en 20 días" && $0.level == .info })
    store.addViajeGasto(lisboa, concept: "Compras", amount: 500, expense: false)
    #expect(store.viajeAlerts(today: today).contains { $0.text.hasPrefix("Lisboa: llevas") })
    store.setViajeStatus(lisboa, to: "Hecho")
    #expect(store.viajeAlerts(today: today).isEmpty && store.viajes.upcoming().isEmpty)
}

@MainActor @Test func tripPassportAlertAndCalendar() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    #expect(!store.viajeAlerts(today: today).contains { $0.text.contains("pasaporte") })
    // pasaporte que caduca 3 meses después de salir
    let expiry = isoDay(110)
    store.writeNote(VaultPath.documentos, text: "---\ntipo: documentos\n---\n\n## Identidad\n\n| Documento | Número | Caduca | Notas |\n| :-- | :-- | :-- | :-- |\n| Pasaporte | X1 | \(expiry) | |\n| DNI | Y2 | \(isoDay(40)) | |\n")
    let alerts = store.viajeAlerts(today: today)
    #expect(alerts.filter { $0.text.contains("pasaporte") }.count == 1 && alerts.contains { $0.text.contains("menos de 6 meses después de salir a Lisboa") })
    store.hiddenModules.insert(.documentos)
    #expect(!store.viajeAlerts(today: today).contains { $0.text.contains("pasaporte") })
    // calendario y Calendar
    let days = store.agenda(from: today, to: DayKey.adding(days: 30, to: today))
    #expect(days.values.joined().contains { $0.kind == .viaje && $0.title == "Viaje a Lisboa" } && days.values.joined().contains { $0.title == "Vuelta de Lisboa" })
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(medicacion: false, review: false, monthlyWeight: false, tasks: false, mascota: false, birthdays: false, documents: false,
                                                                    events: false, payments: false, monthlyReview: false, vehiculo: false, suscripciones: false, prestamos: false), today: today)
    #expect(ev.filter { $0.title.hasPrefix("Viaje:") }.map(\.title) == ["Viaje: Lisboa"] && ev.first?.extraTriggers == ["-P7D"])
    store.hiddenModules.insert(.viajes)
    #expect(!store.alerts(today: today).contains { $0.screen == .viajes })
}

// MARK: Plantillas vacías

@Test func newModuleTemplatesTakeTheFirstEntry() throws {
    let d0 = D("2026-10-20")
    let susc = try #require(Edit.addSuscripcion(try tpl("suscripciones"), name: "Netflix", amount: 12.99, every: "Mensual", date: d0, category: "", trial: false))
    #expect(Parse.suscripciones(susc).items.map(\.name) == ["Netflix"])
    let prueba = try #require(Edit.addSuscripcion(susc, name: "Curso | online", amount: 9, every: "Anual", date: d0, category: "", trial: true))
    #expect(Parse.suscripciones(prueba).items.map(\.name) == ["Netflix", "Curso | online"] && Parse.suscripciones(prueba).items[1].status == .trial)
    let loans = try #require(Edit.addPrestamo(try tpl("prestamos"), name: "Hipoteca", initial: 100_000, installment: 600, day: 5, until: nil, category: ""))
    let paid = try #require(Edit.addPrestamoPago(loans, date: d0, loan: "Hipoteca", amount: 600, note: ""))
    let p = Parse.prestamos(paid)
    #expect(p.loans.map(\.name) == ["Hipoteca"] && p.loans[0].initial == 100_000 && p.loans[0].day == 5 && p.payments.count == 1 && p.paid(p.loans[0]) == 600)
    let book = try #require(Edit.addLibro(try tpl("lecturas"), title: "Dune", author: "Herbert", pages: 600))
    #expect(Parse.lecturas(book).books.map(\.title) == ["Dune"] && Parse.lecturas(book).goal == 0)
    let viajes = try #require(Edit.addViaje(try tpl("viajes"), name: "Lisboa", start: d0, end: d0, budget: 800))
    let gasto = try #require(Edit.addViajeGasto(viajes, date: d0, trip: "Lisboa", concept: "Vuelo", amount: 120))
    let v = Parse.viajes(gasto)
    #expect(v.trips.map(\.name) == ["Lisboa"] && v.expenses.count == 1 && v.spent(v.trips[0]) == 120)
    let bag = try #require(Edit.appendToSection(gasto, section: "Equipaje", line: "- [ ] Cargador"))
    #expect(Parse.viajes(bag).packing.map(\.text) == ["Cargador"] && Edit.uncheckSection(bag, section: "Equipaje") != nil)
}
