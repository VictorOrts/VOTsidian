import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Edición genérica

@Test func genericRowEdits() throws {
    let text = "# T\n| A | B |\n| --- | --- |\n| x | 1 |\n| y | 2 |\n"
    let line = 3
    let upd = try #require(Edit.updateRow(text, line: line, expectFirst: "x", cells: ["x2", "a|b"]))
    #expect(upd.contains("| x2 | a\\|b |"))
    #expect(MD.cells(MD.lines(upd)[line]) == ["x2", "a|b"])
    #expect(Edit.updateRow(text, line: line, expectFirst: "z", cells: ["q", "q"]) == nil)
    let del = try #require(Edit.deleteRow(text, line: 4, expectFirst: "y"))
    #expect(!del.contains("| y |"))
    let ins = try #require(Edit.insertTableRow(text, afterLine: 4, cells: ["n", "3"]))
    #expect(ins.contains("| y | 2 |\n| n | 3 |"))
}

@Test func checkboxAndTaskEdits() throws {
    let text = "- [ ] Uno 📅 2026-10-20\n  - [x] Sub [completion:: 2026-10-01]\ntexto"
    let on = try #require(Edit.toggleCheckbox(text, line: 0, on: DayKey.date("2026-10-19")!))
    #expect(on.hasPrefix("- [x] Uno 📅 2026-10-20 [completion:: 2026-10-19]"))
    let off = try #require(Edit.toggleCheckbox(on, line: 0))
    #expect(off == text)
    #expect(Edit.toggleCheckbox(text, line: 2) == nil)
    let sub = try #require(Edit.toggleCheckbox(text, line: 1))
    #expect(sub.contains("  - [ ] Sub") && !sub.contains("completion"))

    let task = Parse.tasks(text, file: "a.md")[0]
    let up = try #require(Edit.updateTask(text, task: task, newText: "Dos", due: nil))
    #expect(up.hasPrefix("- [ ] Dos\n"))
    let up2 = try #require(Edit.updateTask(text, task: task, newText: "Uno", due: DayKey.date("2026-11-01")))
    #expect(up2.hasPrefix("- [ ] Uno 📅 2026-11-01\n"))
    let del = try #require(Edit.deleteLine(text, raw: task.raw, hint: task.line))
    #expect(del.hasPrefix("  - [x] Sub"))
    #expect(Parse.tasks(text, file: "a.md")[1].completed == DayKey.date("2026-10-01"))
}

@Test func frontmatterEdits() throws {
    let text = "---\ntipo: x\nsemana: \"W1\"\nlista:\n  - a\n  - b\nnumero: 5\n---\n# Cuerpo"
    var t = try #require(Edit.setFrontmatter(text, key: "numero", value: "9"))
    #expect(MD.frontmatter(t)["numero"] == "9")
    t = try #require(Edit.setFrontmatter(t, key: "semana", value: "W2"))
    #expect(t.contains("semana: \"W2\""))
    t = try #require(Edit.setFrontmatter(t, key: "nuevo", value: "v"))
    #expect(MD.frontmatter(t)["nuevo"] == "v" && t.hasSuffix("# Cuerpo"))
    t = try #require(Edit.setFrontmatterList(t, key: "lista", items: ["a", "c", "d"]))
    #expect(MD.frontmatterList(t, key: "lista") == ["a", "c", "d"])
    #expect(MD.frontmatter(t)["numero"] == "9")
    #expect(Edit.setFrontmatter("sin frontmatter", key: "a", value: "b") == nil)
}

@Test func renameLinksAndSections() throws {
    let text = "Ver [[Peso]] y [[Peso|alias]] y [[Peso#x]] y [[Pesos]] y [[Mapa\\|Peso]]"
    let out = Edit.renameLinks(text, old: "Peso", new: "Control $peso")
    #expect(out == "Ver [[Control $peso]] y [[Control $peso|alias]] y [[Control $peso#x]] y [[Pesos]] y [[Mapa\\|Peso]]")

    let inbox = "## Ideas\n- \n\n## Otro\n- x"
    let a = try #require(Edit.appendToSection(inbox, section: "Ideas", line: "- nueva"))
    #expect(a.hasPrefix("## Ideas\n- nueva\n"))
    let b = try #require(Edit.appendToSection(a, section: "Ideas", line: "- otra"))
    #expect(b.hasPrefix("## Ideas\n- nueva\n- otra\n"))
}

@Test func habitRowEdits() throws {
    let week = Template.week(key: "2026-W44", monday: DayKey.date("2026-10-26")!, habits: [HabitDef(name: "Agua")])
    let added = try #require(Edit.addHabitRow(week, name: "Lectura"))
    #expect(Parse.week(added, key: "k").habits.map(\.name) == ["Agua", "Lectura"])
    #expect(Edit.addHabitRow(added, name: "agua") == added)
    let removed = try #require(Edit.removeHabitRow(added, name: "Agua"))
    #expect(Parse.week(removed, key: "k").habits.map(\.name) == ["Lectura"])
}


@Test func habitTableAndUnlink() throws {
    let week = Template.week(key: "2026-W44", monday: DayKey.date("2026-10-26")!, habits: [HabitDef(name: "Agua", criterion: "2,5 L"), HabitDef(name: "Pasos")])
    var marked = try #require(Edit.toggleHabit(week, habit: "Agua", day: 2))
    #expect(Parse.week(marked, key: "k").habits[0].criterion == "2,5 L")
    marked = try #require(Edit.setHabitTable(marked, defs: [HabitDef(name: "Agua", criterion: "3 L"), HabitDef(name: "Creatina", criterion: "5 g")]))
    let r = Parse.week(marked, key: "k")
    #expect(r.habits.map(\.name) == ["Agua", "Creatina"])
    #expect(r.habits[0].criterion == "3 L" && r.habits[0].days[2] && r.habits[1].criterion == "5 g")
    #expect(marked.contains("## 2. Mirar atrás")) // el resto de la nota no se toca

    let text = "[[Inicio]] · [[Tareas]] · [[Inbox]]\n| [[Tareas]] | [[Peso]] |\nVer [[Proyectos|los proyectos]] y [[Tareas#x]]\n[[Tareas]] · [[Inbox]]"
    let a = Edit.unlink(text, name: "Tareas")
    #expect(a == "[[Inicio]] · [[Inbox]]\n| Tareas | [[Peso]] |\nVer [[Proyectos|los proyectos]] y Tareas\n[[Inbox]]")
    #expect(Edit.unlink("Ver [[Proyectos|los proyectos]]", name: "Proyectos") == "Ver los proyectos")
}
