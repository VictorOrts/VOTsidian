import AppIntents
import Foundation
import Testing
@testable import VOTsidian

// MARK: - Siri y Atajos

private func item(_ title: String, _ kind: AgendaItem.Kind = .task, at minutes: Int? = nil) -> AgendaItem {
    AgendaItem(id: title, kind: kind, title: title, date: DayKey.today(), minutes: minutes)
}

@Test func siriReadsTodayWithTimesFirstAndSkipsDone() {
    let text = SiriText.day([item("Comprar pan"), item("Dentista", .appointment, at: 17 * 60 + 30), item("Hecha", .done),
                               item("Llamar a Ana", at: 9 * 60)], overdue: 0)
    #expect(text == "Hoy tienes 3 cosas: Comprar pan; 09:00, Llamar a Ana; 17:30, Dentista.")
    #expect(SiriText.day([], overdue: 0) == "Hoy no tienes nada en la agenda.")
    #expect(SiriText.day([item("Hecha", .done)], overdue: 1) == "Hoy no tienes nada en la agenda. Hay una tarea vencida.")
    #expect(SiriText.day([item("Una")], overdue: 3) == "Hoy tienes una cosa: Una. Hay 3 tareas vencidas.")
}

/// «Qué tengo el miércoles»: el día se dice por su nombre y lo vencido solo cuenta hoy.
@Test @MainActor func siriReadsAnyDay() async throws {
    let today = DayKey.today()
    #expect(SiriText.label(today, today: today) == "Hoy")
    #expect(SiriText.label(DayKey.adding(days: 1, to: today), today: today) == "Mañana")
    let wed = DayKey.date("2026-10-28")!
    #expect(SiriText.label(wed, today: DayKey.date("2026-10-26")!) == "El miércoles 28 de octubre")
    #expect(SiriText.day([], label: "El miércoles 28 de octubre", overdue: 0) == "El miércoles 28 de octubre no tienes nada en la agenda.")

    let store = Store(root: try syntheticVault())
    let day = DayKey.adding(days: 2, to: today)
    store.addAppointment("Endocrino", date: day, time: 17 * 60 + 45)
    var hoy = HoyIntent()
    hoy.store = store
    hoy.fecha = day.addingTimeInterval(15 * 3600)   // Siri manda la fecha con hora
    let result = try await hoy.perform()
    #expect(result.value?.contains("17:45, Endocrino") == true)
}

@Test func siriCutsLongListsAndSaysHowManyMore() {
    let many = (1...9).map { item("T\($0)") }
    #expect(SiriText.day(many, overdue: 0, limit: 2) == "Hoy tienes 9 cosas: T1; T2; y 7 más.")
    #expect(SiriText.alerts([]) == "No hay avisos pendientes.")
    #expect(SiriText.alerts(["Pagar IBI"]) == "Un aviso: Pagar IBI.")
    #expect(SiriText.alerts(["A", "B", "C"], limit: 2) == "3 avisos: A; B; y 1 más.")
}

/// Cada pantalla tiene su nombre para Siri (la lista es literal: una pantalla nueva sin nombre no se podría abrir con la voz).
@Test func everyScreenHasASiriName() {
    for s in Screen.allCases { #expect(Screen.caseDisplayRepresentations[s] != nil, "\(s.rawValue)") }
}

/// Lo que se dice a Siri se apunta igual que en la captura rápida: una tarea con fecha y hora, y una compra en su lista.
@Test @MainActor func siriIntentsWriteToTheNotes() async throws {
    let store = Store(root: try syntheticVault())

    var tarea = AnadirTareaIntent()
    tarea.store = store
    tarea.texto = "llamar al taller mañana a las 10"
    _ = try await tarea.perform()
    let manana = DayKey.adding(days: 1, to: DayKey.today())
    #expect(store.tasks.contains { $0.text == "llamar al taller" && $0.due == manana && $0.time == 600 })

    var captura = CapturarIntent()
    captura.store = store
    captura.texto = "compra mostaza"
    _ = try await captura.perform()
    #expect(store.read(VaultPath.compra).localizedCaseInsensitiveContains("mostaza"))
}
