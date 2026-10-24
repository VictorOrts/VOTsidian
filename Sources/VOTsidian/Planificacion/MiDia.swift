import Foundation

// MARK: - Mi día: el día por horas
//
// Las tareas con hora (`⏰`) son bloques; su altura sale de la duración (`⏱`, 30 minutos si no la tienen). Las citas y las
// tomas de medicación con hora salen como bloques fijos. Lo que tiene fecha de ese día y no tiene hora queda en «Sin hora»,
// para arrastrarlo a una franja. Todo se guarda en la línea de la tarea: no hay otro sitio donde viva el plan del día.

/// Un bloque de la agenda por horas.
struct TimeBlock: Identifiable, Equatable {
    enum Source: Equatable { case task, appointment, medication, other }
    var id: String
    var title: String
    var detail = ""
    /// Minutos desde medianoche.
    var start: Int
    var duration: Int
    var source: Source
    var kind: AgendaItem.Kind
    var task: TaskItem? = nil
    var done = false
    var screen: Screen? = nil
    var path: String? = nil
    var end: Int { start + duration }
    /// Solo las tareas se mueven y se estiran: el resto viene de otras notas (una cita, una pauta de medicación).
    var movable: Bool { task != nil && !done }
    /// Lo que cuenta para la jornada: tareas y citas sin hacer, no la medicación.
    var counts: Bool { !done && (source == .task || source == .appointment) }

    static func == (a: TimeBlock, b: TimeBlock) -> Bool {
        a.id == b.id && a.title == b.title && a.start == b.start && a.duration == b.duration && a.done == b.done && a.task == b.task
    }
}

struct DayPlan: Equatable {
    /// Duración de una tarea con hora que no dice cuánto dura.
    static let defaultDuration = 30
    /// La medicación ocupa poco; se pinta como una franja fina.
    static let medicationDuration = 15

    var day: Date
    var blocks: [TimeBlock] = []
    /// Tareas de ese día (y, si es hoy, las vencidas) sin hora: lo que falta por repartir.
    var unscheduled: [TaskItem] = []

    /// Minutos de tareas y citas pendientes con hora, más lo calculado de las que aún no la tienen.
    var plannedMinutes: Int { blocks.filter(\.counts).reduce(0) { $0 + $1.duration } + unscheduled.reduce(0) { $0 + ($1.duration ?? 0) } }
    /// Tareas sin hora y sin duración: no se sabe cuánto pesan en el día.
    var unestimated: Int { unscheduled.filter { $0.duration == nil }.count }

    /// `agenda`: lo del día según el Calendario (ya sin módulos ocultos). `meds`: tomas con hora de ese día.
    static func build(day: Date, today: Date = DayKey.today(), tasks: [TaskItem], agenda: [AgendaItem], meds: [(id: String, title: String, minutes: Int)] = []) -> DayPlan {
        var plan = DayPlan(day: day)
        for t in tasks {
            guard let due = t.due else { continue }
            if let m = t.time, due == day {
                let medical = t.file == VaultPath.medico
                plan.blocks.append(TimeBlock(id: "t\(t.id)", title: t.text, detail: t.noteName, start: m, duration: t.duration ?? defaultDuration,
                                             source: medical ? .appointment : .task, kind: medical ? .appointment : .task, task: t, done: t.done, screen: medical ? .salud : nil))
            } else if !t.done, t.time == nil || due < day, due == day || (day == today && due < today) {
                plan.unscheduled.append(t)
            }
        }
        // Lo que no es una tarea (citas en notas propias, eventos con hora…): fijo, con la hora que trae.
        for item in agenda where item.task == nil {
            guard let m = item.minutes else { continue }
            plan.blocks.append(TimeBlock(id: item.id, title: item.title, detail: item.detail, start: m, duration: defaultDuration,
                                         source: item.kind == .appointment ? .appointment : .other, kind: item.kind, screen: item.screen, path: item.path))
        }
        for med in meds {
            plan.blocks.append(TimeBlock(id: "med\(med.id)|\(med.minutes)", title: med.title, start: med.minutes, duration: medicationDuration,
                                         source: .medication, kind: .dose, screen: .medicacion))
        }
        // Ids únicos: una pauta con la misma hora dos veces, o dos elementos con el mismo id, romperían el `ForEach`.
        var seen: [String: Int] = [:]
        for i in plan.blocks.indices {
            let n = seen[plan.blocks[i].id, default: 0]
            seen[plan.blocks[i].id] = n + 1
            if n > 0 { plan.blocks[i].id += "#\(n)" }
        }
        plan.blocks.sort { ($0.start, $0.id) < ($1.start, $1.id) }
        // Vencidas primero; dentro, por prioridad.
        plan.unscheduled.sort { a, b in
            let da = a.due ?? day, db = b.due ?? day
            return da != db ? da < db : a.priority != b.priority ? a.priority > b.priority : a.line < b.line
        }
        return plan
    }

    /// Columna de cada bloque cuando se solapan: los que coinciden en el tiempo se reparten el ancho, como en Calendar.
    static func columns(_ blocks: [TimeBlock]) -> [String: (column: Int, of: Int)] {
        var out: [String: (Int, Int)] = [:]
        var group: [(id: String, column: Int)] = []
        var colEnds: [Int] = []
        var groupEnd = Int.min
        func flush() {
            for g in group { out[g.id] = (g.column, colEnds.count) }
            group = []; colEnds = []
        }
        for b in blocks.sorted(by: { ($0.start, -$0.duration, $0.id) < ($1.start, -$1.duration, $1.id) }) {
            if b.start >= groupEnd { flush() }
            let col = colEnds.firstIndex { $0 <= b.start } ?? colEnds.count
            if col == colEnds.count { colEnds.append(b.end) } else { colEnds[col] = b.end }
            group.append((b.id, col))
            groupEnd = max(groupEnd, b.end)
        }
        flush()
        return out
    }

    /// Coloca las tareas sin hora en los huecos libres entre `from` y `until` (minutos), por orden y sin pisar nada, en
    /// múltiplos de 15 minutos. Las que no caben se quedan sin hora.
    static func autoSchedule(_ tasks: [TaskItem], around blocks: [TimeBlock], from: Int, until: Int) -> [(task: TaskItem, start: Int)] {
        var busy = blocks.filter { !$0.done }.map { ($0.start, $0.end) }
        var out: [(TaskItem, Int)] = []
        for t in tasks {
            let length = t.duration ?? defaultDuration
            var start = (from + 14) / 15 * 15
            while start + length <= until {
                if let clash = busy.filter({ $0.0 < start + length && start < $0.1 }).map(\.1).max() {
                    start = (clash + 14) / 15 * 15
                } else {
                    out.append((t, start))
                    busy.append((start, start + length))
                    break
                }
            }
        }
        return out
    }

    /// Minuto de la franja de 15 minutos más cercana, dentro del día.
    static func snap(_ minutes: Double, step: Int = 15) -> Int {
        min(24 * 60 - step, max(0, Int((minutes / Double(step)).rounded()) * step))
    }
}

extension Store {
    /// El plan de un día. `agenda`: lo que ya sacó el Calendario para ese día (así la semana lo pide una sola vez).
    func dayPlan(_ day: Date, agenda: [AgendaItem]? = nil) -> DayPlan {
        let items = agenda ?? (self.agenda(from: day, to: day)[DayKey.string(day)] ?? [])
        return DayPlan.build(day: day, tasks: tasks, agenda: items, meds: medicationTimes(on: day))
    }

    /// Tomas con hora de un día: las diarias, y las periódicas el día que tocan.
    func medicationTimes(on day: Date) -> [(id: String, title: String, minutes: Int)] {
        guard isVisible(.medicacion) else { return [] }
        var out: [(String, String, Int)] = []
        for m in medicacion.active(on: day) where !m.asNeeded && !m.times.isEmpty {
            guard m.every == 1 || medicacion.next(of: m) == day else { continue }
            for t in m.times { if let mi = Medication.minutes(t) { out.append(("\(m.line)", (m.isInjection ? "Pinchazo " : "Tomar ") + m.name, mi)) } }
        }
        return out
    }

    /// Pone la tarea en `day` a la hora `minutes` (o le quita la hora con `nil`).
    func schedule(_ t: TaskItem, on day: Date, at minutes: Int?) {
        edit(t.file) { Edit.updateTask($0, task: t, newText: t.text, due: day, time: .some(minutes)) }
    }

    func setDuration(_ t: TaskItem, _ minutes: Int?) {
        edit(t.file) { Edit.updateTask($0, task: t, newText: t.text, due: t.due, duration: .some(minutes)) }
    }

    /// Reparte las tareas sin hora en los huecos del día, en un solo cambio que se deshace de una vez. Devuelve cuántas colocó.
    @discardableResult
    func autoSchedule(_ plan: DayPlan, from: Int, until: Int) -> Int {
        let placed = DayPlan.autoSchedule(plan.unscheduled, around: plan.blocks, from: from, until: until)
        guard !placed.isEmpty else { return 0 }
        grouped {
            // Por nota, de abajo arriba no hace falta: cada cambio busca su línea por el texto (`MD.index`), no por la posición.
            for p in placed { schedule(p.task, on: plan.day, at: p.start) }
        }
        return placed.count
    }
}
