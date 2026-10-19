import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Etiquetas, menciones, resumen

@Test func tagsSnippetAndWords() {
    let text = "---\ntags:\n  - salud\n  - \"#peso\"\n---\n# Título\n\n> [!INFO] Nota **importante** con [[Peso|el peso]] #dieta y #Salud\n\n```\n#nocuenta\n```\nOtra línea #plan/semanal"
    #expect(NoteInfo.tags(text) == ["salud", "peso", "dieta", "plan/semanal"])
    #expect(NoteInfo.snippet(text) == "Nota importante con el peso #dieta y #Salud")
    #expect(NoteInfo.snippet("---\ntipo: x\n---\n# Solo título\n- [ ] primera tarea") == "primera tarea")
    #expect(NoteInfo.wordCount("Hola mundo, esto es una prueba.") == 6)
    #expect(NoteInfo.tags("# Título con # solo y C# aquí").isEmpty)
}

@Test func linkMentions() throws {
    let text = "Hoy pesé algo. Revisar el Peso pronto.\nYa enlazado: [[Peso]]\n`Peso` en código y https://x.com/Peso\n```\nPeso\n```\nPesos distintos"
    let out = try #require(Edit.linkMention(text, name: "Peso"))
    #expect(out.hasPrefix("Hoy pesé algo. Revisar el [[Peso]] pronto."))
    #expect(Edit.linkMention(out.replacingOccurrences(of: "el [[Peso]] pronto", with: "el [[Peso]] pronto"), name: "Peso") == nil)   // ya no quedan menciones libres
    let lower = try #require(Edit.linkMention("mi peso de hoy", name: "Peso"))
    #expect(lower == "mi [[Peso|peso]] de hoy")
    #expect(Edit.linkMention("xx", name: "xx") == nil)   // nombres cortos no
}

@MainActor @Test func tagsPinsAliasesOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    print("TAGS", store.allTags.prefix(8).map { "\($0.tag)=\($0.count)" })
    #expect(!store.allTags.isEmpty)
    let t = try #require(store.allTags.first)
    #expect(!store.notes(withTag: t.tag).isEmpty)
    store.edit("Moda/Armario.md") { Edit.setFrontmatter($0, key: "tipo", value: "armario") }
    store.edit("Moda/Armario.md") { Edit.setFrontmatterList($0, key: "aliases", items: ["Ropa", "Vestuario"]) }
    #expect(store.resolve("ropa") == "Moda/Armario.md")
    #expect(store.fuzzyResolve("Vestuario") == "Moda/Armario.md")
    store.togglePin("Casa/Casa.md")
    #expect(store.pinned.contains("Casa/Casa.md"))
    store.togglePin("Casa/Casa.md")
    #expect(!store.pinned.contains("Casa/Casa.md"))
    #expect(store.snippets["Casa/Casa.md"]?.isEmpty == false)
    print("MENCIONES de Peso:", store.unlinkedMentions(of: "Cambio físico/Peso.md").map(\.name))
}

// MARK: - Prioridad, plantillas y ánimo

@Test func taskPriority() throws {
    let text = "- [ ] Llamar al banco ⏫ 📅 2026-10-20\n- [ ] Regar 🔽\n- [ ] Normal"
    let t = Parse.tasks(text, file: "a.md")
    #expect(t.map(\.priority) == [3, 1, 0] && t[0].text == "Llamar al banco" && t[1].text == "Regar")
    let kept = try #require(Edit.updateTask(text, task: t[0], newText: "Llamar al banco hoy", due: nil))
    #expect(kept.hasPrefix("- [ ] Llamar al banco hoy ⏫\n"))
    let changed = try #require(Edit.updateTask(text, task: t[0], newText: "Llamar", due: DayKey.date("2026-10-21"), priority: 2))
    #expect(changed.hasPrefix("- [ ] Llamar 🔼 📅 2026-10-21\n"))
    let none = try #require(Edit.updateTask(text, task: t[1], newText: "Regar", due: nil, priority: 0))
    #expect(none.contains("\n- [ ] Regar\n"))
    #expect(Edit.addInboxTask("## Pendiente de clasificar\n- [ ] x", task: "Pagar", due: nil, priority: 3)!.contains("- [ ] Pagar ⏫"))
    let today = DayKey.date("2026-10-19")!
    let p1 = NaturalDate.extractTask("pagar urgente el viernes", today: today)
    #expect(p1.priority == 3 && p1.text == "pagar" && DayKey.string(p1.date!) == "2026-10-23")
    let p2 = NaturalDate.extractTask("comprar pan!", today: today)
    #expect(p2.priority == 3 && p2.text == "comprar pan" && p2.date == nil)
    #expect(NaturalDate.extractTask("llamar mañana", today: today).priority == 0)
}

@MainActor @Test func templatesMoodAndBasesOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    #expect(store.userTemplates().isEmpty)
    store.createSampleTemplates()
    #expect(store.userTemplates() == ["Idea", "Lectura", "Reunión", "Viaje"])
    #expect(!store.notes.contains { $0.path.hasPrefix("Plantillas/") })       // las plantillas no salen como notas
    let tpl = try #require(store.userTemplate("Reunión", title: "Reunión equipo"))
    #expect(tpl.folder == "Proyectos" && tpl.body.contains("# Reunión equipo") && !tpl.body.contains("plantilla_carpeta") && !tpl.body.contains("{{"))
    let rel = try #require(store.createNote(folder: "Proyectos", name: "Reunión equipo", template: "Reunión"))
    #expect(store.noteMeta[rel]?["tipo"] == "reunion" && store.noteTags[rel]?.contains("reunion") == true)

    // ánimo y sueño en la nota del día
    let day = DayKey.date("2026-11-10")!
    #expect(store.diaryValue(day, "animo") == nil)
    store.setDiaryValue(day, "animo", 4)
    store.setDiaryValue(day, "sueno_h", 7.5)
    #expect(store.diaryValue(day, "animo") == 4 && store.diaryValue(day, "sueno_h") == 7.5)
    #expect(store.read(Store.diaryPath(day)).contains("animo: 4"))
    store.setDiaryValue(day, "animo", nil)
    #expect(store.diaryValue(day, "animo") == nil)
    #expect(store.diarySeries("sueno_h", from: DayKey.date("2026-11-01")!, to: DayKey.date("2026-11-30")!).count == 1)
    // nota de hoy
    store.openToday()
    #expect(store.pendingNote == Store.diaryPath(DayKey.today()) && store.notes.contains { $0.path == Store.diaryPath(DayKey.today()) })
    #expect(store.modified[Store.diaryPath(DayKey.today())] != nil)
}
