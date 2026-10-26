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
    #expect(P.parse("cada 15 días") == .days(15) && P.parse("diaria") == .days(1) && P.parse("cada día") == .days(1))
    #expect(P.days(15).label == "cada 15 días" && P.days(1).label == "cada día")
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
    #expect(item("2026-10-01", .days(15)).next(from: D("2026-10-23")) == D("2026-10-31") && item("2026-10-20", .days(15)).next(from: D("2026-10-20")) == D("2026-10-20"))
    #expect(abs(item("2026-10-01", .days(15), amount: 10).yearlyCost - 243.333) < 0.01)
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

// MARK: Órdenes rápidas

@Test func quickCommandsForBooksAndLoans() {
    #expect(QuickCommand.parse("libro Dune - Frank Herbert") == .book("Dune", "Frank Herbert"))
    #expect(QuickCommand.parse("libro Sapiens") == .book("Sapiens", ""))
    #expect(QuickCommand.parse("libro Ensayo - Con - guiones") == .book("Ensayo", "Con - guiones"))
    #expect(QuickCommand.parse("terminé Dune") == .finishBook("Dune") && QuickCommand.parse("acabé Sapiens") == .finishBook("Sapiens"))
    #expect(QuickCommand.parse("cuota Coche") == .loanPayment("Coche"))
    #expect(QuickCommand.parse("libro") == nil && QuickCommand.parse("cuota") == nil && QuickCommand.parse("libro  ") == nil)
    #expect(QuickCommand.book("Dune", "Herbert").summary == "Añadir a Lecturas: «Dune» de Herbert" && QuickCommand.finishBook("Dune").summary == "Terminar «Dune» hoy")
}

@MainActor @Test func quickCommandsRunAgainstTheModules() throws {
    let store = Store(root: try syntheticVault())
    #expect(store.run(.book("Cien años de soledad", "García Márquez")).hasPrefix("Añadir a Lecturas"))
    #expect(store.lecturas.pending.map(\.title).contains("Cien años de soledad"))
    // termina por nombre exacto o parcial, entre lo que lees y lo pendiente
    #expect(store.run(.finishBook("hábitos")) == "Terminado: Hábitos atómicos.")
    #expect(store.lecturas.books.first { $0.title == "Hábitos atómicos" }?.status == .finished)
    #expect(store.run(.finishBook("no existe")).hasPrefix("No encuentro"))
    // cuota: apunta el pago y el gasto
    let month = Budget.monthKey(DayKey.today())
    let before = store.budget(month)?.moves.count ?? 0
    #expect(store.run(.loanPayment("coch")).hasPrefix("Cuota de Coche apuntada"))
    #expect(store.prestamos.payments.count == 3 && store.budget(month)?.moves.count == before + 1)
    #expect(store.run(.loanPayment("Ana")).hasPrefix("No encuentro"))   // sin cuota no hay qué apuntar
    // con el módulo oculto no hace nada
    store.hiddenModules.formUnion([.lecturas, .prestamos])
    #expect(store.run(.book("X", "")).hasPrefix("Activa primero") && store.run(.loanPayment("Coche")).hasPrefix("Activa primero"))
}

// MARK: Módulos nuevos en una carpeta ya configurada

@Test func newModulesAreHiddenOnlyWhenNothingExistsYet() {
    let everything = Module.allCases.map(\.rawValue)
    // antes de que la app recordara cuáles conocía, se parte de los de siempre
    #expect(Module.arrivals(known: nil, hasNotes: { _ in false }) == [.suscripciones, .prestamos, .vehiculo, .viajes, .lecturas, .tramites])
    #expect(Module.arrivals(known: nil, hasNotes: { $0 == .vehiculo }) == [.suscripciones, .prestamos, .viajes, .lecturas, .tramites])   // si ya hay nota, se queda
    #expect(Module.arrivals(known: everything, hasNotes: { _ in false }).isEmpty)
    #expect(Module.arrivals(known: ["peso", "casa"], hasNotes: { _ in false }).count == Module.allCases.count - 2)
    #expect(Module.original.count + 6 == Module.allCases.count)
}

@MainActor @Test func registeringNewModulesHidesAndAnnouncesThemOnce() throws {
    // Nombres fijos: macOS deja el .plist vacío en Preferencias aunque se borre el dominio, y con un UUID se acumulaba uno nuevo en cada pasada.
    let suite = "VOTsidianTests-modulos"
    for s in [suite, suite + "-2", suite + "-3"] { UserDefaults(suiteName: s)?.removePersistentDomain(forName: s) }
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    func vault(_ files: [String: String]) throws -> Store {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/V")
        for (rel, text) in files {
            let url = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return Store(root: dir)
    }
    // carpeta ya configurada: los cinco módulos nuevos se ocultan y se avisa, una sola vez
    let store = try vault([VaultPath.peso: pesoFixture])
    store.modulesConfigured = true
    store.registerNewModules(defaults: defaults)
    #expect(store.hiddenModules == [.suscripciones, .prestamos, .vehiculo, .viajes, .lecturas, .tramites])
    #expect(store.message?.hasPrefix("Módulos nuevos: Suscripciones, Préstamos y deudas, Vehículo, Viajes, Lecturas, Trámites y seguros.") == true)
    #expect(defaults.stringArray(forKey: "knownModules") == Module.allCases.map(\.rawValue))
    store.message = nil
    store.hiddenModules = []                      // el usuario los activa
    store.registerNewModules(defaults: defaults)
    #expect(store.hiddenModules.isEmpty && store.message == nil)
    // carpeta nueva sin configurar: lo decide el asistente, no se toca nada
    let fresh = try vault(["Notas/A.md": "# A\n"])
    fresh.registerNewModules(defaults: UserDefaults(suiteName: suite + "-2")!)
    #expect(fresh.hiddenModules.isEmpty && fresh.message == nil)
    UserDefaults(suiteName: suite + "-2")?.removePersistentDomain(forName: suite + "-2")
    // carpeta con notas pero sin pasar por el asistente: también se ocultan los que no tienen nota
    let used = try vault([VaultPath.peso: pesoFixture, VaultPath.vehiculo: vehiculoFixture])
    used.registerNewModules(defaults: UserDefaults(suiteName: suite + "-3")!)
    #expect(used.hiddenModules == [.suscripciones, .prestamos, .viajes, .lecturas, .tramites])
    UserDefaults(suiteName: suite + "-3")?.removePersistentDomain(forName: suite + "-3")
}

// MARK: Exportar a CSV

@MainActor @Test func moduleDataIsExportedToCSV() throws {
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    let names = Set(try Store(root: try syntheticVault()).exportData(to: out).map(\.lastPathComponent))
    #expect(names.isSuperset(of: ["vehiculo_fechas.csv", "vehiculo_mantenimiento.csv", "vehiculo_repostajes.csv", "suscripciones.csv", "prestamos.csv",
                                  "prestamos_pagos.csv", "lecturas.csv", "viajes.csv", "viajes_gastos.csv"]))
    func csv(_ name: String) throws -> [String] { try String(contentsOf: out.appendingPathComponent(name), encoding: .utf8).components(separatedBy: "\n").filter { !$0.isEmpty } }
    let susc = try csv("suscripciones.csv")
    #expect(susc[0] == "servicio,importe_eur,cada,proximo_cobro,partida,estado,coste_mensual_eur,coste_anual_eur" && susc.count == 6)
    #expect(susc.contains { $0.hasPrefix("Netflix,12.99,cada mes,") && $0.contains(",Suscripciones (música y nube),activa,") } && susc.contains { $0.hasPrefix("Gimnasio,40,cada mes,,,cancelada,") })
    #expect(try csv("prestamos.csv").contains("Coche,6000,500,15,,Préstamo personal,1000,5000") && csv("prestamos.csv").contains("Ana,200,0,,,,0,200"))
    #expect(try csv("prestamos_pagos.csv") == ["fecha,prestamo,importe_eur", "2026-08-15,Coche,500", "2026-09-15,Coche,500"])
    let books = try csv("lecturas.csv")
    #expect(books.count == 4 && books.contains { $0.hasPrefix("Dune,Frank Herbert,terminado,") && $0.hasSuffix(",4,600") } && books.contains { $0.hasPrefix("Sapiens,Yuval Harari,pendiente,,,,") })
    #expect(try csv("viajes.csv").contains { $0.hasPrefix("Lisboa,") && $0.hasSuffix(",800,120,Reservado") } && csv("viajes_gastos.csv").count == 2)
    #expect(try csv("vehiculo_repostajes.csv") == ["fecha,km,litros,importe_eur", "2026-09-01,113600,40,62", "2026-09-20,114100,30,47.4"])
    #expect(try csv("vehiculo_mantenimiento.csv")[1] == "2026-01-10,100000,Aceite y filtros,Taller Pepe,180,15000,12")
    // sin datos de esos módulos no se crea ningún archivo vacío
    let empty = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    let bare = try Store(root: try syntheticVault()).exportData(to: empty).map(\.lastPathComponent)
    #expect(bare.contains("peso.csv"))
    let plain = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/V")
    try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    try "# A\n".write(to: plain.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
    let none = Set(try Store(root: plain).exportData(to: FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")).map(\.lastPathComponent))
    #expect(none.isDisjoint(with: ["suscripciones.csv", "prestamos.csv", "lecturas.csv", "viajes.csv", "vehiculo_repostajes.csv"]))
}

// MARK: Inicio y avisos dentro de las pantallas

@Test func homeCardsFollowTheirModules() {
    #expect(HomeCard.vehiculo.module == .vehiculo && HomeCard.suscripciones.module == .suscripciones && HomeCard.prestamos.module == .prestamos)
    #expect(HomeCard.viajes.module == .viajes && HomeCard.lecturas.module == .lecturas)
    // una carpeta con la disposición guardada de antes recibe las tarjetas nuevas al final y visibles (si su módulo está oculto, no salen)
    let old = HomeLayout(raw: "atencion:1,hoy:1,peso:0")
    #expect(old.items.count == HomeCard.allCases.count && old.items.suffix(6).map(\.card) == [.vehiculo, .suscripciones, .prestamos, .viajes, .lecturas, .tramites] && old.items.suffix(6).allSatisfy(\.visible))
}

@MainActor @Test func moduleAlertsStayPlainInsideTheirOwnScreen() throws {
    // sin adónde ir, el aviso no es un botón ni lleva flecha; con ello (Inicio, Avisos), sí
    let store = Store(root: try syntheticVault())
    let alerts = store.suscripcionAlerts()
    #expect(!alerts.isEmpty)
    let inside = AlertList(alerts: alerts, emptyText: "Nada")
    let outside = AlertList(alerts: alerts, go: { _ in })
    #expect(inside.go == nil && outside.go != nil && inside.emptyText == "Nada")
}

// MARK: Revisión: calendario, órdenes, duplicados y falsos avisos

@MainActor @Test func hiddenModulesLeaveTheCalendar() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    func titles() -> [String] { store.agenda(from: today, to: DayKey.adding(days: 30, to: today)).values.joined().map(\.title) }
    #expect(titles().contains("Se renueva Spotify") && titles().contains("Viaje a Lisboa") && titles().contains { $0.hasPrefix("Coche:") })
    // ocultar un módulo lo quita al momento (la agenda guardada se descarta), y mostrarlo lo devuelve
    store.hiddenModules.formUnion([.suscripciones, .viajes, .vehiculo])
    #expect(!titles().contains("Se renueva Spotify") && !titles().contains("Viaje a Lisboa") && !titles().contains { $0.hasPrefix("Coche:") })
    store.hiddenModules = []
    #expect(titles().contains("Se renueva Spotify"))
    // lo que no es de ningún módulo se queda: tareas y notas del día
    store.hiddenModules = Set(Module.allCases)
    store.addTask("sigo aquí", due: today, recurrence: nil, priority: 0)
    #expect(titles().contains("sigo aquí"))
}

@MainActor @Test func failedQuickCommandsLeaveAMessage() throws {
    let store = Store(root: try syntheticVault())
    store.message = nil
    #expect(store.run(.finishBook("no existe")).hasPrefix("No encuentro") && store.message?.hasPrefix("No encuentro") == true)
    store.message = nil
    #expect(store.run(.loanPayment("Ana")).hasPrefix("No encuentro") && store.message != nil)
    store.hiddenModules.insert(.lecturas)
    store.message = nil
    #expect(store.run(.book("X", "")).hasPrefix("Activa primero") && store.message?.hasPrefix("Activa primero") == true)
    // lo que sale bien no deja ningún aviso
    store.hiddenModules = []
    store.message = nil
    store.run(.book("Dune 2", "Herbert"))
    #expect(store.message == nil)
}

@MainActor @Test func subscriptionChargeIsNotLoggedTwiceInAMonth() throws {
    let store = Store(root: try syntheticVault())
    let netflix = try #require(store.suscripciones.items.first { $0.name == "Netflix" })
    #expect(!store.suscripcionLogged(netflix))
    store.logSuscripcionCharge(netflix)
    #expect(store.suscripcionLogged(netflix))
    #expect(!store.suscripcionLogged(netflix, on: DayKey.adding(days: 40, to: DayKey.today())))   // otro mes
    let spotify = try #require(store.suscripciones.items.first { $0.name == "Spotify" })
    #expect(!store.suscripcionLogged(spotify))                                                      // otra suscripción
    store.undo()
    #expect(!store.suscripcionLogged(netflix))
    // lo semanal se apunta cuando toca, tantas veces como haga falta
    let weekly = SuscripcionesData.Item(name: "Netflix", amount: 12.99, period: .weeks(1), anchor: DayKey.today(), category: "", status: .active, notes: "", line: 99)
    store.logSuscripcionCharge(netflix)
    #expect(!store.suscripcionLogged(weekly))
}

@Test func missedInstallmentNeedsAHabitOfLoggingThem() throws {
    let today = D("2026-10-23")
    // las cuotas de agosto y septiembre están apuntadas: la de octubre, sin apuntar, es un aviso
    #expect(Parse.prestamos(prestamosFixture).statuses(today: today).first?.missed == true)
    // si el mes pasado no se apuntó nada, quien lleva el préstamo no apunta las cuotas: ni aviso ni susto
    let never = Parse.prestamos(prestamosFixture.replacingOccurrences(of: "| 2026-09-15 |", with: "| 2026-07-15 |"))
    let s = try #require(never.statuses(today: today).first)
    #expect(!s.missed && s.nextDue == D("2026-11-15") && s.remaining == 5000)
    let none = Parse.prestamos(prestamosFixture.replacingOccurrences(of: "| 2026-08-15 | Coche | 500 | |\n| 2026-09-15 | Coche | 500 | |\n", with: ""))
    #expect(none.payments.isEmpty && none.statuses(today: today).first?.missed == false)
    // enero con diciembre apuntado: el mes anterior cruza de año
    let year = Parse.prestamos(prestamosFixture.replacingOccurrences(of: "| 2026-09-15 |", with: "| 2025-12-15 |"))
    #expect(year.statuses(today: D("2026-01-20")).first?.missed == true)
}

@MainActor @Test func importedFilesNeverOverwriteAnything() throws {
    let store = Store(root: try syntheticVault())
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
    let dir = tmp.appendingPathComponent("Análisis")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let a = tmp.appendingPathComponent("sangre.pdf"), other = tmp.appendingPathComponent("otro/sangre.pdf")
    try Data("uno".utf8).write(to: a)
    try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("dos".utf8).write(to: other)
    func data(_ u: URL) throws -> Data { try Data(contentsOf: u) }
    func count() throws -> Int { try FileManager.default.contentsOfDirectory(atPath: dir.path).count }
    // la primera vez se copia (y se crea la carpeta)
    let first = try #require(store.importFile(a, to: dir))
    let firstData = try data(first)
    #expect(first.lastPathComponent == "sangre.pdf" && firstData == Data("uno".utf8))
    // el mismo archivo otra vez: se reutiliza, no se duplica
    #expect(store.importFile(a, to: dir) == first)
    let afterSame = try count()
    #expect(afterSame == 1)
    // otro archivo con el mismo nombre: se numera y el primero queda como estaba
    let second = try #require(store.importFile(other, to: dir))
    let (kept, added) = (try data(first), try data(second))
    #expect(second.lastPathComponent == "sangre 2.pdf" && kept == Data("uno".utf8) && added == Data("dos".utf8))
    #expect(store.importFile(other, to: dir) == second)
    // con nombre propio (fotos con la fecha delante)
    #expect(store.importFile(a, to: dir, as: "2026-10-24-sangre.pdf")?.lastPathComponent == "2026-10-24-sangre.pdf")
    // si no se puede, devuelve nil y lo dice
    store.message = nil
    #expect(store.importFile(tmp.appendingPathComponent("no-existe.pdf"), to: dir) == nil && store.message?.hasPrefix("No se pudo copiar no-existe.pdf") == true)
}

// MARK: Números absurdos no cierran la app

@MainActor @Test func absurdNumbersNeverCrash() throws {
    let huge = "99999999999999999999999999", tiny = "0,0000001"
    for n in [huge, "-\(huge)", "1e400", "nan", "inf", tiny] {
        let susc = Parse.suscripciones("| Servicio | Importe | Cada | Próximo cobro | Estado |\n| - | - | - | - | - |\n| A | \(n) | cada \(n) meses | 2026-01-15 | Activa |\n| B | \(n) | cada \(n) semanas | 2026-01-15 | Activa |\n| C | 1 | cada \(n) años | 2026-01-15 | Activa |\n| D | 1 | cada \(n) días | 2026-01-15 | Activa |")
        for i in susc.items { _ = (i.next(), i.occurrences(from: DayKey.today(), to: DayKey.adding(days: 800, to: DayKey.today())), i.monthlyCost, i.period.label) }
        _ = (susc.monthlyTotal, susc.yearlyTotal, susc.upcoming())
        let loans = Parse.prestamos("| Préstamo | Pendiente | Cuota | Día | Hasta |\n| - | - | - | - | - |\n| A | \(n) | \(n) | \(n) | |\n| B | 1000 | \(tiny) | 5 | |\n| C | \(huge) | 1 | 5 | |\n\n| Fecha | Préstamo | Importe |\n| - | - | - |\n| 2026-01-01 | A | \(n) |")
        for s in loans.statuses() { _ = (s.progress, s.nextDue, s.installmentsLeft, s.estimatedEnd, loans.dueDates(s, upTo: DayKey.adding(days: 800, to: DayKey.today()))) }
        let books = Parse.lecturas("---\nobjetivo_anual: \(n)\n---\n| Título | Estado | Nota | Páginas |\n| - | - | - | - |\n| A | Terminado | \(n) | \(n) |")
        _ = (books.goal, books.books.first?.rating, books.books.first?.pages, books.projection())
        let trips = Parse.viajes("| Destino | Salida | Presupuesto |\n| - | - | - |\n| A | 2026-12-01 | \(n) |\n\n| Fecha | Viaje | Concepto | Importe |\n| - | - | - | - |\n| 2026-12-01 | A | x | \(n) |")
        for t in trips.trips { _ = (trips.spent(t), t.days) }
        let car = Parse.vehiculo("---\nkm: \(n)\n---\n## Mantenimiento\n| Fecha | Km | Qué | Taller | Coste | Cada (km) | Cada (meses) |\n| - | - | - | - | - | - | - |\n| 2026-01-01 | \(n) | X | | \(n) | \(n) | \(n) |\n\n## Repostajes\n| Fecha | Km | Litros | Importe |\n| - | - | - | - |\n| 2026-01-01 | \(n) | \(n) | \(n) |\n| 2026-02-01 | 5 | 1 | 1 |")
        _ = (car.currentKm, car.nextServices(), car.consumption, car.spent(year: 2026), car.currentKm.map(Vehiculo.kmText))
        _ = (Parse.medicacion("| Medicamento | Dosis | Forma | Cada |\n| - | - | - | - |\n| A | 1 mg | Pastilla | \(n) |\n| B | 1 mg | Pastilla | cada \(n) semanas |").meds.map(\.every))
        for verb in ["animo", "peso", "dormi", "gasto", "libro", "cuota", "cintura", "tarea"] { _ = QuickCommand.parse("\(verb) \(n)") }
        _ = (Edit.budgetNumber(Double(n) ?? 1e30), Money.format(Double(n) ?? 1e30), Money.exact(Double(n) ?? 1e30), Money.parse(n), MD.int(Double(n)))
    }
    // los dos valores razonables siguen siendo los que eran
    #expect(MD.int(5) == 5 && MD.int(-3) == -3 && MD.int(1e12) == nil && MD.int(.nan) == nil && MD.int(.infinity) == nil && MD.int(nil) == nil)
    #expect(QuickCommand.parse("animo 4") == nil)   // el ánimo ya no se lleva
    #expect(Vehiculo.km("99999999999") == nil && Vehiculo.km("250.000") == 250_000)
    let loan = try #require(Parse.prestamos("| Préstamo | Pendiente | Cuota | Día |\n| - | - | - | - |\n| A | 1000 | \(tiny) | 5 |").statuses().first)
    #expect(loan.installmentsLeft == nil && loan.estimatedEnd == nil)   // sin fecha de fin en vez de un cierre
}

// MARK: Trámites y seguros

@Test func tramitesAreParsedAndTheirNextDeadlineFollowsWhatWasDone() throws {
    let d = Parse.tramites(tramitesFixture)
    #expect(d.procedures.map(\.name) == ["Renta", "IBI", "Basuras", "Renovar DNI"])   // sin plazo no cuenta
    #expect(d.insurances.map(\.name) == ["Hogar", "Salud", "Vida"])
    let today = DayKey.today()
    let renta = try #require(d.procedures.first)
    #expect(renta.pending == DayKey.adding(days: 10, to: today) && renta.period == .months(12) && renta.amount == nil)
    // el IBI hecho hace 20 días cumple el plazo más cercano: el siguiente es el de dentro de un año
    let ibi = d.procedures[1]
    #expect(ibi.amount == 420 && ibi.pending.map { $0 > today } == true)
    // vencido y sin hacer: sigue pendiente, con fecha pasada
    #expect(d.procedures[2].pending == DayKey.adding(days: -3, to: today) && d.procedures[2].period == .months(6))
    // de una sola vez y hecho: ya no está pendiente
    #expect(d.procedures[3].period == nil && d.procedures[3].pending == nil)
    #expect(d.pendingProcedures.map(\.procedure.name) == ["Basuras", "Renta", "IBI"])
    // seguros: anual por defecto, coste al año y próxima renovación
    #expect(d.insurances[0].company == "Mapfre" && d.insurances[0].policy == "H-123" && d.insurances[0].phone == "900 100 200" && d.insurances[2].period == .months(12))
    #expect(d.yearlyInsurance == 320 + 55 * 12 + 25)
    #expect(d.insurances[0].nextRenewal(from: today) == DayKey.adding(days: 20, to: today) && d.insurances[2].nextRenewal(from: today) == nil)
    #expect(try d.insurances[1].nextRenewal(from: #require(DayKey.date("2026-10-24"))) == DayKey.date("2026-11-15"))
}

@Test func doneCountsForTheNearestDeadline() throws {
    func p(_ anchor: String, done: String?) -> TramitesData.Procedure {
        .init(name: "X", anchor: D(anchor), period: .months(12), amount: nil, done: done.map(D), notes: "", line: 1)
    }
    #expect(p("2026-06-30", done: nil).pending == D("2026-06-30"))
    #expect(p("2026-06-30", done: "2026-05-10").pending == D("2027-06-30"))   // presentada antes del plazo
    #expect(p("2026-06-30", done: "2026-07-05").pending == D("2027-06-30"))   // unos días tarde: cumple el que acaba de pasar
    #expect(p("2026-06-30", done: "2027-06-01").pending == D("2028-06-30"))   // un año después, el siguiente
    #expect(p("2026-06-30", done: "2025-12-01").pending == D("2026-06-30"))   // hecho antes del primer plazo apuntado
    #expect(TramitesData.Period.parseOptional("") == nil && TramitesData.Period.parseOptional("Una vez") == nil && TramitesData.Period.parseOptional("Anual") == .months(12))
}

@MainActor @Test func tramitesAlertCalendarAndGastos() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let alerts = store.tramiteAlerts(today: today)
    #expect(alerts.contains { $0.text.hasPrefix("Basuras: el plazo acabó") && $0.level == .urgent })
    #expect(alerts.contains { $0.text.hasPrefix("Renta: plazo en 10 días") && $0.level == .info })
    #expect(alerts.contains { $0.text.hasPrefix("El seguro de Hogar se renueva en 20 días (320 €)") || $0.text.hasPrefix("El seguro de Hogar se renueva en 20 días") })
    #expect(store.alerts(today: today).contains { $0.screen == .tramites })
    // marcarlo hecho apunta la fecha y el gasto; deshacer quita las dos cosas
    let month = Budget.monthKey(today)
    let before = store.budget(month)?.moves.count ?? 0
    let basuras = try #require(store.tramites.procedures.first { $0.name == "Basuras" })
    store.markTramiteDone(basuras, expense: true)
    let done = try #require(store.tramites.procedures.first { $0.name == "Basuras" })
    #expect(done.done == today && done.pending.map { $0 > today } == true && store.budget(month)?.moves.count == before + 1)
    #expect(!store.tramiteAlerts(today: today).contains { $0.text.hasPrefix("Basuras") })
    store.undo()
    #expect(store.tramites.procedures.first { $0.name == "Basuras" }?.done == nil && store.budget(month)?.moves.count == before)
    // la prima va a la partida de la fila y no se apunta dos veces
    let salud = try #require(store.tramites.insurances.first { $0.name == "Salud" })
    #expect(!store.seguroLogged(salud) && store.logSeguroPayment(salud) == "Seguro vida" && store.seguroLogged(salud))
    // calendario y Calendar
    let days = store.agenda(from: DayKey.adding(days: -5, to: today), to: DayKey.adding(days: 30, to: today)).values.joined()
    #expect(days.contains { $0.title == "Plazo: Renta" } && days.contains { $0.title == "Renueva el seguro de Hogar" } && days.contains { $0.kind == .tramite && $0.title == "Plazo: Basuras" })
    let ev = ICS.events(store.reminderSources(), plan: ReminderPlan(), today: today)
    #expect(ev.contains { $0.title == "Plazo: Renta" && $0.extraTriggers == ["-P7D"] } && ev.contains { $0.title.hasPrefix("Renueva el seguro de Hogar") && $0.extraTriggers == ["-P30D"] && $0.notes.contains("900 100 200") })
    #expect(!ev.contains { $0.title.contains("Basuras") })   // ya vencido: no va a Calendar
    store.hiddenModules.insert(.tramites)
    #expect(!store.alerts(today: today).contains { $0.screen == .tramites } && ICS.events(store.reminderSources(), plan: ReminderPlan(), today: today).allSatisfy { !$0.uid.hasPrefix("tramite") && !$0.uid.hasPrefix("seguro") })
}

@MainActor @Test func tramitesTemplateTakesTheFirstEntriesAndExports() throws {
    let day = D("2026-10-20")
    let t1 = try #require(Edit.addTramite(try tpl("tramites"), name: "Tasa | basuras", due: day, every: "Semestral", amount: 60))
    let t2 = try #require(Edit.addSeguro(t1, name: "Coche", company: "X", premium: 400, every: "Anual", renewal: day, phone: "1", category: ""))
    let d = Parse.tramites(t2)
    #expect(d.procedures.map(\.name) == ["Tasa | basuras"] && d.procedures[0].period == .months(6) && d.procedures[0].amount == 60)
    // las filas de ejemplo de la plantilla siguen ahí, sin prima ni fecha (no suman ni avisan), y el nuevo va detrás
    #expect(d.insurances.map(\.name) == ["Hogar", "Salud", "Coche"] && d.insurances[2].premium == 400 && d.yearlyInsurance == 400)
    #expect(d.insurances.prefix(2).allSatisfy { $0.premium == 0 && $0.nextRenewal() == nil })
    // exportar
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
    let names = Set(try Store(root: try syntheticVault()).exportData(to: out).map(\.lastPathComponent))
    #expect(names.isSuperset(of: ["tramites.csv", "seguros.csv"]))
    let csv = try String(contentsOf: out.appendingPathComponent("seguros.csv"), encoding: .utf8)
    #expect(csv.contains("Hogar,Mapfre,H-123,320,cada año,") && csv.contains(",900 100 200,"))
}
