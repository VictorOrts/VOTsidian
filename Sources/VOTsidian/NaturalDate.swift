import Foundation

/// Entiende fechas escritas en español dentro de una frase: "llamar al dentista el viernes", "pagar 25/11", "revisar en 3 días".
enum NaturalDate {
    private static let weekdays = ["domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7]
    private static let months = ["enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7,
                                 "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12]

    /// Devuelve el texto sin la expresión de fecha y la fecha, si la hay.
    static func extract(_ input: String, today: Date = DayKey.today()) -> (text: String, date: Date?) {
        let cal = DayKey.calendar()
        // Plegado carácter a carácter para que los rangos coincidan con el original.
        let folded = String(input.map { ch -> Character in
            String(ch).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first ?? ch
        })
        let ns = folded as NSString
        let full = NSRange(location: 0, length: ns.length)
        let todayYear = cal.component(.year, from: today)

        func date(_ y: Int?, _ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            var year = y ?? todayYear
            if let y, y < 100 { year = 2000 + y }
            guard var out = cal.date(from: DateComponents(year: year, month: m, day: d)) else { return nil }
            if y == nil, out < today { out = cal.date(from: DateComponents(year: year + 1, month: m, day: d)) ?? out }
            return out
        }

        func apply(_ pattern: String, _ resolve: (NSTextCheckingResult) -> Date?) -> (String, Date)? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: folded, range: full), let d = resolve(m) else { return nil }
            var removed = (input as NSString).replacingCharacters(in: m.range, with: "")
            // Quita conectores que se quedan colgando antes o después.
            removed = removed.replacingOccurrences(of: #"(?i)\s+(para|el|este|esta|proximo|próximo|de|en|a)\s*$"#, with: "", options: .regularExpression)
            removed = removed.replacingOccurrences(of: #"(?i)^\s*(para|el)\s+"#, with: "", options: .regularExpression)
            removed = removed.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            return (removed, d)
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }

        let rules: [(String, (NSTextCheckingResult) -> Date?)] = [
            (#"\b(\d{4})-(\d{2})-(\d{2})\b"#, { m in date(Int(group(m, 1)!), Int(group(m, 2)!)!, Int(group(m, 3)!)!) }),
            (#"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#, { m in date(group(m, 3).flatMap { Int($0) }, Int(group(m, 2)!)!, Int(group(m, 1)!)!) }),
            (#"\b(\d{1,2}) de (enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?: de (\d{4}))?\b"#,
             { m in date(group(m, 3).flatMap { Int($0) }, months[group(m, 2)!]!, Int(group(m, 1)!)!) }),
            (#"\b(?:anteayer|antes de ayer)\b"#, { _ in DayKey.adding(days: -2, to: today) }),
            (#"\bayer\b"#, { _ in DayKey.adding(days: -1, to: today) }),
            (#"\bpasado manana\b"#, { _ in DayKey.adding(days: 2, to: today) }),
            (#"\bmanana\b"#, { _ in DayKey.adding(days: 1, to: today) }),
            (#"\bhoy\b"#, { _ in today }),
            (#"\ben (\d+) (dias?|semanas?|meses?)\b"#, { m in
                let n = Int(group(m, 1)!)!
                let unit = group(m, 2)!
                if unit.hasPrefix("semana") { return DayKey.adding(days: 7 * n, to: today) }
                if unit.hasPrefix("mes") { return cal.date(byAdding: .month, value: n, to: today) }
                return DayKey.adding(days: n, to: today)
            }),
            (#"\b(?:(?:el|este|proximo) )?(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b"#, { m in
                let target = weekdays[group(m, 1)!]!
                var delta = (target - cal.component(.weekday, from: today) + 7) % 7
                if delta == 0 { delta = 7 }
                return DayKey.adding(days: delta, to: today)
            }),
            (#"\bel (\d{1,2})\b"#, { m in
                let d = Int(group(m, 1)!)!
                let month = cal.component(.month, from: today)
                guard let this = cal.date(from: DateComponents(year: todayYear, month: month, day: d)) else { return nil }
                return this >= today ? this : cal.date(byAdding: .month, value: 1, to: this)
            }),
        ]
        for (pattern, resolve) in rules {
            if let (text, d) = apply(pattern, resolve) { return (text, d) }
        }
        return (input.trimmingCharacters(in: .whitespaces), nil)
    }

    struct ParsedTask { var text: String; var date: Date?; var recurrence: String?; var priority = 0 }

    /// Como `extract`, pero entiende también "cada semana", "cada 15 días", "cada lunes", "todos los meses".
    static func extractTask(_ input: String, today: Date = DayKey.today()) -> ParsedTask {
        // Prioridad: «urgente», «importante», «prioridad alta/media/baja» o «!» al final.
        var priority = 0
        var base = input
        let prioRules: [(String, Int)] = [(#"(?i)\b(urgente|prioridad alta|muy importante)\b"#, 3), (#"(?i)\b(importante|prioridad media)\b"#, 2), (#"(?i)\bprioridad baja\b"#, 1), (#"\s*!{1,3}\s*$"#, 3)]
        for (pattern, level) in prioRules where priority == 0 {
            if let r = base.range(of: pattern, options: .regularExpression) {
                priority = level
                base.removeSubrange(r)
                base = base.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            }
        }
        if priority > 0 { var r = extractTask(base, today: today, noPriority: true); r.priority = priority; return r }
        return extractTask(base, today: today, noPriority: true)
    }

    private static func extractTask(_ input: String, today: Date, noPriority: Bool) -> ParsedTask {
        let cal = DayKey.calendar()
        let folded = String(input.map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first ?? $0 })
        let ns = folded as NSString
        let patterns: [(String, (NSTextCheckingResult) -> (String, Date?))] = [
            (#"\bcada (\d+) (dias?|semanas?|meses|mes|anos?)\b"#, { m in
                let n = ns.substring(with: m.range(at: 1)), u = ns.substring(with: m.range(at: 2))
                let unit = u.hasPrefix("dia") ? "days" : u.hasPrefix("semana") ? "weeks" : u.hasPrefix("mes") ? "months" : "years"
                return ("\(n) \(unit)", nil)
            }),
            (#"\b(?:cada|todos los|todas las) (dia|dias|semana|semanas|mes|meses|ano|anos)\b"#, { m in
                let u = ns.substring(with: m.range(at: 1))
                return (u.hasPrefix("dia") ? "day" : u.hasPrefix("semana") ? "week" : u.hasPrefix("mes") ? "month" : "year", nil)
            }),
            (#"\b(?:cada|todos los|todas las) (lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b"#, { m in
                let names = ["domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7]
                let target = names[ns.substring(with: m.range(at: 1))]!
                var delta = (target - cal.component(.weekday, from: today) + 7) % 7
                if delta == 0 { delta = 7 }
                return ("week", DayKey.adding(days: delta, to: today))
            }),
        ]
        for (pattern, resolve) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: folded, range: NSRange(location: 0, length: ns.length)) else { continue }
            let (rule, weekdayDate) = resolve(m)
            let rest = (input as NSString).replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespaces)
            let inner = extract(rest, today: today)
            let start = weekdayDate ?? inner.date ?? Recurrence.component(rule).flatMap { cal.date(byAdding: $0.0, value: $0.1, to: today) }
            return ParsedTask(text: inner.text, date: start, recurrence: rule)
        }
        let p = extract(input, today: today)
        return ParsedTask(text: p.text, date: p.date, recurrence: nil)
    }
}
