import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

// MARK: - Bases: calendario y tablero

private let meta: [String: [String: String]] = [
    "P/A.md": ["tipo": "proyecto", "estado": "En curso", "fecha_limite": "2026-11-05", "prioridad": "alta", "coste": "300"],
    "P/B.md": ["tipo": "proyecto", "estado": "en curso", "fecha_limite": "12/11/2026", "prioridad": "media", "coste": "120"],
    "P/C.md": ["tipo": "proyecto", "estado": "Idea", "fecha_limite": "", "prioridad": "alta", "coste": "50"],
    "P/D.md": ["tipo": "proyecto", "estado": "Hecho", "fecha_limite": "2026-10-01", "prioridad": "baja"],
    "P/E.md": ["tipo": "proyecto", "fecha_limite": "sin fecha"],
]
private let paths = meta.keys.sorted()

@Test func basesSuggestDateAndGroupProperties() {
    #expect(BaseQuery.dateKeys(paths: paths, meta: meta) == ["fecha_limite"])          // 3 de 4 con valor son fechas
    let groups = BaseQuery.groupKeys(paths: paths, meta: meta)
    #expect(groups.first == "estado" && groups.contains("prioridad") && !groups.contains("coste") && !groups.contains("fecha_limite"))
    #expect(BaseQuery.dateKeys(paths: [], meta: [:]).isEmpty && BaseQuery.groupKeys(paths: ["x"], meta: ["x": ["estado": "único"]]).isEmpty)
}

@Test func basesGroupByDayAndColumns() {
    let (days, undated) = BaseQuery.byDay(paths: paths, meta: meta, key: "fecha_limite")
    #expect(days["2026-11-05"] == ["P/A.md"] && days["2026-11-12"] == ["P/B.md"] && days["2026-10-01"] == ["P/D.md"])
    #expect(undated == ["P/C.md", "P/E.md"])
    let cols = BaseQuery.columns(paths: paths, meta: meta, key: "estado")
    // orden natural de los estados, la forma más usada de cada valor y «sin valor» al final
    #expect(cols.map(\.value) == ["Idea", "En curso", "Hecho", ""] || cols.map(\.value) == ["Idea", "en curso", "Hecho", ""])
    #expect(cols[1].paths.sorted() == ["P/A.md", "P/B.md"] && cols.last?.paths == ["P/E.md"])
    #expect(BaseQuery.columns(paths: paths, meta: meta, key: "prioridad").map(\.value) == ["alta", "media", "baja", ""])
}

@Test func movedDatesKeepTheirFormat() throws {
    let day = try #require(DayKey.date("2026-11-20"))
    #expect(BaseQuery.format(day, like: "12/11/2026") == "20/11/2026")
    #expect(BaseQuery.format(day, like: "2026-11-05") == "2026-11-20" && BaseQuery.format(day, like: nil) == "2026-11-20" && BaseQuery.format(day, like: "") == "2026-11-20")
}

@Test func savedViewsFromBeforeStillOpen() throws {
    let old = #"[{"name":"Pendientes","text":"","sortKey":"Nota","ascending":true,"conditions":[]}]"#
    let views = try JSONDecoder().decode([BaseView].self, from: Data(old.utf8))
    #expect(views.first?.name == "Pendientes" && views.first?.layout == .tabla && views.first?.dateKey == "")
    var v = BaseView(name: "Calendario")
    v.layout = .calendario; v.dateKey = "fecha"
    let back = try JSONDecoder().decode(BaseView.self, from: JSONEncoder().encode(v))
    #expect(back == v)
}

@MainActor @Test func draggingANoteChangesItsPropertyAndRendersEveryLayout() throws {
    let root = try syntheticVault()
    for (name, body) in [("Reforma baño", "---\ntipo: proyecto\nestado: Idea\nfecha_limite: 12/11/2026\n---\n# Reforma\n"),
                         ("Web", "---\ntipo: proyecto\nestado: En curso\nfecha_limite: 2026-11-30\n---\n# Web\n")] {
        let u = root.appendingPathComponent("Proyectos/\(name).md")
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: u, atomically: true, encoding: .utf8)
    }
    let store = Store(root: root)
    UserDefaults.standard.set("proyecto", forKey: "basesType")
    defer { UserDefaults.standard.removeObject(forKey: "basesType") }
    // lo que hace soltar una nota en un día y en una columna
    let path = "Proyectos/Reforma baño.md"
    let day = try #require(DayKey.date("2026-11-20"))
    store.setProperty(path, key: "fecha_limite", value: BaseQuery.format(day, like: store.noteMeta[path]?["fecha_limite"]))
    store.setProperty(path, key: "estado", value: "En curso")
    #expect(store.noteMeta[path]?["fecha_limite"] == "20/11/2026" && store.noteMeta[path]?["estado"] == "En curso")
    store.undo()
    #expect(store.noteMeta[path]?["estado"] == "Idea")
    for layout in BaseView.Layout.allCases {
        let r = ImageRenderer(content: BasesView(layout: layout).environment(store).frame(width: 1100, height: 900))
        r.scale = 1
        #expect(r.cgImage != nil, "\(layout.rawValue) no se pudo pintar")
    }
}
