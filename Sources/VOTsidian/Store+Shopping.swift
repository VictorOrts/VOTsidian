import Foundation

// MARK: - Lista de la compra y órdenes rápidas

extension Store {
    var shoppingItems: [ShoppingItem] { Shopping.parse(noteTexts[Shopping.file] ?? "") }
    var shoppingExists: Bool { FileManager.default.fileExists(atPath: url(Shopping.file).path) }

    func ensureShoppingList() {
        if !shoppingExists { writeNote(Shopping.file, text: Shopping.template) }
    }

    @discardableResult
    func addShopping(_ items: [String], category: String = "Otros") -> Int {
        ensureShoppingList()
        var added = 0
        edit(Shopping.file) { text in
            let r = Shopping.addItems(text, items: items, category: category)
            added = r.added
            return r.added > 0 ? r.text : nil
        }
        return added
    }

    func toggleShopping(_ item: ShoppingItem) { edit(Shopping.file) { Edit.toggleCheckbox($0, line: item.line, expect: item.raw, completion: false) } }
    func deleteShopping(_ item: ShoppingItem) { edit(Shopping.file) { Edit.deleteLine($0, raw: item.raw, hint: item.line) } }
    func clearBought() { edit(Shopping.file) { Shopping.clearDone($0) } }
    func uncheckShopping() { edit(Shopping.file) { Shopping.uncheckAll($0) } }

    /// Añade a la lista lo que falte de la sección «Lista de la compra» de Menú y compra. Devuelve cuántos artículos añadió.
    func generateShoppingFromMenu() -> Int {
        let groups = Shopping.fromMenu(read("Cambio físico/Menú y compra.md"))
        guard !groups.isEmpty else { return 0 }
        ensureShoppingList()
        var total = 0
        for g in groups { total += addShopping(g.items, category: g.category) }
        return total
    }

    /// Ejecuta una orden rápida y devuelve el mensaje de confirmación.
    @discardableResult
    func run(_ c: QuickCommand) -> String {
        switch c {
        case .weight(let kg, let d): addWeight(date: d, kg: kg, note: "")
        case .mood(let n, let d): setDiaryValue(d, "animo", Double(n))
        case .sleep(let h, let d): setDiaryValue(d, "sueno_h", h)
        case .injection(let d): addDose(date: d, dose: mounjaro.last?.mg ?? 7.5, site: mounjaro.suggestedSite, note: "")
        case .task(let t, let d, let r, let p): addTask(t, due: d, recurrence: r, priority: p)
        case .idea(let t): addIdea(t)
        case .diary(let t): appendToDiary(DayKey.today(), text: t)
        case .appointment(let t, let d):
            edit(VaultPath.medico) { Edit.appendToSection($0, section: "Próximas citas", line: "- [ ] \(t) 📅 \(DayKey.string(d))") }
        case .measure(let field, let v, let d):
            let (table, _) = Measures.parse(read(Measures.file))
            guard let t = table, let col = t.col(field) else { return "Activa primero las medidas en Peso." }
            var cells = [String](repeating: "", count: t.header.count)
            cells[0] = DayKey.dmy(d); cells[col] = MD.formatNumber(v)
            insertRow(file: Measures.file, afterLine: t.lastLine, cells: cells)
        case .shopping(let items):
            let n = addShopping(items)
            return n == 0 ? "Ya estaba en la lista de la compra." : "Añadido a la lista de la compra (\(n))."
        }
        return c.summary
    }
}
