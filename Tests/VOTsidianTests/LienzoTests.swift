import Testing
import Foundation
@testable import VOTsidian

@Test func canvasParsesObsidianFile() throws {
    let doc = try #require(JSONCanvas.parse(canvasFixture))
    #expect(doc.nodes.map(\.id) == ["g1", "t1", "t2", "f1", "l1"])
    #expect(doc.nodes[0].label == "Mudanza" && doc.nodes[0].color == "4")
    #expect(doc.nodes[3].file == "Notas/A.md" && doc.nodes[4].url == "https://www.obsidian.md")
    // La flecha a un nodo que no existe se ignora; las demás conservan lados y texto.
    #expect(doc.edges.map(\.id) == ["e1", "e2"])
    #expect(doc.edges[0].fromSide == "right" && doc.edges[0].label == "luego" && doc.edges[0].toArrow && !doc.edges[0].fromArrow)
    #expect(doc.bounds == CGRect(x: -40, y: -80, width: 760, height: 550))
    // Mover el grupo arrastra lo que tiene dentro, no lo de fuera.
    #expect(doc.moving("g1") == ["g1", "t1", "t2"])
    #expect(doc.moving("t1") == ["t1"])
}

@Test func canvasRejectsBrokenAndOddInput() {
    #expect(JSONCanvas.parse("no es json") == nil)
    #expect(JSONCanvas.parse("[1, 2]") == nil)
    #expect(JSONCanvas.parse("")?.nodes.isEmpty == true)
    #expect(JSONCanvas.parse(#"{"nodes":[{"id":"a","x":1e999}]}"#) == nil)   // JSON que no se puede leer: no se toca
    // Números absurdos se recortan; ids repetidos: vale el primero.
    let odd = #"{"nodes":[{"id":"a","x":1e300,"y":"x","width":-5},{"id":"a","x":3},{"x":1}]}"#
    let doc = JSONCanvas.parse(odd)
    #expect(doc?.nodes.count == 1)
    #expect(doc?.nodes.first?.x == JSONCanvas.limit && doc?.nodes.first?.y == 0 && doc?.nodes.first?.width == 1)
    #expect(JSONCanvas.moveNodes(odd, to: ["a": CGPoint(x: 1e300, y: .nan)]) != nil)
}

@Test func canvasEditsKeepUnknownFields() throws {
    var t = try #require(JSONCanvas.moveNodes(canvasFixture, to: ["t1": CGPoint(x: 10.4, y: -20.6), "zz": .zero]))
    var doc = try #require(JSONCanvas.parse(t))
    #expect(doc.nodes.first { $0.id == "t1" }?.frame.origin == CGPoint(x: 10, y: -21))
    #expect(t.contains("\"extra\" : \"se conserva\""))
    #expect(JSONCanvas.moveNodes(canvasFixture, to: ["zz": .zero]) == nil)

    t = try #require(JSONCanvas.addNode(t, id: "n1", type: "text", frame: CGRect(x: 5, y: 5, width: 10, height: 10), fields: ["text": "hola"]))
    t = try #require(JSONCanvas.addNode(t, id: "g2", type: "group", frame: CGRect(x: 0, y: 0, width: 500, height: 500), fields: ["label": "G"]))
    doc = try #require(JSONCanvas.parse(t))
    #expect(doc.nodes.first?.id == "g2")                       // los grupos, debajo
    #expect(doc.nodes.last.map { ($0.id, $0.text, $0.width) } ?? ("", "", 0) == ("n1", "hola", 40))   // tamaño mínimo

    t = try #require(JSONCanvas.setField(t, id: "n1", key: "text", to: "adiós"))
    t = try #require(JSONCanvas.setColor(t, id: "n1", to: "5"))
    t = try #require(JSONCanvas.connect(t, id: "e9", from: "n1", to: "t2"))
    #expect(JSONCanvas.connect(t, id: "e10", from: "n1", to: "t2") == nil)   // no se repite
    #expect(JSONCanvas.connect(t, id: "e11", from: "n1", to: "n1") == nil)
    doc = try #require(JSONCanvas.parse(t))
    #expect(doc.nodes.last?.text == "adiós" && doc.nodes.last?.color == "5")
    #expect(doc.edges.contains { $0.id == "e9" })

    t = try #require(JSONCanvas.setColor(t, id: "n1", to: ""))
    t = try #require(JSONCanvas.remove(t, ids: ["n1"]))
    doc = try #require(JSONCanvas.parse(t))
    #expect(!doc.nodes.contains { $0.id == "n1" } && !doc.edges.contains { $0.id == "e9" })   // su flecha se va con él
    #expect(JSONCanvas.remove(t, ids: ["nada"]) == nil)
}

@Test func canvasEdgeSidesAndColors() {
    let e = CanvasEdge(id: "e", fromNode: "a", toNode: "b")
    let a = CGRect(x: 0, y: 0, width: 100, height: 50)
    #expect(JSONCanvas.sides(e, from: a, to: CGRect(x: 300, y: 10, width: 100, height: 50)) == ("right", "left"))
    #expect(JSONCanvas.sides(e, from: a, to: CGRect(x: 0, y: -300, width: 100, height: 50)) == ("top", "bottom"))
    #expect(JSONCanvas.anchor(a, side: "bottom") == CGPoint(x: 50, y: 50))
    #expect(JSONCanvas.color("4") != nil && JSONCanvas.color("#ff8800") != nil && JSONCanvas.color("#zz") == nil && JSONCanvas.color("") == nil)
    #expect(JSONCanvas.newID().count == 16)
}

@MainActor @Test func canvasFilesEditAndUndo() throws {
    let store = Store(root: try syntheticVault())
    store.reload()
    #expect(store.canvasFiles() == ["Lienzos/Mudanza.canvas"])
    let rel = try #require(store.createCanvas(named: "Ideas"))
    #expect(rel == "Lienzos/Ideas.canvas" && store.createCanvas(named: "Ideas") == "Lienzos/Ideas 2.canvas")
    #expect(JSONCanvas.parse(store.read(rel))?.nodes.isEmpty == true)

    let before = store.canvasStamp
    let tasks = store.tasks.count
    #expect(store.edit(rel) { JSONCanvas.addNode($0, id: "x", type: "text", frame: .init(x: 0, y: 0, width: 200, height: 80), fields: ["text": "- [ ] no es tarea"]) })
    #expect(store.canvasStamp > before)
    #expect(store.tasks.count == tasks)              // un lienzo no aporta tareas
    #expect(JSONCanvas.parse(store.readOptional(rel) ?? "")?.nodes.count == 1)
    store.undo()
    #expect(JSONCanvas.parse(store.readOptional(rel) ?? "")?.nodes.isEmpty == true)
}
