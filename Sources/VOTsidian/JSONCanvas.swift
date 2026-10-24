import SwiftUI

// Lienzo libre: archivos `.canvas` de Obsidian (formato abierto JSON Canvas 1.0, https://jsoncanvas.org). Tarjetas de texto,
// notas, enlaces y grupos colocados a mano, unidos con flechas. El archivo es la fuente de verdad: cada cambio se lee del disco,
// se transforma con una función pura de `JSONCanvas` y se escribe con `store.edit`, así que se deshace como cualquier otro.
// Los campos que la app no conoce (de Obsidian o de un plugin) se conservan tal cual.

struct CanvasNode: Identifiable, Equatable {
    var id: String
    /// `text`, `file`, `link` o `group`.
    var type: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var text = ""
    var file = ""
    var url = ""
    var label = ""
    /// `"1"`…`"6"` (colores de Obsidian) o `#RRGGBB`. Vacío: sin color.
    var color = ""
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct CanvasEdge: Identifiable, Equatable {
    var id: String
    var fromNode: String
    var toNode: String
    /// `top`, `right`, `bottom` o `left`. Vacío: el lado que mire hacia el otro nodo.
    var fromSide = ""
    var toSide = ""
    var label = ""
    var color = ""
    /// Punta en el origen y en el destino (`arrow` o `none`). Por defecto, como en Obsidian: solo en el destino.
    var fromArrow = false
    var toArrow = true
}

struct CanvasDoc: Equatable {
    var nodes: [CanvasNode] = []
    var edges: [CanvasEdge] = []

    /// Lo que se mueve al arrastrar `id`: el nodo y, si es un grupo, lo que queda dentro de él.
    func moving(_ id: String) -> Set<String> {
        guard let n = nodes.first(where: { $0.id == id }) else { return [] }
        guard n.type == "group" else { return [id] }
        return Set(nodes.filter { $0.id == id || n.frame.contains($0.frame) }.map(\.id))
    }

    /// Rectángulo que abarca todos los nodos (`nil` si no hay ninguno).
    var bounds: CGRect? { nodes.map(\.frame).reduce(nil) { $0?.union($1) ?? $1 } }
}

enum JSONCanvas {
    static let empty = "{\n  \"edges\" : [],\n  \"nodes\" : []\n}\n"
    /// Coordenadas fuera de esto se recortan: un número enorme en el archivo no puede cerrar la app al pasarlo a `Int`.
    static let limit = 10_000_000.0

    // MARK: Leer

    /// `nil` si el texto no es un objeto JSON (archivo roto o a medio sincronizar). Los nodos sin `id` se saltan.
    static func parse(_ text: String) -> CanvasDoc? {
        guard let obj = object(text) else { return nil }
        var doc = CanvasDoc()
        var seen = Set<String>()
        for n in obj["nodes"] as? [[String: Any]] ?? [] {
            // Un `id` repetido (archivo editado a mano) dejaría dos nodos imposibles de distinguir: vale el primero.
            guard let id = n["id"] as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
            doc.nodes.append(CanvasNode(id: id, type: n["type"] as? String ?? "text",
                                        x: number(n["x"]), y: number(n["y"]),
                                        width: max(1, number(n["width"], default: 250)), height: max(1, number(n["height"], default: 60)),
                                        text: n["text"] as? String ?? "", file: n["file"] as? String ?? "", url: n["url"] as? String ?? "",
                                        label: n["label"] as? String ?? "", color: n["color"] as? String ?? ""))
        }
        let ids = Set(doc.nodes.map(\.id))
        for e in obj["edges"] as? [[String: Any]] ?? [] {
            guard let id = e["id"] as? String, let a = e["fromNode"] as? String, let b = e["toNode"] as? String,
                  ids.contains(a), ids.contains(b) else { continue }
            doc.edges.append(CanvasEdge(id: id, fromNode: a, toNode: b, fromSide: e["fromSide"] as? String ?? "", toSide: e["toSide"] as? String ?? "",
                                        label: e["label"] as? String ?? "", color: e["color"] as? String ?? "",
                                        fromArrow: (e["fromEnd"] as? String) == "arrow", toArrow: (e["toEnd"] as? String) != "none"))
        }
        return doc
    }

    // MARK: Cambiar (texto → texto; `nil` si no se encontró qué cambiar)

    /// Mueve varios nodos de una vez (un grupo arrastra lo que tiene dentro): un solo cambio que deshacer.
    static func moveNodes(_ text: String, to positions: [String: CGPoint]) -> String? {
        guard !positions.isEmpty else { return nil }
        return mutate(text) { obj in
            guard var nodes = obj["nodes"] as? [[String: Any]] else { return false }
            var moved = false
            for i in nodes.indices {
                guard let id = nodes[i]["id"] as? String, let p = positions[id] else { continue }
                nodes[i]["x"] = int(p.x); nodes[i]["y"] = int(p.y); moved = true
            }
            obj["nodes"] = nodes
            return moved
        }
    }

    static func resizeNode(_ text: String, id: String, width: Double, height: Double) -> String? {
        mutate(text) { obj in
            updateNode(&obj, id) { $0["width"] = int(max(40, width)); $0["height"] = int(max(30, height)) }
        }
    }

    /// Cambia un campo de texto de un nodo: `text` de una tarjeta, `label` de un grupo.
    static func setField(_ text: String, id: String, key: String, to value: String) -> String? {
        mutate(text) { obj in updateNode(&obj, id) { $0[key] = value } }
    }

    static func setColor(_ text: String, id: String, to color: String) -> String? {
        mutate(text) { obj in
            updateNode(&obj, id) { if color.isEmpty { $0.removeValue(forKey: "color") } else { $0["color"] = color } }
        }
    }

    /// Añade un nodo: `fields` lleva lo propio de su tipo (`text`, `file`, `url` o `label`).
    static func addNode(_ text: String, id: String, type: String, frame: CGRect, fields: [String: String]) -> String? {
        mutate(text) { obj in
            var n: [String: Any] = ["id": id, "type": type, "x": int(frame.minX), "y": int(frame.minY),
                                    "width": int(max(40, frame.width)), "height": int(max(30, frame.height))]
            for (k, v) in fields { n[k] = v }
            var nodes = obj["nodes"] as? [[String: Any]] ?? []
            // Los grupos van delante: en Obsidian lo que está antes se pinta debajo.
            if type == "group" { nodes.insert(n, at: 0) } else { nodes.append(n) }
            obj["nodes"] = nodes
            return true
        }
    }

    /// Une dos nodos con una flecha. No repite una unión que ya existe en ese sentido.
    static func connect(_ text: String, id: String, from a: String, to b: String) -> String? {
        guard a != b else { return nil }
        return mutate(text) { obj in
            let nodes = obj["nodes"] as? [[String: Any]] ?? []
            guard nodes.contains(where: { $0["id"] as? String == a }), nodes.contains(where: { $0["id"] as? String == b }) else { return false }
            var edges = obj["edges"] as? [[String: Any]] ?? []
            if edges.contains(where: { $0["fromNode"] as? String == a && $0["toNode"] as? String == b }) { return false }
            edges.append(["id": id, "fromNode": a, "toNode": b])
            obj["edges"] = edges
            return true
        }
    }

    /// Quita nodos y uniones por `id`. Las uniones de un nodo quitado se van con él.
    static func remove(_ text: String, ids: Set<String>) -> String? {
        guard !ids.isEmpty else { return nil }
        return mutate(text) { obj in
            let nodes = obj["nodes"] as? [[String: Any]] ?? []
            let edges = obj["edges"] as? [[String: Any]] ?? []
            let keptNodes = nodes.filter { !ids.contains($0["id"] as? String ?? "") }
            let keptEdges = edges.filter { e in
                ![e["id"], e["fromNode"], e["toNode"]].contains { ids.contains($0 as? String ?? "") }
            }
            guard keptNodes.count != nodes.count || keptEdges.count != edges.count else { return false }
            obj["nodes"] = keptNodes
            obj["edges"] = keptEdges
            return true
        }
    }

    // MARK: Geometría

    /// Identificador nuevo: 16 cifras hexadecimales, como los de Obsidian.
    static func newID() -> String { (0..<16).map { _ in String("0123456789abcdef".randomElement()!) }.joined() }

    /// Lados por los que sale y entra una unión. Si el archivo no los dice, el que mira hacia el otro nodo.
    static func sides(_ e: CanvasEdge, from a: CGRect, to b: CGRect) -> (String, String) {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        let auto = abs(dx) > abs(dy) ? (dx > 0 ? ("right", "left") : ("left", "right")) : (dy > 0 ? ("bottom", "top") : ("top", "bottom"))
        return (e.fromSide.isEmpty ? auto.0 : e.fromSide, e.toSide.isEmpty ? auto.1 : e.toSide)
    }

    static func anchor(_ r: CGRect, side: String) -> CGPoint {
        switch side {
        case "top": CGPoint(x: r.midX, y: r.minY)
        case "bottom": CGPoint(x: r.midX, y: r.maxY)
        case "left": CGPoint(x: r.minX, y: r.midY)
        default: CGPoint(x: r.maxX, y: r.midY)
        }
    }

    static func normal(_ side: String) -> CGVector {
        switch side {
        case "top": CGVector(dx: 0, dy: -1)
        case "bottom": CGVector(dx: 0, dy: 1)
        case "left": CGVector(dx: -1, dy: 0)
        default: CGVector(dx: 1, dy: 0)
        }
    }

    /// Color de Obsidian: `"1"` rojo … `"6"` morado, o un `#RRGGBB`.
    static func color(_ s: String) -> Color? {
        switch s {
        case "1": return Brand.bad
        case "2": return Brand.warn
        case "3": return Brand.amber
        case "4": return Brand.accent
        case "5": return Brand.sky
        case "6": return Brand.violet
        default:
            guard s.hasPrefix("#"), s.count == 7, let v = Int(s.dropFirst(), radix: 16) else { return nil }
            return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
        }
    }

    // MARK: Interno

    private static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }   // archivo recién creado vacío
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func mutate(_ text: String, _ change: (inout [String: Any]) -> Bool) -> String? {
        guard var obj = object(text), change(&obj) else { return nil }
        if obj["nodes"] == nil { obj["nodes"] = [[String: Any]]() }
        if obj["edges"] == nil { obj["edges"] = [[String: Any]]() }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let out = String(data: data, encoding: .utf8) else { return nil }
        return out + "\n"
    }

    private static func updateNode(_ obj: inout [String: Any], _ id: String, _ change: (inout [String: Any]) -> Void) -> Bool {
        guard var nodes = obj["nodes"] as? [[String: Any]], let i = nodes.firstIndex(where: { $0["id"] as? String == id }) else { return false }
        change(&nodes[i])
        obj["nodes"] = nodes
        return true
    }

    private static func number(_ v: Any?, default d: Double = 0) -> Double {
        guard let n = (v as? NSNumber)?.doubleValue, n.isFinite else { return d }
        return min(max(n, -limit), limit)
    }

    private static func int(_ v: Double) -> Int { v.isFinite ? Int(min(max(v, -limit), limit).rounded()) : 0 }
}

extension Store {
    /// Lienzos de la carpeta de notas, del más reciente al más antiguo. Sin `.obsidian`, papelera ni carpetas ocultas.
    func canvasFiles() -> [String] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [(String, Date)] = []
        let base = root.standardizedFileURL.path
        for case let u as URL in e where u.pathExtension == "canvas" {
            let path = u.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let rel = String(path.dropFirst(base.count + 1))
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            found.append((rel, date))
        }
        return found.sorted { ($0.1, $1.0) > ($1.1, $0.0) }.map(\.0)
    }

    /// Crea un lienzo vacío sin pisar ninguno: «Lienzos/Sin título.canvas», «… 2.canvas»… Devuelve su ruta.
    func createCanvas(named name: String = "Sin título") -> String? {
        let clean = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let stem = clean.isEmpty ? "Sin título" : clean
        var rel = "Lienzos/\(stem).canvas", n = 2
        while exists(rel) { rel = "Lienzos/\(stem) \(n).canvas"; n += 1 }
        do {
            try FileManager.default.createDirectory(at: url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONCanvas.empty.write(to: url(rel), atomically: true, encoding: .utf8)
        } catch {
            Log.notes.error("No se pudo crear el lienzo: \(error.localizedDescription, privacy: .public)")
            message = "No se pudo crear el lienzo: \(error.localizedDescription)"; return nil
        }
        reload(changed: [rel])
        return rel
    }
}
