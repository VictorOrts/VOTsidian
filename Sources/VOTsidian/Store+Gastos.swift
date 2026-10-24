import Foundation

// MARK: - Store

extension Store {
    static var gastosFolder: String { VaultPath.gastos }
    func budgetPath(_ month: String) -> String { "\(Store.gastosFolder)/\(month).md" }

    /// Meses con nota de presupuesto, del más viejo al más nuevo.
    var budgetMonths: [String] {
        let prefix = Store.gastosFolder + "/"
        return notes.compactMap { n in
            guard n.path.hasPrefix(prefix), n.name.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            return n.name
        }.sorted()
    }

    /// Se analiza una vez por recarga: la pantalla de Gastos y los avisos lo piden muchas veces en cada pintado.
    func budget(_ month: String) -> Budget? {
        let p = budgetPath(month)
        touch(p)   // aunque la caché acierte: quien pinta este mes depende de su nota
        if let b = budgetCache[p] { return b }
        guard let t = noteTexts[p] else { return nil }
        let b = Parse.budget(t, month: month, path: p)
        budgetCache[p] = b
        return b
    }

    /// El mes con nota más cercano a `month` (a igual distancia, el siguiente): para no dejar en blanco Inicio,
    /// Finanzas o Gastos cuando el mes actual no tiene nota pero, por ejemplo, el que viene ya está preparado.
    func nearestBudgetMonth(to month: String) -> String? {
        guard let m = BudgetLine.monthIndex(month) else { return nil }
        return budgetMonths.filter { $0 != month }.min { a, b in
            let da = abs((BudgetLine.monthIndex(a) ?? 0) - m), db = abs((BudgetLine.monthIndex(b) ?? 0) - m)
            return da != db ? da < db : a > b
        }
    }

    /// Los `limit` meses con nota anteriores a `month`, del más reciente al más viejo.
    func budgets(before month: String, limit: Int = 3) -> [Budget] {
        budgetMonths.filter { $0 < month }.reversed().prefix(limit).compactMap { budget($0) }
    }

    /// Crea la nota del mes copiando la estructura del último mes que haya.
    @discardableResult
    func createBudget(_ month: String) -> Bool {
        guard budget(month) == nil else { return true }
        // La nota puede existir aunque la app aún no la haya leído (recién llegada de iCloud o sin descargar): no se pisa.
        let u = url(budgetPath(month))
        let placeholder = u.deletingLastPathComponent().appendingPathComponent(".\(u.lastPathComponent).icloud")
        if FileManager.default.fileExists(atPath: u.path) || FileManager.default.fileExists(atPath: placeholder.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: u)
            reload()
            if budget(month) != nil { return true }
            message = "La nota \(budgetPath(month)) ya existe pero aún no se puede leer (¿la está descargando iCloud?). No se creó otra."
            return false
        }
        let previous = budgetMonths.last { $0 < month }.flatMap { budget($0) } ?? budgetMonths.last.flatMap { budget($0) }
        return writeNote(budgetPath(month), text: Edit.budgetNote(month: month, from: previous))
    }

    func addExpense(_ amount: Double, category: String, note: String, date: Date) {
        let month = Budget.monthKey(date)
        // Si hay que crear la nota del mes, crearla y apuntar se deshacen juntos: deshacer el gasto no deja una nota vacía.
        grouped {
            guard createBudget(month) else { return }
            edit(budgetPath(month)) { Edit.addBudgetMove($0, date: date, amount: amount, category: category, note: note) }
        }
    }

    func setBudgetCell(_ b: Budget, section: String, line: Int, name: String, column: String, value: String) {
        edit(b.path) { Edit.setSectionCell(Edit.normalizeBudgetTable($0, section: section), section: section, line: line, expectFirst: name, column: column, value: value) }
    }

    /// Cambia cada cuántos meses se paga una partida y desde qué mes. Afecta a este mes y a los que se creen después.
    func setBudgetFrequency(_ b: Budget, _ l: BudgetLine, every: Int, start: String?) {
        edit(b.path) { text in
            var t = Edit.normalizeBudgetTable(text, section: "Partidas")
            for (column, value) in [("Cada", every > 1 ? String(every) : ""), ("Desde", every > 1 ? start ?? b.month : "")] {
                guard let next = Edit.setSectionCell(t, section: "Partidas", line: l.line, expectFirst: l.name, column: column, value: value) else { return nil }
                t = next
            }
            return t
        }
    }

    func addBudgetLine(_ b: Budget, name: String, amount: Double, kind: BudgetLine.Kind, every: Int, start: String?) {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        guard b.line(named: clean) == nil else { message = "Ya hay una partida llamada «\(clean)»."; return }
        edit(b.path) { Edit.addBudgetLine($0, name: clean, amount: amount, kind: kind, every: every, start: start) }
    }

    func renameBudgetLine(_ b: Budget, _ l: BudgetLine, to name: String) {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != l.name else { return }
        guard b.line(named: clean) == nil || MD.fold(clean) == MD.fold(l.name) else { message = "Ya hay una partida llamada «\(clean)»."; return }
        guard edit(b.path, { Edit.renameBudgetLine($0, line: l.line, from: l.name, to: clean) }) else { return }
        // Lo aprendido apuntaba al nombre viejo: sin esto, «dentista» dejaría de ir a su partida tras renombrarla.
        expenseLearned = expenseLearned.mapValues { MD.fold($0) == MD.fold(l.name) ? clean : $0 }
    }

    func addBudgetIncome(_ b: Budget, name: String) {
        let clean = name.replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        guard !b.incomes.contains(where: { MD.fold($0.name) == MD.fold(clean) }) else { message = "Ya hay un ingreso llamado «\(clean)»."; return }
        edit(b.path) { Edit.addBudgetIncome($0, name: clean) }
    }

    func removeBudgetIncome(_ b: Budget, _ i: BudgetIncome) {
        edit(b.path) { Edit.deleteRow($0, line: i.line, expectFirst: i.name) }
    }

    /// Quita la partida de este mes. Sus movimientos se quedan en la nota y siguen contando como gasto.
    func removeBudgetLine(_ b: Budget, _ l: BudgetLine) {
        edit(b.path) { Edit.deleteRow($0, line: l.line, expectFirst: l.name) }
    }

    func deleteExpense(_ b: Budget, _ m: BudgetMove) {
        // La fila se borra solo si sigue siendo ese gasto (misma fecha e importe): si la nota cambió, no se toca otra.
        edit(b.path) { text in
            guard let now = Parse.budget(text, month: b.month, path: b.path).moves.first(where: { $0.line == m.line }),
                  now.date == m.date, now.amount == m.amount else { return nil }
            return Edit.deleteRow(text, line: m.line, expectFirst: MD.cells(MD.lines(text)[m.line]).first ?? "")
        }
    }

    /// Corrige un gasto apuntado. Si la fecha nueva es de otro mes, el gasto se pasa a la nota de ese mes (se deshace de una vez).
    func updateExpense(_ b: Budget, _ m: BudgetMove, date: Date, amount: Double, note: String) {
        let clean = note.trimmingCharacters(in: .whitespaces)
        guard date != m.date || amount != m.amount || clean != m.note else { return }
        if Budget.monthKey(date) == b.month {
            edit(b.path) { Edit.updateBudgetMove($0, month: b.month, move: m, date: date, amount: amount, note: clean) }
            return
        }
        grouped {
            guard createBudget(Budget.monthKey(date)) else { return }
            let before = noteTexts[b.path]
            deleteExpense(b, m)
            // Solo se apunta en el otro mes si de verdad se quitó de este: si no, quedaría duplicado.
            guard noteTexts[b.path] != before else { return }
            addExpense(amount, category: m.category, note: clean, date: date)
        }
    }

    /// Partidas para adivinar un gasto: las del mes en curso, o las del último mes con nota, o las de la hoja de Numbers.
    var expenseCategories: [String] {
        (budget(Budget.monthKey(DayKey.today())) ?? budgetMonths.last.flatMap { budget($0) })?.lines.map(\.name) ?? Edit.defaultBudgetLines.map(\.0)
    }

    /// Palabra → partida, aprendido de las veces que corriges la partida que se adivinó.
    var expenseLearned: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "expenseLearned") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "expenseLearned") }
    }

    func learnExpense(note: String, category: String) {
        let words = ExpenseParser.learnable(note, categories: expenseCategories)
        guard !words.isEmpty else { return }
        var l = expenseLearned
        for w in words { l[w] = category }
        expenseLearned = l
    }

    func parseExpense(_ text: String) -> ExpenseParser.Result? {
        ExpenseParser.parse(text, categories: expenseCategories, people: people.map(\.name), learned: expenseLearned)
    }

    /// Apunta un gasto escrito como frase (⌘K, captura rápida). Sin partida reconocible va a la de imprevistos.
    @discardableResult
    func addExpense(_ p: ExpenseParser.Result) -> String {
        let cats = expenseCategories
        guard let c = p.category ?? cats.first(where: { MD.fold($0).contains("imprevist") }) ?? cats.last else { return "No hay partidas donde apuntarlo." }
        addExpense(p.amount, category: c, note: p.note, date: p.date)
        return (p.amount < 0 ? "Devolución apuntada: \(Money.exact(-p.amount))" : "Apuntado: \(Money.exact(p.amount))") + " en \(c)" + (Budget.monthKey(p.date) != Budget.monthKey(DayKey.today()) ? " (\(Budget.title(Budget.monthKey(p.date)).lowercased()))" : "")
    }

    /// Cambia la partida de un gasto ya apuntado y aprende de la corrección.
    func setExpenseCategory(_ b: Budget, _ m: BudgetMove, to category: String) {
        guard MD.fold(category) != m.key else { return }
        edit(b.path) { text in
            let lines = MD.lines(text)
            guard m.line < lines.count, let first = MD.cells(lines[m.line]).first else { return nil }
            return Edit.setSectionCell(text, section: "Movimientos", line: m.line, expectFirst: first, column: "Partida", value: category)
        }
        learnExpense(note: m.note, category: category)
    }

    /// Pasa el sobrante de un mes al fondo: un movimiento en la partida de ahorro (el último día del mes) y la suma en
    /// `fondo_emergencia_eur` de la nota Finanzas. Así el mes queda cuadrado y el fondo, al día.
    func transferLeftover(_ b: Budget, amount: Double) {
        guard amount > 0, let saving = b.lines.first(where: { $0.kind == .ahorro }), let first = Budget.firstDay(b.month),
              let last = DayKey.calendar().date(byAdding: DateComponents(month: 1, day: -1), to: first) else { return }
        // Los dos cambios se deshacen juntos; si el movimiento no se pudo apuntar, el fondo no se toca.
        grouped {
            guard edit(b.path, { Edit.addBudgetMove($0, date: last, amount: amount, category: saving.name, note: "sobrante del mes") }) else { return }
            guard FileManager.default.fileExists(atPath: url(VaultPath.finanzas).path) else {
                message = "El sobrante se apuntó en \(saving.name), pero no existe \(VaultPath.finanzas) para sumarlo al fondo. Pon lo que tienes en la tarjeta del fondo."
                return
            }
            edit(VaultPath.finanzas) { t in
                let key = "fondo_emergencia_eur"
                let value = Edit.budgetNumber(Money.parse(MD.frontmatter(t)[key] ?? "") + amount)
                // Sin propiedades en la nota, se crean.
                return Edit.setFrontmatter(t, key: key, value: value) ?? "---\n\(key): \(value)\n---\n" + t
            }
        }
    }

    /// Da por pagada la aportación de un evento: la apunta como gasto (con enlace al evento, en la partida que se
    /// adivine por su nombre o en imprevistos) y pone el evento en «pagado». Se deshace de una vez.
    func payContribution(path: String, amount: Double, date: Date = DayKey.today()) {
        guard amount > 0 else { return }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let cats = expenseCategories
        let category = ExpenseParser.parse("\(Edit.budgetNumber(amount)) \(name)", categories: cats, learned: expenseLearned)?.category
            ?? cats.first { MD.fold($0).contains("imprevist") } ?? cats.last
        guard let category else { message = "No hay partidas donde apuntarlo."; return }
        let month = Budget.monthKey(date)
        grouped {
            let before = budget(month)?.moves.count ?? 0
            addExpense(amount, category: category, note: "aportación [[\(name)]]", date: date)
            // Solo se marca pagado si el gasto quedó apuntado.
            guard (budget(month)?.moves.count ?? 0) > before else { return }
            setProperty(path, key: "estado", value: "pagado")
        }
    }

    /// Eventos de Finanzas con aportación sin pagar.
    var pendingContributions: [(name: String, amount: Double, path: String)] {
        noteMeta.compactMap { path, m in
            guard m["tipo"] == "evento", m["estado"] != "pagado", m["estado"] != "cancelado" else { return nil }
            let v = Money.parse(m["aportacion_eur"] ?? "")
            return v > 0 ? (((path as NSString).lastPathComponent as NSString).deletingPathExtension, v, path) : nil
        }.sorted { $0.name < $1.name }
    }
}

extension Store {
    /// Apunta en Gastos un importe que viene de otro módulo (cuota, renovación, repostaje…). La partida es la pedida si existe;
    /// si no, la que adivina Gastos para la nota, luego la primera que contenga alguna de `fallback` y por último imprevistos.
    /// Devuelve la partida usada, o `nil` si no hay dónde apuntarlo.
    @discardableResult
    func addLinkedExpense(_ amount: Double, note: String, date: Date, category: String? = nil, fallback: [String] = []) -> String? {
        let cats = expenseCategories
        func named(_ s: String) -> String? {
            let key = MD.fold(s)
            guard !key.isEmpty else { return nil }
            return cats.first { MD.fold($0) == key } ?? cats.first { MD.fold($0).contains(key) }
        }
        let guess = ExpenseParser.parse("\(MD.formatNumber(amount, comma: true)) \(note)", categories: cats, learned: expenseLearned)?.category
        guard let c = category.flatMap(named) ?? guess ?? fallback.lazy.compactMap(named).first ?? named("imprevist") ?? cats.last else { return nil }
        addExpense(amount, category: c, note: note, date: date)
        return c
    }
}
