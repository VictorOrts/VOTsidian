import Foundation

// MARK: - Peso

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
    var remainingKg: Double? { hasGoal ? last.map { max(0, $0.kg - goalKg) } : nil }
    var progress: Double {
        guard hasGoal, let l = last, initialKg > goalKg else { return 0 }
        return min(1, max(0, (initialKg - l.kg) / (initialKg - goalKg)))
    }

    /// kg por mes entre el primer registro dentro de `window` días y el último.
    func ratePerMonth(window days: Int? = nil) -> Double? {
        guard let l = last else { return nil }
        let pool = days.map { d in records.filter { DayKey.days(from: $0.date, to: l.date) <= d } } ?? records
        guard let f = pool.first, pool.count > 1 else { return nil }
        let span = Double(DayKey.days(from: f.date, to: l.date))
        return span > 0 ? (l.kg - f.kg) / span * 30.4 : nil
    }

    /// Media móvil exponencial por tiempo: cada registro pesa según los días desde el anterior.
    /// Con pesajes espaciados (mensuales) un solo valor atípico no mueve tanto la tendencia.
    func smoothed(halfLifeDays: Double = 30) -> [WeightRecord] {
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
        guard hasGoal, let l = last, let r = ratePerMonth(window: days), r < 0, l.kg > goalKg else { return nil }
        return DayKey.adding(days: Int((l.kg - goalKg) / -r * 30.4), to: l.date)
    }

    /// Fecha estimada de llegada al objetivo sobre la tendencia suavizada: la central usa los últimos 4 meses;
    /// el rango va del ritmo más rápido al más lento entre 2 meses, 4 meses y todo el historial (solo los que bajan).
    func projection() -> WeightProjection? {
        guard hasGoal, let l = last, l.kg > goalKg, records.count > 1 else { return nil }
        var trend = self
        trend.records = smoothed()
        let rates = [60, 120, nil].compactMap { trend.ratePerMonth(window: $0) }.filter { $0 < 0 }
        guard let fast = rates.min(), let slow = rates.max() else { return nil }
        let central = trend.ratePerMonth(window: 120).flatMap { $0 < 0 ? $0 : nil } ?? rates.sorted()[rates.count / 2]
        func date(_ r: Double) -> Date { DayKey.adding(days: Int((l.kg - goalKg) / -r * 30.4), to: l.date) }
        return WeightProjection(date: date(central), earliest: date(fast), latest: date(slow), ratePerMonth: central)
    }
}

// MARK: - Medicación

struct Dose: Identifiable, Equatable {
    var date: Date
    var dose: String
    var site: String
    var note: String
    var line = -1
    var id: Date { date }
    var mg: Double? { MD.number(dose) }
}

struct MedicacionData: Equatable {
    /// Nombre del medicamento («nombre:» en la nota); da nombre a la pantalla y a los avisos.
    var name = "Medicación"
    /// Nombre de las notas de la primera versión, que no llevan «nombre:».
    static let legacyName = "Mounjaro"
    var everyDays = 9
    var doses: [Dose] = []

    var last: Dose? { doses.last }
    var next: Date? { last.map { DayKey.adding(days: everyDays, to: $0.date) } }
    /// Positivo: faltan días. Negativo: atrasado.
    var daysUntilNext: Int? { next.map { DayKey.days(from: DayKey.today(), to: $0) } }

    /// Lado opuesto al de la última inyección, si se anotó.
    var suggestedSite: String {
        let s = MD.fold(last?.site ?? "")
        if s.contains("izq") { return "Abdomen derecho" }
        if s.contains("der") { return "Abdomen izquierdo" }
        return "Abdomen izquierdo"
    }
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
    /// Como `MedicacionData.legacyName`.
    static let legacyName = "Nala"
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
