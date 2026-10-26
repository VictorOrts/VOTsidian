import Foundation

/// Entiende fechas escritas en español dentro de una frase: "llamar al dentista el viernes", "pagar 25/11", "revisar en 3 días".
enum NaturalDate {
    private static let weekdays = ["domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7]
    private static let months = ["enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7,
                                 "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12]

    /// Qué se escribió, para saber cómo llevar la fecha al pasado (un gasto) cuando cae en el futuro.
    enum Kind { case none, exact, dayMonth, dayOfMonth, weekday, relative }

    private static let numberWords = ["un": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "quince": 15]

    /// El texto sin tildes ni mayúsculas, con **exactamente** la misma longitud (en unidades UTF-16) que el original, para que las
    /// posiciones que se encuentran en él valgan en el original. Lo que no se puede plegar sin cambiar la longitud (un emoji
    /// compuesto, una bandera) se sustituye por un carácter que no coincide con nada.
    static func aligned(_ input: String) -> String {
        var out = ""
        for ch in input {
            let f = String(ch).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            out += f.utf16.count == ch.utf16.count ? f : String(repeating: "\u{FFFD}", count: ch.utf16.count)
        }
        return out
    }

    /// Devuelve el texto sin la expresión de fecha y la fecha, si la hay.
    static func extract(_ input: String, today: Date = DayKey.today()) -> (text: String, date: Date?) {
        let r = extractKind(input, today: today)
        return (r.text, r.date)
    }

    /// Como `extract`, y además el tipo de expresión: `dayMonth` («22/10», «3 de mayo», sin año), `dayOfMonth` («el 20»),
    /// `weekday` («el viernes»), `exact` (con año) o `relative` («ayer», «en 3 días»).
    static func extractKind(_ input: String, today: Date = DayKey.today()) -> (text: String, date: Date?, kind: Kind) {
        let cal = DayKey.calendar()
        // «n» + tilde suelta (al pegar desde un PDF, por ejemplo) pasa a «ñ»: así se reconoce «mañana» y las posiciones cuadran.
        let input = input.precomposedStringWithCanonicalMapping
        let folded = aligned(input)
        let ns = folded as NSString
        let full = NSRange(location: 0, length: ns.length)
        let todayYear = cal.component(.year, from: today)

        func date(_ y: Int?, _ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            var year = y ?? todayYear
            if let y, y < 100 { year = 2000 + y }
            if y != nil { return DayKey.make(year, m, d) }
            // Sin año, la próxima vez que exista: «el 29 de febrero» puede caer dentro de tres años.
            for k in 0...8 { if let out = DayKey.make(year + k, m, d), out >= today { return out } }
            return nil
        }

        func apply(_ pattern: String, _ resolve: (NSTextCheckingResult) -> Date?) -> (String, Date)? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: folded, range: full), let d = resolve(m) else { return nil }
            var removed = (input as NSString).replacingCharacters(in: m.range, with: "")
            // Quita conectores que se quedan colgando antes o después.
            removed = removed.replacingOccurrences(of: #"(?i)(\s+(para|el|este|esta|proximo|próximo|de|en|a))+\s*$"#, with: "", options: .regularExpression)
            removed = removed.replacingOccurrences(of: #"(?i)^\s*(para|el)\s+"#, with: "", options: .regularExpression)
            removed = removed.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            return (removed, d)
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }

        // El tipo de las fechas sin año depende de si se escribió el año: se apunta al resolver.
        var yearGiven = false
        let rules: [(String, Kind, (NSTextCheckingResult) -> Date?)] = [
            (#"\b([0-9]{4})-([0-9]{2})-([0-9]{2})\b"#, .exact, { m in date(Int(group(m, 1)!), Int(group(m, 2)!)!, Int(group(m, 3)!)!) }),
            // Un día de la semana delante («el lunes 2 de noviembre», «el viernes 30/10») va con la fecha: si no, quedaba en el texto.
            (#"(?:\b(?:el )?(?:lunes|martes|miercoles|jueves|viernes|sabado|domingo),? )?\b([0-9]{1,2})/([0-9]{1,2})(?:/([0-9]{2,4}))?\b"#, .dayMonth, { m in
                yearGiven = group(m, 3) != nil
                return date(group(m, 3).flatMap { Int($0) }, Int(group(m, 2)!)!, Int(group(m, 1)!)!) }),
            (#"(?:\b(?:el )?(?:lunes|martes|miercoles|jueves|viernes|sabado|domingo),? )?\b([0-9]{1,2}) de (enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?: de ([0-9]{4}))?\b"#, .dayMonth,
             { m in
                yearGiven = group(m, 3) != nil
                return date(group(m, 3).flatMap { Int($0) }, months[group(m, 2)!]!, Int(group(m, 1)!)!) }),
            (#"\b(?:anteayer|antes de ayer)\b"#, .relative, { _ in DayKey.adding(days: -2, to: today) }),
            (#"\bayer\b"#, .relative, { _ in DayKey.adding(days: -1, to: today) }),
            (#"\bpasado manana\b"#, .relative, { _ in DayKey.adding(days: 2, to: today) }),
            (#"\bmanana\b"#, .relative, { _ in DayKey.adding(days: 1, to: today) }),
            (#"\bhoy\b"#, .relative, { _ in today }),
            (#"\b(?:en|dentro de) ([0-9]{1,4}|un|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|quince) (dias?|semanas?|meses?|anos?)\b"#, .relative, { m in
                let word = group(m, 1)!
                guard let n = Int(word) ?? numberWords[word] else { return nil }
                let unit = group(m, 2)!
                if unit.hasPrefix("semana") { return DayKey.adding(days: 7 * n, to: today) }
                if unit.hasPrefix("mes") { return cal.date(byAdding: .month, value: n, to: today) }
                if unit.hasPrefix("ano") { return cal.date(byAdding: .year, value: n, to: today) }
                return DayKey.adding(days: n, to: today)
            }),
            (#"\b(?:(?:el|este|proximo) )?(lunes|martes|miercoles|jueves|viernes|sabado|domingo)(?: que viene)?\b"#, .weekday, { m in
                let target = weekdays[group(m, 1)!]!
                var delta = (target - cal.component(.weekday, from: today) + 7) % 7
                if delta == 0 { delta = 7 }
                return DayKey.adding(days: delta, to: today)
            }),
            (#"\bel ([0-9]{1,2})\b"#, .dayOfMonth, { m in
                let d = Int(group(m, 1)!)!
                let month = cal.component(.month, from: today)
                // El próximo día `d` que exista: «el 31» en noviembre es el 31 de diciembre, no el 1.
                var c = DateComponents(year: todayYear, month: month)
                for _ in 0..<12 {
                    if let this = DayKey.make(c.year!, c.month!, d), this >= today { return this }
                    c.month! += 1
                    if c.month! > 12 { c.month = 1; c.year! += 1 }
                }
                return nil
            }),
            // «en enero»: el día 1 de la próxima vez que llegue ese mes (si es el mes en curso, hoy).
            (#"\ben (enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)(?: de ([0-9]{4}))?\b"#, .dayMonth, { m in
                let month = months[group(m, 1)!]!
                if let y = group(m, 2).flatMap({ Int($0) }) { yearGiven = true; return date(y, month, 1) }
                return month == cal.component(.month, from: today) ? today : date(nil, month, 1)
            }),
        ]
        for (pattern, kind, resolve) in rules {
            if let (text, d) = apply(pattern, resolve) { return (text, d, kind == .dayMonth && yearGiven ? .exact : kind) }
        }
        return (input.trimmingCharacters(in: .whitespaces), nil, .none)
    }

    struct ParsedTask: Equatable { var text: String; var date: Date?; var recurrence: String? = nil; var priority = 0; var time: Int? = nil; var muted = false; var duration: Int? = nil }

    /// La hora escrita en una frase: «a las 17:30», «a las 5 de la tarde», «a las 9 y media», «sobre las 10», «a mediodía» o
    /// «17:30» suelto. Devuelve la frase sin ella y la hora en minutos. «A las 1» a «a las 6» sin «de la mañana» son de la tarde,
    /// que es como se dice una cita.
    static func extractTime(_ input: String) -> (text: String, minutes: Int?) {
        let input = input.precomposedStringWithCanonicalMapping
        let folded = aligned(input)
        let ns = folded as NSString
        let full = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        func cut(_ m: NSTextCheckingResult) -> String {
            (input as NSString).replacingCharacters(in: m.range, with: "").replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        if let re = try? NSRegularExpression(pattern: #"\b(?:a|sobre)\s+las?\s+([0-9]{1,2})(?:[:.h]([0-9]{2}))?(?:\s*h\b)?(?:\s+(y media|y cuarto|menos cuarto))?(?:\s+de la (manana|tarde|noche|madrugada)|\s+(del mediodia))?\b"#),
           let m = re.firstMatch(in: folded, range: full), var h = group(m, 1).flatMap({ Int($0) }) {
            var mi = group(m, 2).flatMap { Int($0) } ?? 0
            switch group(m, 3) {
            case "y media": mi += 30
            case "y cuarto": mi += 15
            case "menos cuarto": h -= 1; mi = 45
            default: break
            }
            let part = group(m, 4)
            if part == "tarde" || part == "noche" || group(m, 5) != nil { if h < 12 { h += 12 } }
            else if part == nil, (1...6).contains(h) { h += 12 }
            if (0..<24).contains(h), (0..<60).contains(mi) { return (cut(m), h * 60 + mi) }
        }
        if let re = try? NSRegularExpression(pattern: #"\ba mediodia\b"#), let m = re.firstMatch(in: folded, range: full) { return (cut(m), 12 * 60) }
        if let re = try? NSRegularExpression(pattern: #"(?<![0-9/])([0-9]{1,2}):([0-9]{2})(?![0-9])(?:\s*h\b)?"#), let m = re.firstMatch(in: folded, range: full),
           let h = group(m, 1).flatMap({ Int($0) }), let mi = group(m, 2).flatMap({ Int($0) }), h < 24, mi < 60 {
            return (cut(m), h * 60 + mi)
        }
        return (input, nil)
    }

    /// Lo que dura algo: «de 10 a 11:30» (hora y duración), «durante 45 min», «durante 2 horas», «durante hora y media» o
    /// «⏱ 1h30m» tal cual. Devuelve la frase sin ello. Las horas de 1 a 6 son de la tarde, como en `extractTime`.
    static func extractDuration(_ input: String) -> (text: String, time: Int?, minutes: Int?) {
        let input = input.precomposedStringWithCanonicalMapping
        let folded = aligned(input)
        let ns = folded as NSString
        let full = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
        func cut(_ m: NSTextCheckingResult) -> String {
            (input as NSString).replacingCharacters(in: m.range, with: "").replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        // Un tramo de cantidades no es un horario: «subir de 3 a 5 kg», «leer de 10 a 20 páginas», «de 2 a 4 personas».
        let notHours = #"(?![0-9])(?!\s*(?:[€%x]|(?:kg|kilos?|g|gr|gramos|km|kilometros|m|metros|cm|l|litros?|ml|paginas?|pags?|capitulos?|euros?|veces|series|repeticiones|personas|anos|meses|semanas|dias|minutos|min|horas|libros?|unidades|uds?)\b))"#
        if let re = try? NSRegularExpression(pattern: #"\b(?:de|desde las?)\s+([0-9]{1,2})(?:[:.]([0-9]{2}))?\s+(?:a|hasta)(?:\s+las?)?\s+([0-9]{1,2})(?:[:.]([0-9]{2}))?(?:\s*h\b)?"# + notHours),
           let m = re.firstMatch(in: folded, range: full), var h1 = group(m, 1), var h2 = group(m, 3) {
            if (1...6).contains(h1) { h1 += 12 }
            if (1...6).contains(h2) || h2 < h1 && h2 < 12 { h2 += 12 }
            let start = h1 * 60 + (group(m, 2) ?? 0), end = h2 * 60 + (group(m, 4) ?? 0)
            if h1 < 24, h2 <= 24, (group(m, 2) ?? 0) < 60, (group(m, 4) ?? 0) < 60, TaskDuration.range.contains(end - start) { return (cut(m), start, end - start) }
        }
        // «9:00-10:30», «9:00 – 10:30»: con minutos a los dos lados, para no confundirlo con «3-5 kg».
        if let re = try? NSRegularExpression(pattern: #"(?<![0-9/])([0-9]{1,2})[:.]([0-9]{2})\s*[-–]\s*([0-9]{1,2})[:.]([0-9]{2})(?![0-9])(?:\s*h\b)?"#),
           let m = re.firstMatch(in: folded, range: full), let h1 = group(m, 1), let m1 = group(m, 2), let h2 = group(m, 3), let m2 = group(m, 4),
           h1 < 24, h2 <= 24, m1 < 60, m2 < 60, TaskDuration.range.contains(h2 * 60 + m2 - h1 * 60 - m1) {
            return (cut(m), h1 * 60 + m1, h2 * 60 + m2 - h1 * 60 - m1)
        }
        let words: [(String, (NSTextCheckingResult) -> Int?)] = [
            (#"\bdurante (?:una )?hora y media\b"#, { _ in 90 }),
            (#"\bdurante media hora\b"#, { _ in 30 }),
            (#"\bdurante una hora\b"#, { _ in 60 }),
            (#"\bdurante ([0-9]{1,2})\s*(?:horas?\b|h)(?:\s*y media)?(?:\s*([0-9]{1,2})\s*(?:minutos|min|m)?\b)?"#, { m in
                guard let h = group(m, 1) else { return nil }
                return h * 60 + (ns.substring(with: m.range).contains("y media") ? 30 : group(m, 2) ?? 0)
            }),
            (#"\bdurante ([0-9]{1,4})\s*(?:m|min|minutos?)\b"#, { group($0, 1) }),
            (#"⏱\x{FE0F}?\s*([0-9]{1,2}h(?:[0-9]{1,2}m?)?|[0-9]{1,4}m(?:in)?)"#, { m in TaskDuration.parse(ns.substring(with: m.range(at: 1))) }),
        ]
        for (pattern, value) in words {
            if let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: folded, range: full), let v = value(m), TaskDuration.range.contains(v) {
                return (cut(m), nil, v)
            }
        }
        return (input, nil, nil)
    }

    /// Fecha y hora de una frase («cita dentista el 29/10 a las 17:30»): primero la hora, luego la fecha con lo que queda.
    static func extractDateTime(_ input: String, today: Date = DayKey.today()) -> (text: String, date: Date?, time: Int?) {
        let t = extractTime(input)
        let d = extract(t.text, today: today)
        return (d.text, d.date, t.minutes)
    }

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
        // «sin aviso», «sin avisar», «no avisar»: la tarea no va a Calendar ni a las notificaciones.
        var muted = false
        if let r = base.range(of: #"(?i)\s*\b(sin avisos?|sin avisar|no avisar)\b"#, options: .regularExpression) {
            muted = true
            base.removeSubrange(r)
            base = base.trimmingCharacters(in: .whitespaces)
        }
        let lasting = extractDuration(base)
        let timed = extractTime(lasting.text)
        var r = extractTask(timed.text, today: today, noPriority: true)
        r.priority = priority
        r.time = lasting.time ?? timed.minutes
        r.muted = muted
        r.duration = lasting.minutes
        return r
    }

    private static func extractTask(_ input: String, today: Date, noPriority: Bool) -> ParsedTask {
        let cal = DayKey.calendar()
        let input = input.precomposedStringWithCanonicalMapping
        let folded = aligned(input)
        let ns = folded as NSString
        let patterns: [(String, (NSTextCheckingResult) -> (String, Date?))] = [
            (#"\b(?:cada dia laborable|todos los dias laborables|los dias laborables|entre semana|de lunes a viernes)\b"#, { _ in
                ("weekday", cal.isDateInWeekend(today) ? Recurrence.next(after: today, rule: "weekday", today: today) : today)
            }),
            (#"\bcada ([0-9]+) (dias?|semanas?|meses|mes|anos?)\b"#, { m in
                let n = ns.substring(with: m.range(at: 1)), u = ns.substring(with: m.range(at: 2))
                let unit = u.hasPrefix("dia") ? "days" : u.hasPrefix("semana") ? "weeks" : u.hasPrefix("mes") ? "months" : "years"
                return ("\(n) \(unit)", nil)
            }),
            (#"\b(?:al dia|a diario|diariamente)\b"#, { _ in ("day", nil) }),
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
