import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Autocompletado del editor

@Test func editorCompletionDetect() {
    func d(_ t: String, _ caret: Int? = nil) -> EditorCompletion.Match? { EditorCompletion.detect(t, caret: caret ?? t.count) }
    #expect(d("ver [[Pe") == EditorCompletion.Match(kind: .link, start: 4, end: 8, query: "Pe"))
    #expect(d("[[")?.query == "" && d("[[")?.kind == .link)
    #expect(d("ver [[Peso]] y más") == nil)                     // enlace ya cerrado
    #expect(d("ver [[Peso]] y [[Ca")?.query == "Ca")
    #expect(d("línea uno\nver [[Mo")?.query == "Mo" && d("línea uno\nver [[Mo", 9)?.query == nil)   // solo cuenta la línea actual
    #expect(d("ver [[Peso", 6)?.query == "")                    // cursor justo tras [[
    #expect(d("hoy #die")?.kind == .tag && d("hoy #die")?.query == "die")
    #expect(d("# Título") == nil && d("#") == nil && d("hoy #") == nil)   // encabezados y # solo
    #expect(d("C# es otro") == nil && d("a#b") == nil)
    #expect(d("texto normal") == nil)
}

@Test func editorCompletionSuggestions() {
    let notes: [(name: String, folder: String, aliases: [String])] = [
        ("Peso", "Salud", []), ("Plan Nutricional", "Salud", []), ("Personas", "Organización", []),
        ("Armario", "Moda", ["Ropa"]), ("Casa", "Casa", []),
    ]
    let a = EditorCompletion.noteSuggestions(query: "pe", notes: notes, current: "Casa", recent: [])
    #expect(a.map(\.title) == ["Personas", "Peso", "Crear nota «pe»"])
    #expect(a[1].insert == "[[Peso]]" && a.last?.create == "pe")
    #expect(EditorCompletion.noteSuggestions(query: "peso", notes: notes, current: "Casa", recent: []).map(\.title) == ["Peso"])   // exacta: sin «crear»
    #expect(EditorCompletion.noteSuggestions(query: "ropa", notes: notes, current: "", recent: []).first?.title == "Armario")        // por alias
    #expect(EditorCompletion.noteSuggestions(query: "nutri", notes: notes, current: "", recent: []).first?.title == "Plan Nutricional") // contiene
    let empty = EditorCompletion.noteSuggestions(query: "", notes: notes, current: "Casa", recent: ["Personas", "Peso"])
    #expect(empty.map(\.title).prefix(2) == ["Personas", "Peso"] && !empty.contains { $0.title == "Casa" })
    let tags = EditorCompletion.tagSuggestions(query: "sa", tags: [("salud", 5), ("casa", 1), ("nutricion", 2)])
    #expect(tags.map(\.title) == ["#salud", "#casa"] && tags[0].insert == "#salud ")
}

@Test func tidyFooters() {
    let a = "# T\ntexto\n\nInicio\n\n---\nRelacionado: [[A]] · [[B]]\n"
    #expect(Edit.tidyFooter(a) == "# T\ntexto\n\n---\nRelacionado: [[A]] · [[B]]\n")
    let b = "# T\ntexto\n\n---\nInicio\n"
    #expect(Edit.tidyFooter(b) == "# T\ntexto\n")
    let c = "---\ntipo: x\n---\n# T\n\nInicio es una palabra\n\n---\n\n---\n[[X]]\n"
    #expect(Edit.tidyFooter(c) == "---\ntipo: x\n---\n# T\n\nInicio es una palabra\n\n---\n[[X]]\n")
    let d = "Inicio\n" + String(repeating: "línea\n", count: 8) + "---\nInicio\n"
    #expect(Edit.tidyFooter(d).hasPrefix("Inicio\n"))   // solo se limpia el pie, no el principio
}

@MainActor @Test func aliasLinksAndSkipOnCopy() throws {
    guard let path = ProcessInfo.processInfo.environment["VAULT_COPY"] else { return }
    let store = Store(root: try tempVaultCopy(path))
    store.edit("Moda/Armario.md") { Edit.setFrontmatterList($0, key: "aliases", items: ["Ropa"]) }
    store.edit("Casa/Casa.md") { $0 + "\nVer [[Ropa]]\n" }
    #expect(store.outLinks["Casa/Casa.md"]?.contains("Moda/Armario.md") == true)    // el alias cuenta en el grafo
    // una nota cuyo nombre contiene «Plantillas» no se oculta
    _ = store.createNote(folder: "Casa", name: "Reglas de Plantillas", template: "En blanco")
    #expect(store.notes.contains { $0.name == "Reglas de Plantillas" })
}

@Test func removeDataviewBlocks() {
    let text = """
    ---
    tipo: x
    ---
    # Nota

    ## Progreso

    ```dataviewjs
    const a = 1;
    // # no es un encabezado
    ```

    ---

    ## Registro
    | A | B |
    | - | - |
    | 1 | 2 |

    **Resumen (automático):**
    ```dataview
    TABLE x
    ```

    ## Objetivo
    ```dataview
    LIST
    ```
    Texto que se queda.

    ## Código normal
    ```swift
    let x = 1
    ```
    """
    let out = Edit.removeDataview(text)
    #expect(!out.contains("dataview") && !out.contains("const a") && !out.contains("Resumen (automático)") && !out.contains("## Progreso"))
    #expect(out.contains("## Registro") && out.contains("| 1 | 2 |") && out.contains("## Objetivo\nTexto que se queda."))
    #expect(out.contains("```swift\nlet x = 1\n```") && out.hasPrefix("---\ntipo: x\n---\n# Nota\n"))
    #expect(Edit.removeDataview("# Sin bloques\n\ntexto\n") == "# Sin bloques\n\ntexto\n")   // no toca lo que no tiene bloques
}


// MARK: - Edición del editor y pestañas (lógica de la interfaz)

@Test func editorOps() {
    // negrita sobre una selección y sin selección
    #expect(EditorOps.wrap("hola mundo", selection: 5..<10, pre: "**", post: "**") == .init(text: "hola **mundo**", caret: 14))
    #expect(EditorOps.wrap("hola ", selection: 5..<5, pre: "**", post: "**") == .init(text: "hola ****", caret: 7))      // cursor en medio
    #expect(EditorOps.wrap("hola", selection: nil, pre: "`", post: "`") == .init(text: "hola``", caret: 5))
    // insertar sustituye la selección
    #expect(EditorOps.insert("ver X aquí", selection: 4..<5, "[[Peso]]") == .init(text: "ver [[Peso]] aquí", caret: 12))
    // prefijo de línea: pone, quita y respeta la línea del cursor
    let text = "uno\ndos\ntres"
    #expect(EditorOps.linePrefix(text, caret: 5, prefix: "- ") == .init(text: "uno\n- dos\ntres", caret: 7))
    #expect(EditorOps.linePrefix("uno\n- dos\ntres", caret: 7, prefix: "- ") == .init(text: text, caret: 5))
    #expect(EditorOps.linePrefix("", caret: nil, prefix: "## ") == .init(text: "## ", caret: 3))
    #expect(EditorOps.linePrefix("a", caret: 0, prefix: "- [ ] ").text == "- [ ] a")
    // aceptar una sugerencia
    let m = EditorCompletion.detect("ver [[Pe", caret: 8)!
    #expect(EditorOps.accept("ver [[Pe", match: m, insert: "[[Peso]]") == .init(text: "ver [[Peso]]", caret: 12))
    let m2 = EditorCompletion.detect("ver [[Pe]] y más", caret: 8)!        // ya había ]] detrás
    #expect(EditorOps.accept("ver [[Pe]] y más", match: m2, insert: "[[Peso]]") == .init(text: "ver [[Peso]] y más", caret: 12))
    let m3 = EditorCompletion.detect("hoy #sa", caret: 7)!
    #expect(EditorOps.accept("hoy #sa", match: m3, insert: "#salud ") == .init(text: "hoy #salud ", caret: 11))
    // con texto con emoji y tildes las posiciones siguen siendo en caracteres
    #expect(EditorOps.wrap("á🙂b", selection: 1..<2, pre: "_", post: "_") == .init(text: "á_🙂_b", caret: 4))
}

@Test func tabLogic() {
    var tabs = TabLogic.open([], active: nil, path: "A", newTab: false)
    #expect(tabs == ["A"])
    tabs = TabLogic.open(tabs, active: "A", path: "B", newTab: false)      // sustituye la activa
    #expect(tabs == ["B"])
    tabs = TabLogic.open(tabs, active: "B", path: "C", newTab: true)       // pestaña nueva
    tabs = TabLogic.open(tabs, active: "C", path: "D", newTab: true)
    #expect(tabs == ["B", "C", "D"])
    #expect(TabLogic.open(tabs, active: "D", path: "B", newTab: false) == tabs)   // ya abierta: no duplica
    #expect(TabLogic.open(tabs, active: "C", path: "E", newTab: false) == ["B", "E", "D"])
    // cerrar la activa pasa a la vecina; cerrar otra no cambia la activa
    let c1 = TabLogic.close(["B", "C", "D"], active: "C", path: "C")
    #expect(c1.tabs == ["B", "D"] && c1.active == "D")
    let c2 = TabLogic.close(["B", "C", "D"], active: "D", path: "D")
    #expect(c2.tabs == ["B", "C"] && c2.active == "C")
    let c3 = TabLogic.close(["B", "C", "D"], active: "D", path: "B")
    #expect(c3.tabs == ["C", "D"] && c3.active == "D")
    let c4 = TabLogic.close(["B"], active: "B", path: "B")
    #expect(c4.tabs.isEmpty && c4.active == nil)
    #expect(TabLogic.close(["B"], active: "B", path: "Z").tabs == ["B"])
    // cambiar de pestaña da la vuelta
    #expect(TabLogic.cycle(["B", "C", "D"], active: "D", by: 1) == "B")
    #expect(TabLogic.cycle(["B", "C", "D"], active: "B", by: -1) == "D")
    #expect(TabLogic.cycle(["B"], active: "B", by: 1) == "B")
}
