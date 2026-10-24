import Foundation

// MARK: - Peso

/// Como mucho `limit` puntos repartidos por igual, siempre con el primero y el último: una gráfica de mil pesajes se ve igual
/// con unos cientos, y se dibuja mucho más deprisa.
func thinned<T>(_ items: [T], to limit: Int) -> [T] {
    guard items.count > limit, limit > 1 else { return items }
    let step = Double(items.count - 1) / Double(limit - 1)
    return (0..<limit).map { items[Int((Double($0) * step).rounded())] }
}

/// Como `thinned`, pero en cada tramo se queda con el pesaje más bajo y el más alto: un pico de un solo día no desaparece
/// de la gráfica al dibujar menos puntos.
func thinnedKeepingExtremes(_ records: [WeightRecord], to limit: Int) -> [WeightRecord] {
    guard records.count > limit, limit >= 4 else { return records }
    let buckets = (limit - 2) / 2
    let inner = records.dropFirst().dropLast()
    let size = Double(inner.count) / Double(buckets)
    var out = [records[0]]
    for b in 0..<buckets {
        let lo = inner.startIndex + Int((Double(b) * size).rounded(.down))
        let hi = min(inner.endIndex, inner.startIndex + Int((Double(b + 1) * size).rounded(.down)))
        guard lo < hi else { continue }
        let slice = records[lo..<hi]
        let low = slice.min { $0.kg < $1.kg }!, high = slice.max { $0.kg < $1.kg }!
        out += low.date <= high.date ? (low.id == high.id ? [low] : [low, high]) : [high, low]
    }
    out.append(records[records.count - 1])
    return out
}

struct WeightRecord: Identifiable, Equatable {
    var date: Date
    var kg: Double
    var note: String
    var line = -1
    var id: Date { date }
}

struct WeightProjection: Equatable {
    var date: Date
    var earliest: Date
    var latest: Date
    var ratePerMonth: Double
}

struct WeightData: Equatable {
    var initialKg = 0.0
    var goalKg = 0.0
    var start: Date?
    var records: [WeightRecord] = []

    var last: WeightRecord? { records.last }
    var previous: WeightRecord? { records.count > 1 ? records[records.count - 2] : nil }
    var lostKg: Double? { last.map { initialKg - $0.kg } }
    /// Sin `objetivo_peso_kg` en la nota no hay meta: nada de «faltan», progreso ni fecha de llegada.
    var hasGoal: Bool { goalKg > 0 }
    /// El objetivo está por encima del peso de partida: se quiere subir (ganar músculo, recuperar peso), no bajar.
    var gaining: Bool { hasGoal && goalKg > initialKg }
    /// Lo avanzado desde el principio, en la dirección del objetivo (positivo = bien).
    var achievedKg: Double? { last.map { gaining ? $0.kg - initialKg : initialKg - $0.kg } }
    /// «perdidos» o «ganados», para acompañar a `achievedKg`.
    var achievedWord: String { gaining ? "ganados" : "perdidos" }
    /// Un cambio de peso va en la buena dirección (bajar si se quiere bajar; subir si se quiere subir).
    func isGood(_ delta: Double) -> Bool { gaining ? delta >= 0 : delta <= 0 }
    var remainingKg: Double? { hasGoal ? last.map { gaining ? max(0, goalKg - $0.kg) : max(0, $0.kg - goalKg) } : nil }
    var progress: Double {
        guard hasGoal, let l = last, initialKg != goalKg else { return 0 }
        return min(1, max(0, (l.kg - initialKg) / (goalKg - initialKg)))
    }

    /// kg por mes entre el primer registro dentro de `window` días y el último.
    func ratePerMonth(window days: Int? = nil) -> Double? {
        guard let l = last else { return nil }
        let pool = days.map { d in records.filter { DayKey.days(from: $0.date, to: l.date) <= d } } ?? records
        guard let f = pool.first, pool.count > 1 else { return nil }
        let span = Double(DayKey.days(from: f.date, to: l.date))
        return span > 0 ? (l.kg - f.kg) / span * 30.4 : nil
    }

    /// La tendencia (media de 30 días) calculada una vez al leer la nota: la pantalla la pide varias veces al pintarse.
    var trendCache: [WeightRecord]?

    /// Media móvil exponencial por tiempo: cada registro pesa según los días desde el anterior.
    /// Con pesajes espaciados (mensuales) un solo valor atípico no mueve tanto la tendencia.
    func smoothed(halfLifeDays: Double = 30) -> [WeightRecord] {
        if halfLifeDays == 30, let c = trendCache, c.count == records.count { return c }
        guard var cur = records.first?.kg else { return [] }
        var out: [WeightRecord] = []
        for (i, r) in records.enumerated() {
            if i > 0 {
                let gap = Double(max(1, DayKey.days(from: records[i - 1].date, to: r.date)))
                let a = 1 - pow(0.5, gap / halfLifeDays)
                cur += a * (r.kg - cur)
            }
            var s = r
            s.kg = cur
            out.append(s)
        }
        return out
    }

    func projectedGoalDate(window days: Int? = 120) -> Date? {
        guard hasGoal, let l = last, let r = ratePerMonth(window: days), isGood(r), r != 0, (remainingKg ?? 0) > 0 else { return nil }
        return DayKey.adding(days: Int(abs(goalKg - l.kg) / abs(r) * 30.4), to: l.date)
    }

    /// Fecha estimada de llegada al objetivo sobre la tendencia suavizada: la central usa los últimos 4 meses;
    /// el rango va del ritmo más rápido al más lento entre 2 meses, 4 meses y todo el historial (solo los que van hacia
    /// el objetivo: bajando si se quiere bajar, subiendo si se quiere subir).
    func projection() -> WeightProjection? {
        guard hasGoal, let l = last, (remainingKg ?? 0) > 0, records.count > 1 else { return nil }
        var trend = self
        trend.records = smoothed()
        let rates = [60, 120, nil].compactMap { trend.ratePerMonth(window: $0) }.filter { $0 != 0 && isGood($0) }
        guard let fast = rates.max(by: { abs($0) < abs($1) }), let slow = rates.min(by: { abs($0) < abs($1) }) else { return nil }
        let central = trend.ratePerMonth(window: 120).flatMap { $0 != 0 && isGood($0) ? $0 : nil } ?? rates.sorted()[rates.count / 2]
        func date(_ r: Double) -> Date { DayKey.adding(days: Int(abs(goalKg - l.kg) / abs(r) * 30.4), to: l.date) }
        return WeightProjection(date: date(central), earliest: date(fast), latest: date(slow), ratePerMonth: central)
    }
}

// MARK: - Medicación

/// Una toma o un pinchazo del registro de medicación.
struct Dose: Identifiable, Equatable {
    var date: Date
    var dose: String
    var site: String
    var note: String
    var line = -1
    /// Medicamento de la toma (en las notas de antes, el único que había).
    var med = ""
    /// La línea tal cual, para borrarla aunque la tabla haya cambiado.
    var raw = ""
    var id: String { "\(line)|\(DayKey.string(date))" }
    var mg: Double? { MD.number(dose) }
}

// MARK: - Mascota

struct MascotaVisit: Identifiable, Equatable {
    var date: Date
    var tipo: String
    var detalle: String
    var proxima: Date?
    var coste: String
    var line = -1
    var id: String { DayKey.string(date) + tipo + String(line) }
}

struct MascotaData: Equatable {
    var name = "Mascota"
    var birth: Date?
    var food = ""
    var visits: [MascotaVisit] = []

    var upcoming: [(date: Date, title: String)] {
        visits.compactMap { v in v.proxima.map { ($0, v.tipo.isEmpty ? (v.detalle.isEmpty ? "Revisión" : v.detalle) : v.tipo) } }
            .filter { $0.0 >= DayKey.today() }.sorted { $0.0 < $1.0 }
    }

    var overdue: [(date: Date, title: String)] {
        visits.compactMap { v -> (Date, String)? in
            guard let p = v.proxima, p < DayKey.today() else { return nil }
            let done = visits.contains { $0.tipo == v.tipo && $0.date >= p }
            return done ? nil : (p, v.tipo.isEmpty ? "Revisión" : v.tipo)
        }
    }

    var ageText: String? {
        guard let b = birth else { return nil }
        let c = DayKey.calendar().dateComponents([.year, .month], from: b, to: Date())
        return "\(c.year ?? 0) años y \(c.month ?? 0) meses"
    }
}

// MARK: - Tareas

struct TaskItem: Identifiable, Equatable {
    var file: String
    var line: Int
    var raw: String
    var text: String
    var due: Date?
    var scheduled: Date?
    var done: Bool
    var completed: Date? = nil
    var recurrence: String? = nil
    var priority = 0   // 3 alta ⏫ · 2 media 🔼 · 1 baja 🔽
    /// Hora (minutos desde medianoche), escrita como `⏰ 17:30` detrás de la fecha. Sin ella, es de día completo.
    var time: Int? = nil
    var id: String { "\(file):\(line)" }
    var noteName: String { (file as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "") }
}

// MARK: - Revisión semanal

struct HabitDef: Equatable, Identifiable {
    var name: String
    var criterion = ""
    var id: String { name }
}

struct HabitWeek: Equatable {
    var name: String
    var days: [Bool]
    var criterion = ""
    var count: Int { days.filter { $0 }.count }
}

struct WeekReview: Equatable {
    var key: String
    var exists = false
    var habits: [HabitWeek] = []
    var logros = ""
    var noSalio = ""
    var objetivos = ["", "", ""]
    var fechas: [String] = []

    var totalDone: Int { habits.reduce(0) { $0 + $1.count } }
    var totalPossible: Int { habits.count * 7 }
}

// MARK: - Plan nutricional y proyecto

struct PlanData: Equatable {
    var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
    var meals: [[String]] = []
    var mealLines: [Int] = []
}

struct Milestone: Identifiable, Equatable {
    var name: String
    var kg: Double
    var markedDone: Bool
    var line = -1
    var id: String { name }
}
