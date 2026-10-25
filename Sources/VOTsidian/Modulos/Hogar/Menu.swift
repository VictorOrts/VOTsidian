import Foundation

// MARK: - Menú semanal: de los platos de la semana a la lista de la compra

/// Un ingrediente del menú de la semana: en cuántas comidas sale, en qué sección de la lista iría y si ya está en ella.
struct MenuNeed: Equatable, Identifiable {
    var name: String
    var count: Int
    var category: String
    var covered: Bool
    var id: String { WeeklyMenu.key(name) }
}

/// Un plato de la tabla del menú: día, comida (la columna) y lo que se come.
struct MenuDish: Equatable {
    var day: String
    var meal: String
    var dish: String
}

/// La tabla «Menú semanal» de la nota Menú y compra (`| Día | Comida | Cena |`), con platos escritos como
/// «Pollo + patata + pepino, tomate y maíz». Cada plato se parte en ingredientes para completar la lista de la compra.
enum WeeklyMenu {
    static var file: String { VaultPath.beside("plan", "Menú y compra.md") }

    static let template = """
    ---
    tipo: menu
    tags:
      - nutricion
    ---

    # Menú y compra

    > Escribe cada plato con sus ingredientes separados por «+», comas o «y»: «Pollo + patata + ensalada». En Compra,
    > «Completar con el menú» añade a la lista lo que falte.

    ## Menú semanal
    | Día | Comida | Cena |
    | :-- | :----- | :--- |
    | Lunes | | |
    | Martes | | |
    | Miércoles | | |
    | Jueves | | |
    | Viernes | | |
    | Sábado | | |
    | Domingo | | |

    ## Lista de la compra
    - **Básicos:** huevos, leche, pan.

    """

    /// Celdas que no son un plato que comprar.
    private static let notDishes: Set<String> = ["", "-", "—", "–", "libre", "fuera", "comer fuera", "cenar fuera", "restaurante", "sobras"]

    static func dishes(_ text: String) -> [MenuDish] {
        let tables = Parse.tables(text)
        guard let t = tables.first(where: { MD.fold($0.title).contains("menu semanal") }) ?? tables.first(where: { $0.col("dia") == 0 }),
              let dayCol = t.col("dia") else { return [] }
        var out: [MenuDish] = []
        for r in t.rows {
            let day = dayCol < r.cells.count ? r.cells[dayCol] : ""
            for (i, meal) in t.header.enumerated() where i != dayCol && i < r.cells.count {
                let dish = r.cells[i].trimmingCharacters(in: .whitespaces)
                if !notDishes.contains(MD.fold(dish)) { out.append(MenuDish(day: day, meal: meal, dish: dish)) }
            }
        }
        return out
    }

    /// «Pollo + patata + pepino, tomate y maíz» → Pollo, Patata, Pepino, Tomate, Maíz. Las alternativas («pollo o pavo») cuentan
    /// las dos; lo que va con «sin» se descarta, y también las cantidades del principio («200 g de pollo»).
    static func ingredients(of dish: String) -> [String] {
        var t = dish.replacingOccurrences(of: #"\[\[([^\]|]*\|)?([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        let parts = t.components(separatedBy: CharacterSet(charactersIn: "+,;/"))
            .flatMap { $0.replacingOccurrences(of: #"\s+(y|e|o|u|con)\s+"#, with: "|", options: [.regularExpression, .caseInsensitive]).split(separator: "|") }
        var out: [String] = []
        for p in parts {
            var s = p.trimmingCharacters(in: .whitespaces)
            if MD.fold(s).hasPrefix("sin ") { continue }
            s = s.replacingOccurrences(of: #"^[0-9][0-9.,–-]*\s*((g|gr|kg|ml|l|uds?|unidades?|latas?|piezas?)\b\.?)?\s*(de\s+)?"#, with: "",
                                       options: [.regularExpression, .caseInsensitive])
            s = s.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
            guard s.count >= 2, !notDishes.contains(MD.fold(s)) else { continue }
            let cap = s.prefix(1).uppercased() + s.dropFirst()
            if !out.contains(where: { key($0) == key(cap) }) { out.append(cap) }
        }
        return out
    }

    // MARK: Comparar nombres

    private static let stopwords: Set<String> = ["de", "del", "la", "el", "los", "las", "al", "a", "con", "y", "e", "o", "en", "para", "un", "una"]

    /// Palabras de un nombre, sin tildes ni mayúsculas y sin las de enlace («pechuga de pollo» → pechuga, pollo).
    static func words(_ s: String) -> [String] {
        MD.fold(s).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !stopwords.contains($0) }
    }

    /// La misma palabra en singular o plural: tomate/tomates, melocotón/melocotones, nuez/nueces.
    static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (s, l) = a.count < b.count ? (a, b) : (b, a)
        return l == s + "s" || l == s + "es" || (s.hasSuffix("z") && l == s.dropLast() + "ces")
    }

    /// Clave para no repetir un ingrediente escrito en singular y en plural.
    static func key(_ s: String) -> String {
        words(s).map { w in
            if w.hasSuffix("ces") { return String(w.dropLast(3)) + "z" }      // nueces → nuez
            if w.hasSuffix("ones") { return String(w.dropLast(2)) }            // melocotones → melocoton
            return w.hasSuffix("s") && w.count > 3 ? String(w.dropLast()) : w  // patatas, tomates
        }
        .joined(separator: " ")
    }

    /// Si un artículo ya cubre el ingrediente: todas las palabras del ingrediente están en él («Pavo» en «Pechuga de pollo y pavo»).
    static func covers(_ item: String, _ ingredient: String) -> Bool {
        let have = words(item)
        let need = words(ingredient)
        return !need.isEmpty && need.allSatisfy { w in have.contains { same($0, w) } }
    }

    // MARK: Sección de la lista

    /// Pasillos del súper por palabras, para listas organizadas así (las de `Shopping.defaultCategories`).
    private static let aisles: [(String, [String])] = [
        ("Lácteos y huevos", ["huevo", "clara", "leche", "yogur", "yopro", "skyr", "kefir", "queso", "cottage", "nata", "mantequilla", "requeson"]),
        ("Congelados", ["congelado", "helado"]),
        ("Despensa", ["atun", "maiz", "arroz", "pasta", "macarron", "espagueti", "fideo", "pan", "avena", "lenteja", "garbanzo", "alubia", "legumbre",
                      "aceite", "vinagre", "sal", "especia", "harina", "azucar", "cafe", "cacao", "galleta", "cereal", "conserva", "quinoa",
                      "nuez", "almendra", "frutos secos", "tomate frito", "caldo", "tortilla trigo", "creatina", "proteina polvo"]),
        ("Carne y pescado", ["pollo", "pavo", "ternera", "cerdo", "lomo", "jamon", "carne", "salmon", "merluza", "bacalao", "pescado", "gamba",
                             "langostino", "hamburguesa", "salchicha", "chorizo", "sepia", "calamar", "dorada", "lubina", "mejillon"]),
        ("Fruta y verdura", ["patata", "batata", "boniato", "tomate", "pepino", "lechuga", "ensalada", "verdura", "cebolla", "ajo", "zanahoria",
                             "pimiento", "calabacin", "berenjena", "brocoli", "espinaca", "aguacate", "fruta", "melocoton", "sandia", "melon",
                             "arandano", "fresa", "manzana", "platano", "naranja", "limon", "pera", "uva", "kiwi", "champinon", "seta", "judia"]),
        ("Bebidas", ["agua", "refresco", "cerveza", "vino", "zumo"]),
    ]

    static func aisle(_ name: String) -> String? {
        let ws = words(name)
        let f = " " + ws.joined(separator: " ") + " "
        // Palabra entera, en singular o plural: «sal» no es «salmón».
        func has(_ k: String) -> Bool { k.contains(" ") ? f.contains(" " + k + " ") : ws.contains { same($0, k) } }
        return aisles.first { $0.1.contains(where: has) }?.0
    }

    /// Sección donde va un ingrediente nuevo: la del grupo de «Lista de la compra» de la nota (o de la lista) que comparta alguna
    /// palabra con él; si no, el pasillo por palabras, salvo que la lista use sus propias secciones (entonces «Otros»).
    static func category(for name: String, groups: [(category: String, items: [String])], list: [ShoppingItem]) -> String {
        let need = words(name)
        func overlaps(_ text: String) -> Bool { let have = words(text); return need.contains { w in have.contains { same($0, w) } } }
        if let g = groups.first(where: { g in g.items.contains(where: overlaps) }) ?? groups.first(where: { overlaps($0.category) }) { return g.category }
        if let i = list.first(where: { overlaps($0.text) || overlaps($0.category) }) { return i.category }
        let sections = Set(list.map(\.category) + groups.map(\.category))
        let usesAisles = sections.isEmpty || sections.contains { $0 != "Otros" && Shopping.defaultCategories.contains($0) }
        return usesAisles ? aisle(name) ?? "Otros" : "Otros"
    }

    /// Lo que pide el menú de la semana, de lo que más se repite a lo que menos, con si ya está en la lista.
    static func needs(_ menu: String, list: [ShoppingItem]) -> [MenuNeed] {
        let groups = Shopping.fromMenu(menu)
        var order: [String] = []
        var found: [String: (name: String, count: Int)] = [:]
        for d in dishes(menu) {
            for i in ingredients(of: d.dish) {
                let k = key(i)
                if let f = found[k] { found[k] = (f.name, f.count + 1) } else { found[k] = (i, 1); order.append(k) }
            }
        }
        return order.compactMap { found[$0] }.map { f in
            MenuNeed(name: f.name, count: f.count, category: category(for: f.name, groups: groups, list: list),
                     covered: list.contains { covers($0.text, f.name) })
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : MD.fold($0.name) < MD.fold($1.name) }
    }
}
