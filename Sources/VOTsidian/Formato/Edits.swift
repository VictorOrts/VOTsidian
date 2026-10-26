import Foundation

/// Transformaciones puras de texto Markdown. Cada una devuelve nil si no puede aplicarse.
enum Edit {
    /// Inserta `row` justo después de la última fila de tabla que cumple `match`.
    static func insertRow(_ text: String, row: String, after match: ([String]) -> Bool) -> String? {
        var lines = MD.lines(text)
        let rows = MD.tableRows(lines)
        // Sin ninguna fila aún (nota recién creada), va justo debajo de la cabecera de la primera tabla.
        let separator = rows.first { r in !r.cells.isEmpty && r.cells.allSatisfy { $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil } }
        guard let last = rows.last(where: { match($0.cells) }) ?? separator else { return nil }
        lines.insertClamped(row, at: last.index + 1)
        return lines.joined(separator: "\n")
    }

    static func addWeight(_ text: String, date: Date, kg: Double, note: String) -> String? {
        let key = DayKey.dmy(date)
        let row = rowString([key, MD.formatNumber(kg), note])
        var lines = MD.lines(text)
        if let same = MD.tableRows(lines).first(where: { DayKey.dmyDate($0.cells[0]).map(DayKey.dmy) == key }) {
            lines[same.index] = row
            return lines.joined(separator: "\n")
        }
        return insertRow(text, row: row) { DayKey.dmyDate($0[0]) != nil }
    }

    /// Pinchazo en mg (un pinchazo por día y medicamento: el mismo día se corrige).
    static func addDose(_ text: String, date: Date, dose: Double, site: String, note: String, med: String = "") -> String? {
        addIntake(text, date: date, med: med, dose: "\(MD.formatNumber(dose, comma: true)) mg", site: site, note: note, replaceSameDay: true)
    }

    static func addMascotaVisit(_ text: String, date: Date, tipo: String, detalle: String, proxima: Date?, coste: String) -> String? {
        let row = rowString([DayKey.string(date), tipo, detalle, proxima.map(DayKey.string) ?? "", coste])
        return insertRow(text, row: row) { DayKey.date($0[0]) != nil }
    }

    static func toggleHabit(_ text: String, habit: String, day: Int) -> String? {
        var lines = MD.lines(text)
        guard let h = lines.firstIndex(where: { MD.fold($0).hasPrefix("| habito") }) else { return nil }
        var j = h + 2
        while j < lines.count, MD.isTable(lines[j]) {
            let c = MD.cells(lines[j])
            if MD.fold(c[0]) == MD.fold(habit), day >= 0, day + 1 < c.count {
                lines[j] = MD.setCell(lines[j], col: day + 1, value: c[day + 1].contains("✅") ? "" : "✅")
                return lines.joined(separator: "\n")
            }
            j += 1
        }
        return nil
    }

    static func setValue(_ text: String, after marker: String, value: String) -> String? {
        var lines = MD.lines(text)
        guard let i = lines.firstIndex(where: { $0.contains(marker) }), let r = lines[i].range(of: marker) else { return nil }
        lines[i] = String(lines[i][..<r.upperBound]) + (value.isEmpty ? " " : " \(value)")
        return lines.joined(separator: "\n")
    }

    static func setObjective(_ text: String, index: Int, value: String) -> String? {
        var lines = MD.lines(text)
        guard let o = lines.firstIndex(where: { $0.contains("**Tres objetivos:**") }) else { return nil }
        var n = 0
        var j = o + 1
        while j < lines.count, n < 3 {
            if lines[j].firstMatch(of: /^\s*[0-9]\.\s?(.*)$/) != nil {
                if n == index { lines[j] = "\(index + 1). \(value)"; return lines.joined(separator: "\n") }
                n += 1
            } else if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty { break }
            j += 1
        }
        return nil
    }

    static func setDates(_ text: String, items: [String]) -> String? {
        var lines = MD.lines(text)
        guard let f = lines.firstIndex(where: { $0.contains("**Fechas importantes:**") }) else { return nil }
        var end = f + 1
        while end < lines.count, lines[end].hasPrefix("- ") { end += 1 }
        let new = items.map { $0.hasPrefix("- ") ? $0 : "- \($0)" }
        lines.replaceSubrange((f + 1)..<end, with: new.isEmpty ? ["- [ ] "] : new)
        return lines.joined(separator: "\n")
    }

    static func setTask(_ text: String, task: TaskItem, done: Bool, on day: Date = Date()) -> String? {
        var lines = MD.lines(text)
        guard let i = MD.index(of: task.raw, in: lines, near: task.line) else { return nil }
        var l = lines[i]
        guard let box = l.firstMatch(of: /^(\s*(?:[-*+]|[0-9]+\.)\s+\[)[ xX](\])/) else { return nil }
        l = String(box.1) + (done ? "x" : " ") + String(box.2) + l[box.range.upperBound...]
        if done {
            if !l.contains("[completion::"), l.range(of: #"✅\s*[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) == nil { l += " [completion:: \(DayKey.string(day))]" }
        } else {
            l = l.replacingOccurrences(of: #"\s*(\[completion::[^\]]*\]|✅\s*[0-9]{4}-[0-9]{2}-[0-9]{2})"#, with: "", options: .regularExpression)
        }
        lines[i] = l
        return lines.joined(separator: "\n")
    }

    /// Una tarea como se escribe en la nota: `- [ ] Dentista ⏫ 📅 2026-11-02 ⏰ 17:30 ⏱ 1h 🔁 every week`. La hora solo va con fecha.
    static func taskLine(_ task: String, due: Date?, time: Int? = nil, recurrence: String? = nil, priority: Int = 0, muted: Bool = false, duration: Int? = nil) -> String {
        "- [ ] \(oneLine(task))" + priorityMark(priority) + dueMark(due, time) + durationMark(duration) + (muted ? " 🔕" : "") + (recurrence.map { " 🔁 every \($0)" } ?? "")
    }

    static func durationMark(_ minutes: Int?) -> String { minutes.map { " ⏱ \(TaskDuration.text($0))" } ?? "" }

    static func dueMark(_ due: Date?, _ time: Int?) -> String {
        guard let due else { return "" }
        return " 📅 \(DayKey.string(due))" + (time.map { " ⏰ \(TimeOfDay.text($0))" } ?? "")
    }

    static func addInboxTask(_ text: String, task: String, due: Date?, recurrence: String? = nil, priority: Int = 0, time: Int? = nil, muted: Bool = false, duration: Int? = nil) -> String? {
        var lines = MD.lines(text)
        let line = taskLine(task, due: due, time: time, recurrence: recurrence, priority: priority, muted: muted, duration: duration)
        guard let r = MD.section(lines, containing: "Pendiente de clasificar") else {
            lines.append(line)
            return lines.joined(separator: "\n")
        }
        let lastItem = r.last(where: { lines[$0].hasPrefix("- ") }) ?? r.lowerBound - 1
        lines.insertClamped(line, at: lastItem + 1)
        return lines.joined(separator: "\n")
    }
}

extension Edit {
    /// Añade una fila a la tabla de la sección, tras la última fila con la primera celda rellena.
    static func addRow(_ text: String, section: String, cells: [String]) -> String? {
        var lines = MD.lines(text)
        guard let range = MD.section(lines, containing: section) else { return nil }
        let rows = MD.tableRows(lines).filter { range.contains($0.index) }
        guard rows.count >= 2 else { return nil }
        let after = rows.dropFirst(2).last(where: { !($0.cells.first ?? "").isEmpty })?.index ?? rows[1].index
        lines.insertClamped("| " + cells.joined(separator: " | ") + " |", at: after + 1)
        return lines.joined(separator: "\n")
    }

    /// Cambia una celda de una fila de la sección. `expectFirst` evita editar la fila equivocada si el archivo cambió.
    static func setSectionCell(_ text: String, section: String, line: Int, expectFirst: String, column: String, value: String) -> String? {
        var lines = MD.lines(text)
        guard let range = MD.section(lines, containing: section), range.contains(line), line < lines.count, MD.isTable(lines[line]) else { return nil }
        let head = MD.tableRows(lines).first { range.contains($0.index) }
        guard let col = head?.cells.firstIndex(where: { MD.fold($0) == MD.fold(column) }) else { return nil }
        let cells = MD.cells(lines[line])
        guard cells.first == expectFirst, col < cells.count else { return nil }
        lines[line] = MD.setCell(lines[line], col: col, value: value)
        return lines.joined(separator: "\n")
    }
}

extension Edit {
    /// Completa una tarea que se repite: la marca hecha y añade justo debajo la siguiente repetición.
    static func completeRecurring(_ text: String, task: TaskItem, today: Date = DayKey.today()) -> String? {
        guard let base = task.recurrence, let done = setTask(text, task: task, done: true, on: today) else { return nil }
        let rule = Recurrence.pinningDay(base, due: task.due)
        var lines = MD.lines(done)
        // setTask no cambia el número de líneas: la tarea está en el mismo índice que en el texto original.
        guard let i = MD.index(of: task.raw, in: MD.lines(text), near: task.line), let next = Recurrence.next(after: task.due, rule: rule, today: today) else { return done }
        let prefix = task.raw.firstMatch(of: /^(\s*(?:[-*+]|[0-9]+\.)\s+\[)[ xX](\]\s+)/).map { String($0.1) + " " + String($0.2) } ?? "- [ ] "
        lines.insertClamped(prefix + task.text + priorityMark(task.priority) + dueMark(next, task.time) + durationMark(task.duration) + (task.muted ? " 🔕" : "") + " 🔁 every \(rule)", at: i + 1)
        return lines.joined(separator: "\n")
    }
}


// MARK: - Edición genérica

extension Edit {
    /// El texto en una sola línea. Cualquier salto (también un «\r» suelto, de un texto pegado de Windows) partiría la fila de la
    /// tabla o la tarea en dos, y lo de después quedaría como texto suelto en la nota.
    static func oneLine(_ s: String) -> String {
        s.contains(where: \.isNewline) ? s.split(whereSeparator: \.isNewline).joined(separator: " ") : s
    }

    static func rowString(_ cells: [String]) -> String {
        "| " + cells.map { oneLine($0).replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
    }

    static func updateRow(_ text: String, line: Int, expectFirst: String, cells: [String]) -> String? {
        var lines = MD.lines(text)
        guard line >= 0, line < lines.count, MD.isTable(lines[line]), MD.cells(lines[line]).first == expectFirst else { return nil }
        lines[line] = rowString(cells)
        return lines.joined(separator: "\n")
    }

    static func deleteRow(_ text: String, line: Int, expectFirst: String) -> String? {
        var lines = MD.lines(text)
        guard line >= 0, line < lines.count, MD.isTable(lines[line]), MD.cells(lines[line]).first == expectFirst else { return nil }
        lines.remove(at: line)
        return lines.joined(separator: "\n")
    }

    static func insertTableRow(_ text: String, afterLine: Int, cells: [String]) -> String? {
        var lines = MD.lines(text)
        guard afterLine >= 0, afterLine < lines.count, MD.isTable(lines[afterLine]) else { return nil }
        lines.insertClamped(rowString(cells), at: afterLine + 1)
        return lines.joined(separator: "\n")
    }

    /// Marca o desmarca la casilla `- [ ]` de una línea concreta.
    static func toggleCheckbox(_ text: String, line lineHint: Int, expect: String? = nil, on day: Date = Date(), completion: Bool = true) -> String? {
        var lines = MD.lines(text)
        // Si el archivo cambió desde que se pintó la pantalla, busca la línea exacta en vez de tocar otra.
        var line = lineHint
        if let expect, !(line >= 0 && line < lines.count && lines[line] == expect) {
            guard let found = MD.index(of: expect, in: lines, near: line) else { return nil }
            line = found
        }
        guard line >= 0, line < lines.count, let m = lines[line].firstMatch(of: /^(\s*(?:[-*+]|[0-9]+\.)\s+\[)([ xX])(\].*)$/) else { return nil }
        let wasDone = m.2 != " "
        var l = String(m.1) + (wasDone ? " " : "x") + String(m.3)
        if wasDone { l = l.replacingOccurrences(of: #"\s*(\[completion::[^\]]*\]|✅\s*[0-9]{4}-[0-9]{2}-[0-9]{2})"#, with: "", options: .regularExpression) }
        else if completion, !l.contains("[completion::") { l += " [completion:: \(DayKey.string(day))]" }
        lines[line] = l
        return lines.joined(separator: "\n")
    }

    static func priorityMark(_ p: Int) -> String { p == 3 ? " ⏫" : p == 2 ? " 🔼" : p == 1 ? " 🔽" : "" }

    /// `priority`: -1 la deja como está, 0 la quita, 1 a 3 la cambia. `time` y `duration`: `nil` las deja como están; `.some(nil)` las quita.
    static func updateTask(_ text: String, task: TaskItem, newText: String, due: Date?, priority: Int = -1, time: Int?? = nil, muted: Bool? = nil, duration: Int?? = nil) -> String? {
        var lines = MD.lines(text)
        guard let i = MD.index(of: task.raw, in: lines, near: task.line), let m = lines[i].firstMatch(of: /^(\s*(?:[-*+]|[0-9]+\.)\s+\[[ xX]\]\s+)(.*)$/) else { return nil }
        let body = String(m.2)
        var tail = ""
        // Se conservan las demás fechas de Obsidian Tasks (programada, inicio, creada, hecha) y la marca de completada.
        for pattern in [#"⏳\s*[0-9]{4}-[0-9]{2}-[0-9]{2}"#, #"🛫\s*[0-9]{4}-[0-9]{2}-[0-9]{2}"#, #"➕\s*[0-9]{4}-[0-9]{2}-[0-9]{2}"#, #"✅\s*[0-9]{4}-[0-9]{2}-[0-9]{2}"#, #"\[completion::[^\]]*\]"#] {
            if let r = body.range(of: pattern, options: .regularExpression) { tail += " " + body[r] }
        }
        if let r = Recurrence.find(in: body) { tail = " " + r.trimmingCharacters(in: .whitespaces) + tail }
        let prio = priority < 0 ? task.priority : priority
        lines[i] = String(m.1) + oneLine(newText).trimmingCharacters(in: .whitespaces) + priorityMark(prio) + dueMark(due, time ?? task.time) + durationMark(duration ?? task.duration) + ((muted ?? task.muted) ? " 🔕" : "") + tail
        return lines.joined(separator: "\n")
    }

    static func deleteLine(_ text: String, raw: String, hint: Int) -> String? {
        var lines = MD.lines(text)
        guard let i = MD.index(of: raw, in: lines, near: hint) else { return nil }
        lines.remove(at: i)
        return lines.joined(separator: "\n")
    }

    static func setFrontmatter(_ text: String, key: String, value: String) -> String? {
        var lines = MD.lines(text)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        if let i = lines[1..<end].firstIndex(where: { $0.hasPrefix("\(key):") }) {
            let old = String(lines[i].dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            let quoted = old.hasPrefix("\"") || yamlNeedsQuotes(value)
            lines[i] = "\(key):" + (value.isEmpty ? "" : quoted ? " " + yamlQuoted(value) : " \(value)")
        } else {
            lines.insertClamped("\(key):" + (value.isEmpty ? "" : yamlNeedsQuotes(value) ? " " + yamlQuoted(value) : " \(value)"), at: end)
        }
        return lines.joined(separator: "\n")
    }

    /// Valores que YAML leería mal sin comillas: con «: » o « #», que empiezan por un signo especial (`[[enlace]]`, `@`, `#`…) o con espacios en los bordes.
    static func yamlNeedsQuotes(_ v: String) -> Bool {
        guard let first = v.first else { return false }
        // `[a, b]` y `{a: 1}` son listas y mapas de YAML escritos a propósito; `[[Nota]]` no, es un enlace.
        if !v.hasPrefix("[["), (v.hasPrefix("[") && v.hasSuffix("]")) || (v.hasPrefix("{") && v.hasSuffix("}")) { return false }
        return v.contains(": ") || v.contains(" #") || v.hasSuffix(":") || v.hasPrefix("- ") || v.hasPrefix("? ")
            || "[]{}&*!|>'\"%@`#,".contains(first) || v != v.trimmingCharacters(in: .whitespaces)
    }

    static func yamlQuoted(_ v: String) -> String {
        "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func setFrontmatterList(_ text: String, key: String, items: [String]) -> String? {
        var lines = MD.lines(text)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        let new = ["\(key):"] + items.map { "  - \($0)" }
        if let i = lines[1..<end].firstIndex(where: { $0.hasPrefix("\(key):") }) {
            var j = i + 1
            while j < end, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("- ") { j += 1 }
            lines.replaceSubrange(i..<j, with: new)
        } else {
            lines.insertClamped(contentsOf: new, at: end)
        }
        return lines.joined(separator: "\n")
    }

    /// Cambia los enlaces a `old` por `new`. Entiende mayúsculas y tildes distintas (`[[medico]]` → «Médico») y enlaces
    /// con carpeta (`[[Salud/Médico]]`), que conservan su carpeta; los de otra carpeta con el mismo nombre no se tocan.
    static func renameLinks(_ text: String, old: String, new: String, folder: String = "") -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[\[([^\]|#\\]+)(?=[\]|#\\])"#) else { return text }
        let ns = text as NSString
        let oldKey = MD.fold(old), folderKey = MD.fold(folder)
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let target = ns.substring(with: m.range(at: 1))
            let dir = (target as NSString).deletingLastPathComponent
            guard MD.fold((target as NSString).lastPathComponent) == oldKey else { continue }
            if !dir.isEmpty, !folderKey.isEmpty, !folderKey.hasSuffix(MD.fold(dir)) { continue }
            let replacement = dir.isEmpty ? new : dir + "/" + new
            out = (out as NSString).replacingCharacters(in: m.range(at: 1), with: replacement)
        }
        return out
    }

    static func addHabitRow(_ text: String, name: String) -> String? {
        var lines = MD.lines(text)
        guard let h = lines.firstIndex(where: { MD.fold($0).hasPrefix("| habito") }) else { return nil }
        var j = h + 2
        while j < lines.count, MD.isTable(lines[j]) {
            if MD.fold(MD.cells(lines[j])[0]) == MD.fold(name) { return text }
            j += 1
        }
        lines.insertClamped("| \(name) |  |  |  |  |  |  |  |", at: j)
        return lines.joined(separator: "\n")
    }

    static func removeHabitRow(_ text: String, name: String) -> String? {
        var lines = MD.lines(text)
        guard let h = lines.firstIndex(where: { MD.fold($0).hasPrefix("| habito") }) else { return nil }
        var j = h + 2
        while j < lines.count, MD.isTable(lines[j]) {
            if MD.fold(MD.cells(lines[j])[0]) == MD.fold(name) { lines.remove(at: j); return lines.joined(separator: "\n") }
            j += 1
        }
        return nil
    }
}

extension Edit {
    /// Añade una línea de lista a una sección. Si hay un punto vacío (`- `), lo rellena.
    static func appendToSection(_ text: String, section: String, line: String) -> String? {
        var lines = MD.lines(text)
        guard let r = MD.section(lines, containing: section) else { return nil }
        if let empty = r.first(where: { ["-", "- [ ]"].contains(lines[$0].trimmingCharacters(in: .whitespaces)) }) {
            lines[empty] = line
        } else {
            let last = r.last(where: { lines[$0].hasPrefix("- ") }) ?? (r.lowerBound - 1)
            lines.insertClamped(line, at: last + 1)
        }
        return lines.joined(separator: "\n")
    }
}

extension Edit {
    /// Reescribe la tabla de hábitos con la lista dada (nombre y criterio), conservando las marcas de cada día.
    static func setHabitTable(_ text: String, defs: [HabitDef]) -> String? {
        var lines = MD.lines(text)
        guard let h = lines.firstIndex(where: { MD.fold($0).hasPrefix("| habito") }) else { return nil }
        var end = h + 1
        while end < lines.count, MD.isTable(lines[end]) { end += 1 }
        var old: [String: [String]] = [:]
        for j in (h + 2)..<max(end, h + 2) {
            let c = MD.cells(lines[j])
            old[MD.fold(c[0])] = (1...7).map { $0 < c.count ? c[$0] : "" }
        }
        var block = ["| Hábito | L | M | X | J | V | S | D | Criterio |", "| :----- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :------- |"]
        for d in defs {
            let marks = old[MD.fold(d.name)] ?? [String](repeating: "", count: 7)
            block.append("| " + ([d.name] + marks).joined(separator: " | ") + " | " + d.criterion.replacingOccurrences(of: "|", with: "\\|") + " |")
        }
        lines.replaceSubrange(h..<end, with: block)
        return lines.joined(separator: "\n")
    }

    /// Convierte los enlaces a una nota en texto (para cuando la nota se elimina). Quita el separador " · " que lo rodeaba.
    /// Como `renameLinks`, entiende mayúsculas y tildes distintas (`[[medico]]`) y enlaces con carpeta (`[[Salud/Médico]]`).
    static func unlink(_ text: String, name: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\[\[([^\]|#\\]+)(?:#[^\]|\\]*)?(?:\\?\|([^\]]*))?\]\]"#),
              let sep = try? NSRegularExpression(pattern: #"^[ \t]·[ \t]$"#) else { return text }
        let key = MD.fold(name)
        var out = text as NSString
        func isSeparator(_ r: NSRange) -> Bool {
            r.location >= 0 && r.location + r.length <= out.length && sep.firstMatch(in: out.substring(with: r), range: NSRange(location: 0, length: 3)) != nil
        }
        for m in re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let target = (text as NSString).substring(with: m.range(at: 1))
            guard MD.fold((target as NSString).lastPathComponent) == key else { continue }
            let before = NSRange(location: m.range.location - 3, length: 3), after = NSRange(location: m.range.location + m.range.length, length: 3)
            if isSeparator(before) {
                out = out.replacingCharacters(in: NSRange(location: before.location, length: 3 + m.range.length), with: "") as NSString
            } else if isSeparator(after) {
                out = out.replacingCharacters(in: NSRange(location: m.range.location, length: m.range.length + 3), with: "") as NSString
            } else {
                let alias = m.range(at: 2).location != NSNotFound ? (text as NSString).substring(with: m.range(at: 2)) : (target as NSString).lastPathComponent
                out = out.replacingCharacters(in: m.range, with: alias) as NSString
            }
        }
        return out as String
    }
}


extension Edit {
    /// Añade enlaces a una línea final «Relacionado» (o a la línea de enlaces del pie). No repite los que la nota ya tiene.
    static func addRelated(_ text: String, links: [String]) -> String? {
        var lines = MD.lines(text)
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        let existing = Set(Links.extract(text).map { MD.fold($0) })
        let new = links.filter { !existing.contains(MD.fold($0)) }
        guard !new.isEmpty else { return text }
        let tokens = new.map { "[[\($0)]]" }.joined(separator: " · ")
        if let last = lines.last, last.hasPrefix("Relacionado:") || last.range(of: #"^(\[\[[^\]]+\]\](?: · )?)+$"#, options: .regularExpression) != nil {
            lines[lines.count - 1] = last + " · " + tokens
        } else if lines.last == "---" {
            lines.append("Relacionado: " + tokens)
        } else {
            lines += ["", "---", "Relacionado: " + tokens]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension Edit {
    /// Enlaces `[[..]]`, código `..`, direcciones y paréntesis: ahí no se enlaza. Se compilan una vez.
    private static let protectedZones = [#"\[\[[^\]]*\]\]"#, #"`[^`]*`"#, #"https?://\S+"#, #"\([^)]*\)"#].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Convierte la primera mención sin enlazar de `name` en `[[name]]` (fuera de código, enlaces y direcciones).
    static func linkMention(_ text: String, name: String) -> String? {
        guard name.count >= 3 else { return nil }
        var lines = MD.lines(text)
        let fence = MD.fenced(lines)
        var start = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { start = end + 1 }
        let pattern = "(?<![\\p{L}\\p{N}\\[|/#.])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}\\]|/])"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for i in start..<lines.count where !fence.contains(i) {
            let line = lines[i]
            let ns = line as NSString
            let matches = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { continue }
            // zonas protegidas: enlaces [[..]], código `..` y direcciones
            let protected = protectedZones.flatMap { $0.matches(in: line, range: NSRange(location: 0, length: ns.length)).map(\.range) }
            for m in matches {
                if protected.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                let found = ns.substring(with: m.range)
                let link = found == name ? "[[\(name)]]" : "[[\(name)|\(found)]]"
                lines[i] = ns.replacingCharacters(in: m.range, with: link)
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }
}

extension Edit {
    /// Limpia pies de nota: quita líneas «Inicio» sueltas (restos de un enlace borrado) y junta separadores `---` repetidos.
    static func tidyFooter(_ text: String) -> String {
        var lines = MD.lines(text)
        let tailStart = max(lines.count - 6, 0)
        lines = lines.enumerated().filter { $0.offset < tailStart || $0.element.trimmingCharacters(in: .whitespaces) != "Inicio" }.map(\.element)
        // «--- (vacíos) ---» → un solo «---»
        var i = 0
        while i < lines.count {
            if lines[i] == "---", i > 0 {
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if j < lines.count, lines[j] == "---", !(MD.fenced(lines).contains(i)) { lines.removeSubrange((i + 1)...j); continue }
            }
            i += 1
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last == "---" { lines.removeLast() }
        // varias líneas vacías seguidas en el pie → una
        var tidy: [String] = []
        let from = max(lines.count - 8, 0)
        for (i, l) in lines.enumerated() {
            if i >= from, l.trimmingCharacters(in: .whitespaces).isEmpty, tidy.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { continue }
            tidy.append(l)
        }
        return tidy.joined(separator: "\n") + "\n"
    }
}

extension Edit {
    /// Quita los bloques ```dataview / ```dataviewjs (consultas de Obsidian), su etiqueta «Resumen (automático)» y los encabezados que se quedan vacíos.
    static func removeDataview(_ text: String) -> String {
        var lines = MD.lines(text)
        func isStart(_ l: String) -> Bool { let t = l.trimmingCharacters(in: .whitespaces); return t.hasPrefix("```dataview") }
        var changed = false
        var i = 0
        while i < lines.count {
            guard isStart(lines[i]) else { i += 1; continue }
            var end = i + 1
            while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("```") { end += 1 }
            let last = min(end, lines.count - 1)
            var first = i
            // etiqueta propia del bloque justo encima
            var k = first - 1
            while k >= 0, lines[k].trimmingCharacters(in: .whitespaces).isEmpty { k -= 1 }
            if k >= 0, lines[k].contains("Resumen (automático)") { first = k }
            lines.removeSubrange(first...last)
            changed = true
            i = first
        }
        guard changed else { return text }

        // encabezados que quedaron sin contenido (solo líneas vacías o `---` hasta el siguiente encabezado o el final)
        var j = 0
        while j < lines.count {
            if lines[j].hasPrefix("#"), !MD.fenced(lines).contains(j) {
                var e = j + 1
                while e < lines.count, !lines[e].hasPrefix("#") { e += 1 }
                let body = lines[(j + 1)..<e].filter { let t = $0.trimmingCharacters(in: .whitespaces); return !t.isEmpty && t != "---" }
                let isTitle = lines[j].hasPrefix("# ")
                if body.isEmpty, !isTitle {
                    lines.removeSubrange(j..<e)
                    continue
                }
            }
            j += 1
        }
        // varias líneas vacías o reglas repetidas → una
        var out: [String] = []
        for l in lines {
            let blank = l.trimmingCharacters(in: .whitespaces).isEmpty
            if blank, out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { continue }
            out.append(l)
        }
        var k2 = 0
        while k2 < out.count {
            if out[k2] == "---" {
                var n = k2 + 1
                while n < out.count, out[n].trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
                if n < out.count, out[n] == "---", k2 > 0 { out.removeSubrange((k2 + 1)...n); continue }
            }
            k2 += 1
        }
        while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }
}

extension Edit {
    /// Añade líneas a una sección; si la sección no existe la crea antes del pie de la nota.
    static func appendToSectionCreating(_ text: String, section: String, lines new: [String]) -> String? {
        guard !new.isEmpty else { return nil }
        var lines = MD.lines(text)
        if let r = MD.section(lines, containing: section) {
            var last = r.last(where: { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty && lines[$0] != "---" }) ?? (r.lowerBound - 1)
            if last < r.lowerBound - 1 { last = r.lowerBound - 1 }
            lines.insertClamped(contentsOf: new, at: last + 1)
        } else {
            var at = lines.count
            while at > 0, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
            if let hr = lines.lastIndex(of: "---"), hr > 0, hr >= at - 3 { at = hr }
            lines.insertClamped(contentsOf: ["## \(section)"] + new + [""], at: at)
        }
        return lines.joined(separator: "\n")
    }
}
