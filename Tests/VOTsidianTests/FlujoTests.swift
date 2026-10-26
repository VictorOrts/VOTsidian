import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Flujo: captura única, historial, fijadas, panel Hoy y enlaces al lado

@Test func captureUnderstandsAnySentence() {
    let today = DayKey.date("2026-10-19")!   // lunes
    func g(_ s: String, day: Date? = nil, tasksOnly: Bool = false) -> CaptureGuess? { Capture.interpret(s, defaultDay: day, tasksOnly: tasksOnly, today: today) }
    func values(_ x: CaptureGuess?) -> [String] { x?.chips.map(\.value) ?? [] }

    // tarea con todo lo que lleva la frase
    let t = g("dentista el viernes a las 17:30 durante 1h")
    if case .task(let p)? = t?.command { #expect(p.text == "dentista" && DayKey.string(p.date!) == "2026-10-23" && p.time == 1050 && p.duration == 60) } else { Issue.record("no es tarea") }
    #expect(values(t).starts(with: ["Tarea", dayLabel(DayKey.date("2026-10-23")!), "17:30", "1 h"]))
    #expect(t?.destination == "Inbox")
    // sin fecha: el día de la pantalla, o el Inbox sin fecha
    if case .task(let p)? = g("pasear a Tor", day: DayKey.adding(days: 2, to: today))?.command { #expect(p.date == DayKey.adding(days: 2, to: today)) } else { Issue.record("no es tarea") }
    #expect(values(g("ordenar fotos")).contains("sin fecha"))
    #expect(values(g("llamar a mamá mañana")).contains("mañana"))
    // las órdenes de ⌘K
    #expect(g("peso 101,2")?.command == .weight(101.2, today))
    #expect(g("compra leche y pan")?.command == .shopping(["leche", "pan"]))
    #expect(g("cita dentista el 29/10 a las 17:30")?.command == .appointment("dentista", DayKey.date("2026-10-29")!, 1050))
    // un importe en euros es un gasto; un número suelto, no
    if case .expense(let e)? = g("22 € cena con Ana")?.command { #expect(e.amount == 22) } else { Issue.record("no es gasto") }
    if case .expense? = g("gasolina 48 euros")?.command {} else { Issue.record("«48 euros» no es gasto") }
    if case .task? = g("revisar 3 facturas")?.command {} else { Issue.record("un número suelto no es gasto") }
    // en los campos de tareas todo es tarea: «compra …» no va a la lista de la compra
    if case .task(let p)? = g("compra regalo para Ana el viernes", tasksOnly: true)?.command { #expect(p.text.hasPrefix("compra regalo")) } else { Issue.record("no es tarea") }
    #expect(g("   ") == nil && g("") == nil)
    #expect(Capture.looksLikeMoney("12,50€") && Capture.looksLikeMoney("pagué 30 euros") && !Capture.looksLikeMoney("3 eurovisiones"))
}

@MainActor @Test func captureSavesWhatItShows() throws {
    let store = Store(root: try syntheticVault())
    let guess = try #require(Capture.interpret("llamar al taller mañana a las 10:00", tasksOnly: true))
    store.run(guess.command)
    let saved = store.tasks.first { $0.text == "llamar al taller" }
    #expect(saved?.due == DayKey.adding(days: 1, to: DayKey.today()) && saved?.time == 600)
}

@MainActor @Test func backAndForwardWalkTheScreens() throws {
    let store = Store(root: try syntheticVault())
    store.screen = .inicio
    store.backStack = []; store.forwardStack = []; store.syncHistoryFlags()
    store.screen = .gastos
    store.screen = .vehiculo
    #expect(store.canGoBack && !store.canGoForward)
    store.goBack()
    #expect(store.screen == .gastos && store.canGoForward)
    store.goBack()
    #expect(store.screen == .inicio && !store.canGoBack)
    store.goForward()
    #expect(store.screen == .gastos)
    store.screen = .notas   // ir a otra pantalla borra lo de «adelante»
    #expect(!store.canGoForward)
    // cambiar de modo dentro de la Agenda no llena el historial
    store.screen = .dia
    let depth = store.backStack.count
    store.screen = .tareas
    store.screen = .planificar
    #expect(store.backStack.count == depth)
    // la Agenda vuelve a su último modo
    store.screen = .gastos
    store.go(.dia)
    #expect(store.screen == .planificar)
}

@Test func pinsAreStableAndUnique() {
    #expect(Pins.parse(Pins.standard) == [.dia, .calendario, .notas])
    // los modos de la Agenda son la Agenda; Inicio no se fija; sin repetidos ni nombres desconocidos
    #expect(Pins.parse("Tareas|Mi día|Inicio|Gastos|Gastos|Nada") == [.dia, .gastos])
    let added = Pins.toggled(Pins.standard, .vehiculo)
    #expect(Pins.parse(added) == [.dia, .calendario, .notas, .vehiculo])
    #expect(Pins.parse(Pins.toggled(added, .planificar)) == [.calendario, .notas, .vehiculo])
}

@MainActor @Test func linksOpenBesideWhenThePanelIsShown() throws {
    let store = Store(root: try syntheticVault())
    store.screen = .gastos
    _ = store.open(link: URL(string: "votsidian://note/B")!, peek: true)
    #expect(store.peekNote == "Notas/B.md" && store.screen == .gastos && store.pendingNote == nil)
    _ = store.open(link: URL(string: "votsidian://note/A")!)
    #expect(store.pendingNote == "Notas/A.md")
    // una nota con pantalla propia sigue abriendo su pantalla
    _ = store.open(link: URL(string: "votsidian://note/Vehículo")!, peek: true)
    #expect(store.screen == .vehiculo)
}

@MainActor @Test func focusSessionsEndAndCanBeStopped() async throws {
    let store = Store(root: try syntheticVault())
    store.startFocus("informe", minutes: 25)
    #expect(store.focus?.title == "informe" && store.focus?.minutes == 25)
    store.stopFocus()
    #expect(store.focus == nil)
    // uno que ya terminó se cierra solo y lo dice arriba
    store.startFocus("corto", minutes: 1, now: Date().addingTimeInterval(-60))
    // con toda la batería en marcha el hilo principal puede tardar: se espera hasta 5 s
    for _ in 0..<100 where store.focus != nil { try await Task.sleep(for: .milliseconds(50)) }
    #expect(store.focus == nil && store.message?.contains("corto") == true)
}

@MainActor @Test func panelAndPeekRender() throws {
    let store = Store(root: try syntheticVault())
    store.addTask("vencida", due: DayKey.adding(days: -2, to: DayKey.today()))
    store.addTask("para hoy a las 10:00", due: DayKey.today(), time: 600)
    func render<V: View>(_ name: String, _ view: V, size: CGSize) {
        let r = ImageRenderer(content: view.environment(store).frame(width: size.width, height: size.height))
        r.scale = 1
        #expect(r.cgImage != nil, "\(name) no se pudo pintar")
    }
    render("Panel Hoy", HoyPanel(), size: CGSize(width: 300, height: 800))
    store.peekNote = "Notas/A.md"
    render("Panel con nota", HoyPanel(), size: CGSize(width: 300, height: 800))
    render("Nota en ventana", NotePeek(path: "Notas/A.md", inWindow: true), size: CGSize(width: 600, height: 500))
    render("Nota que no existe", NotePeek(path: "Notas/No existe.md"), size: CGSize(width: 300, height: 300))
    render("Campo de captura", CaptureField(defaultDay: DayKey.today()), size: CGSize(width: 500, height: 80))
    for s in Screen.allCases { render("Ventana \(s)", ScreenView(screen: s), size: CGSize(width: 900, height: 700)) }
}

@MainActor @Test func historySkipsHiddenModulesAndFocusIsBounded() throws {
    let store = Store(root: try syntheticVault())
    store.screen = .inicio
    store.backStack = []; store.forwardStack = []; store.syncHistoryFlags()
    store.screen = .vehiculo
    store.screen = .gastos
    store.screen = .notas
    store.hiddenModules.insert(.finanzas)   // Gastos ya no se ve: Atrás la salta
    store.goBack()
    #expect(store.screen == .vehiculo)
    store.hiddenModules.insert(.vehiculo)
    store.goBack()
    #expect(store.screen == .inicio)
    store.goBack()   // sin nada detrás, no se mueve
    #expect(store.screen == .inicio && !store.canGoBack)
    // un ⏱ disparatado no desborda el temporizador: se queda en un día
    store.startFocus("x", minutes: Int.max)
    #expect(store.focus?.minutes == 24 * 60)
    store.stopFocus()
}

@MainActor @Test func dayChangeRebuildsWhatDependsOnToday() throws {
    let store = Store(root: try syntheticVault())
    let today = store.today
    _ = store.agenda(from: today, to: today)
    #expect(!store.agendaCache.isEmpty)
    store.checkDayChange(now: today)   // mismo día: nada
    #expect(!store.agendaCache.isEmpty && store.today == today)
    let tomorrow = DayKey.adding(days: 1, to: today)
    store.checkDayChange(now: tomorrow)
    #expect(store.today == tomorrow && store.agendaCache.isEmpty && store.budgetCache.isEmpty)
}

@Test func formDatesFollowTheNewDay() {
    let cal = DayKey.calendar()
    let old = DayKey.date("2026-10-25")!, new = DayKey.date("2026-10-26")!   // la noche del cambio de hora
    // la fecha de un formulario (con hora) pasa al día nuevo y conserva la hora; la de un panel (medianoche), igual
    let form = cal.date(bySettingHour: 23, minute: 40, second: 0, of: old)!
    #expect(DayKey.following(form, from: old, to: new) == cal.date(bySettingHour: 23, minute: 40, second: 0, of: new))
    #expect(DayKey.following(old, from: old, to: new) == new)
    // una fecha elegida a mano (otro día) no se toca
    #expect(DayKey.following(DayKey.date("2026-10-20")!, from: old, to: new) == nil)
}

@MainActor @Test func overdueDoseShowsTodayAndCountsFromToday() throws {
    let store = Store(root: try syntheticVault())
    let today = DayKey.today()
    let late = try #require(store.medicacion.daysUntilNext)
    try #require(late < 0)   // en el vault sintético el pinchazo va con retraso
    let every = try #require(store.medicacion.main?.every)
    let agenda = store.agenda(from: today, to: DayKey.adding(days: every, to: today))
    let next = agenda.values.flatMap { $0 }.filter { $0.kind == .doseNext }.sorted { $0.date < $1.date }
    #expect(next.first?.date == today && next.first?.detail == "\(-late) días tarde")
    #expect(next.dropFirst().first?.date == DayKey.adding(days: every, to: today))
}
