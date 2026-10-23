import Foundation

// MARK: - Entender «22 € cena con Ana»

enum ExpenseParser {
    struct Result: Equatable { var amount: Double; var category: String?; var note: String; var person: String?; var date: Date }

    /// Palabras que llevan a una partida aunque su nombre no aparezca: se buscan dentro del nombre de las partidas.
    private static let hints: [(words: [String], partida: [String])] = [
        (["cena", "comida fuera", "restaurante", "bar", "cafe", "copas", "cine", "concierto", "viaje", "hotel", "vuelo", "entrada"], ["restaurante", "ocio", "entreten"]),
        (["gasolina", "metro", "taxi", "uber", "cabify", "bus", "autobus", "parking", "tren", "peaje", "renfe", "taller", "itv", "neumaticos"], ["transporte"]),
        (["mercadona", "super", "supermercado", "compra", "carrefour", "lidl", "fruta", "aldi", "alcampo", "eroski", "consum"], ["alimenta", "comida"]),
        (["luz", "agua", "gas", "factura", "endesa", "iberdrola", "naturgy"], ["suministro", "luz"]),
        (["fibra", "internet", "movil", "telefono", "movistar", "vodafone", "orange", "digi", "o2", "pepephone", "lowi", "simyo"], ["internet", "movil"]),
        (["gym", "gimnasio"], ["gym", "deporte"]),
        (["farmacia", "dentista", "fisio", "medico"], ["salud"]),
        (["ropa", "zapatos", "zara", "peluqueria"], ["ropa"]),
        (["spotify", "netflix", "icloud", "music", "hbo", "disney", "suscripcion"], ["suscrip"]),
        (["comunidad"], ["comunidad"]),
        (["ahorro", "fondo"], ["ahorro"]),
    ]

    /// Palabras de la nota que se guardan al corregir la partida («dentista» → «Imprevistos»): las vacías no cuentan.
    static func keywords(_ note: String) -> [String] {
        let stop: Set = ["con", "para", "del", "los", "las", "una", "uno", "por", "que", "the"]
        return MD.fold(note.replacingOccurrences(of: #"\[\[[^\]]*\]\]"#, with: " ", options: .regularExpression))
            .split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 && !stop.contains($0) }
    }

    /// Las palabras que vale la pena aprender de una corrección: no las que ya forman parte del nombre de una partida.
    /// Corregir «seguro coche» de «Seguro vida» a «Transporte» aprende «coche»; si aprendiera «seguro», luego
    /// «seguro vida 37» también iría a Transporte, porque lo aprendido manda sobre el nombre.
    static func learnable(_ note: String, categories: [String]) -> [String] {
        let names = Set(categories.flatMap { MD.fold($0).split { !$0.isLetter }.map(String.init) })
        return keywords(note).filter { !names.contains($0) }
    }

    /// Palabras que convierten el importe en una devolución: entra dinero en la partida en vez de salir.
    /// «abono» no está: «abono transporte 20» es el abono mensual, un gasto.
    private static let refundWords = ["devolucion", "devuelto", "devuelta", "devolvieron", "reembolso", "reintegro"]

    static func parse(_ input: String, categories: [String], people: [String] = [], learned: [String: String] = [:], today: Date = DayKey.today()) -> Result? {
        // La fecha va primero: en «22/10 gasolina 40» o «el 12 pan 3» el número de la fecha no es el importe.
        let dated = NaturalDate.extractKind(input.trimmingCharacters(in: .whitespaces), today: today)
        var rest = dated.text
        // «1.200» son mil doscientos (punto de miles), «12,50» y «12.5» llevan decimales.
        // El número empieza en límite de palabra: en «gym o2 40» el importe es 40, no el 2 de «o2».
        // Sin €, un número con céntimos gana a uno entero: en «2 cafés 3,50» el 2 es cuántos, no cuánto.
        guard let m = rest.firstMatch(of: /\b(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,6}(?:[.,]\d{1,2})?)\s*(?:€|eur(?:os)?\b)/)
                ?? rest.firstMatch(of: /(?:€\s*)?\b(\d{1,3}(?:\.\d{3})+,\d{1,2}|\d{1,6}[.,]\d{1,2})\b(?![.,]\d)/)
                ?? rest.firstMatch(of: /(?:€\s*)?\b(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d{1,6}(?:[.,]\d{1,2})?)/) else { return nil }
        var amount = Money.parse(String(m.1))
        guard amount > 0 else { return nil }
        rest.removeSubrange(m.range)
        rest = rest.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if refundWords.contains(where: { MD.fold(rest).contains($0) }) { amount = -amount }
        rest = rest.replacingOccurrences(of: #"^(?i)(en|de|del|por)\s+"#, with: "", options: .regularExpression)
        let folded = " " + MD.fold(rest).replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression) + " "

        // Primero, palabras del propio nombre de la partida («gym», «transporte»): gana la que más comparte y, a igualdad,
        // la de nombre más corto («seguro vida» va a «Seguro vida», no a «Vivienda (…, seguro)»). Después, las pistas.
        let scored = categories.map { c -> (String, Int, Int) in
            let words = MD.fold(c).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 || $0.contains(where: \.isNumber) }
            return (c, words.filter { folded.contains(" \($0) ") }.count, words.count)
        }.filter { $0.1 > 0 }
        // Lo aprendido de tus correcciones manda sobre todo lo demás (si la partida sigue existiendo).
        var category = keywords(rest).lazy.compactMap { w in learned[w].flatMap { l in categories.first { MD.fold($0) == MD.fold(l) } } }.first
            ?? scored.max { ($0.1, -$0.2) < ($1.1, -$1.2) }?.0
        if category == nil {
            for h in hints where h.words.contains(where: { folded.contains(" \($0) ") }) {
                if let c = categories.first(where: { c in h.partida.contains { MD.fold(c).contains($0) } }) { category = c; break }
            }
        }
        if category == nil { category = categories.first { MD.fold($0).contains("imprevist") } }

        var person: String?
        for p in people where p.count >= 3 {
            let key = MD.fold(p)
            if folded.contains(" \(key) "), let r = rest.range(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: p) + "(?![\\p{L}\\p{N}])",
                                                                options: [.regularExpression, .caseInsensitive, .diacriticInsensitive]) {
                person = p
                rest.replaceSubrange(r, with: "[[\(p)]]")
                break
            }
        }
        return Result(amount: amount, category: category, note: rest, person: person, date: pastDate(dated.date, kind: dated.kind, today: today) ?? today)
    }

    /// Las fechas de las tareas miran al futuro («el viernes» es el próximo); un gasto ya pasó: «el viernes» es el último,
    /// «22/10» es el de este año y «el 20» el de este mes. «mañana», «en 3 días» o un día de los próximos 7 se respetan
    /// (un pago que se apunta por adelantado).
    private static func pastDate(_ d: Date?, kind: NaturalDate.Kind, today: Date) -> Date? {
        guard let d, d > today else { return d }
        let cal = DayKey.calendar()
        switch kind {
        case .weekday:
            return DayKey.adding(days: -7, to: d)
        case .dayMonth where DayKey.days(from: today, to: d) > 7:
            if let back = cal.date(byAdding: .year, value: -1, to: d), back <= today { return back }
        case .dayOfMonth where DayKey.days(from: today, to: d) > 7:
            // El último día con ese número que ya pasó (saltando meses en que no existe, como el 31).
            let day = cal.component(.day, from: d)
            for k in 0...12 {
                guard let m = cal.date(byAdding: .month, value: -k, to: cal.dateInterval(of: .month, for: today)!.start) else { break }
                if let back = DayKey.make(cal.component(.year, from: m), cal.component(.month, from: m), day), back <= today { return back }
            }
        default: break
        }
        return d
    }
}
