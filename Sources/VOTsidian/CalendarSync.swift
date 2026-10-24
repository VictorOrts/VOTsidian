import EventKit
import Foundation

// MARK: - Calendar con EventKit: un calendario «VOTsidian» que se mantiene al día solo
//
// Los avisos (`ICSEvent`) se traducen a eventos de EventKit y se sincronizan con un calendario propio: lo nuevo se crea, lo
// que cambió se actualiza y lo que ya no toca se quita, sin duplicados. La app solo lee y cambia ese calendario, nunca los demás.

/// Un aviso ya traducido a lo que entiende EventKit.
struct CalendarEventSpec: Equatable {
    struct Recurrence: Equatable {
        enum Frequency: Equatable { case daily, weekly, monthly, yearly }
        var frequency: Frequency
        var interval = 1
        var until: Date?
        /// 1 = domingo … 7 = sábado, como `EKWeekday`.
        var weekday: Int?
        /// Día del mes; -1 es el último.
        var monthDay: Int?

        /// «FREQ=DAILY;INTERVAL=2;UNTIL=20261231», «FREQ=WEEKLY;BYDAY=SU», «FREQ=MONTHLY;BYMONTHDAY=-1», «FREQ=YEARLY».
        static func parse(_ rule: String) -> Recurrence? {
            var parts: [String: String] = [:]
            for p in rule.split(separator: ";") {
                let kv = p.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { parts[String(kv[0])] = String(kv[1]) }
            }
            let frequency: Frequency
            switch parts["FREQ"] {
            case "DAILY": frequency = .daily
            case "WEEKLY": frequency = .weekly
            case "MONTHLY": frequency = .monthly
            case "YEARLY": frequency = .yearly
            default: return nil
            }
            var r = Recurrence(frequency: frequency)
            r.interval = parts["INTERVAL"].flatMap(Int.init).map { max(1, $0) } ?? 1
            if let u = parts["UNTIL"], u.count >= 8 { r.until = DayKey.date("\(u.prefix(4))-\(u.dropFirst(4).prefix(2))-\(u.dropFirst(6).prefix(2))") }
            r.weekday = parts["BYDAY"].flatMap { ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7][$0] }
            r.monthDay = parts["BYMONTHDAY"].flatMap(Int.init)
            return r
        }
    }

    var uid: String
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var allDay: Bool
    var recurrence: Recurrence?
    /// Segundos respecto al inicio: negativo es antes («-P1D» = un día antes).
    var alarms: [TimeInterval]

    init(_ e: ICSEvent) {
        uid = e.uid
        title = e.title
        notes = e.notes
        allDay = e.minutes == nil
        if let m = e.minutes {
            start = DayKey.calendar().date(bySettingHour: m / 60, minute: m % 60, second: 0, of: e.start) ?? e.start
            end = start.addingTimeInterval(Double(e.duration ?? 15) * 60)   // como el DURATION del .ics
        } else {
            start = e.start
            end = e.start
        }
        recurrence = e.rule.flatMap(Recurrence.parse)
        // Igual que el .ics: de día completo avisa a las 9:00; con hora, a la hora; y los avisos extra («-P30D»…).
        alarms = ([e.minutes == nil ? "PT9H" : "PT0S"] + e.extraTriggers).compactMap(Self.seconds)
    }

    /// «PT9H», «PT0S», «-P30D», «-P1W», «-PT15M» en segundos.
    static func seconds(_ trigger: String) -> TimeInterval? {
        var s = Substring(trigger)
        var sign = 1.0
        if s.hasPrefix("-") { sign = -1; s = s.dropFirst() }
        guard s.hasPrefix("P"), s.count > 1 else { return nil }
        s = s.dropFirst()
        var total = 0.0, number = "", inTime = false
        for c in s {
            if c == "T" { inTime = true; continue }
            if c.isNumber { number.append(c); continue }
            guard let n = Double(number) else { return nil }
            number = ""
            switch (c, inTime) {
            case ("D", false): total += n * 86400
            case ("W", false): total += n * 7 * 86400
            case ("H", true): total += n * 3600
            case ("M", true): total += n * 60
            case ("S", true): total += n
            default: return nil
            }
        }
        return number.isEmpty ? sign * total : nil
    }

    /// Resume lo que se ve en Calendar: si no cambia, no hace falta tocar el evento.
    var fingerprint: String {
        let r = recurrence.map { "\($0.frequency)-\($0.interval)-\($0.until.map { String(Int($0.timeIntervalSince1970)) } ?? "")-\($0.weekday ?? 0)-\($0.monthDay ?? 0)" } ?? ""
        return [title, notes, String(Int(start.timeIntervalSince1970)), String(Int(end.timeIntervalSince1970)), allDay ? "1" : "0", r,
                alarms.map { String(Int($0)) }.joined(separator: ",")].joined(separator: "|")
    }
}

/// Qué hay que crear, actualizar y quitar para que el calendario quede como pide la app.
enum CalendarPlan {
    struct Actions: Equatable {
        var create: [CalendarEventSpec] = []
        var update: [CalendarEventSpec] = []
        /// Identificadores que están en el calendario y ya no tocan.
        var stale: [String] = []
    }

    /// `known`: huella de cada evento en la última sincronización. `present`: identificadores que ya están en el calendario.
    /// Si dos avisos comparten identificador, vale el primero.
    static func diff(desired: [CalendarEventSpec], known: [String: String], present: Set<String>) -> Actions {
        var out = Actions()
        var seen = Set<String>()
        for s in desired where seen.insert(s.uid).inserted {
            if !present.contains(s.uid) { out.create.append(s) }
            else if known[s.uid] != s.fingerprint { out.update.append(s) }
        }
        out.stale = present.subtracting(seen).sorted()
        return out
    }

    /// Un evento suelto que ya pasó se queda como historial; una serie que ya no toca, o uno futuro, se quita.
    static func shouldRemove(start: Date, recurring: Bool, today: Date) -> Bool { recurring || start >= today }
}

@MainActor
enum CalendarSync {
    static let calendarName = "VOTsidian"

    enum Failure: LocalizedError {
        case unavailable, denied, noSource
        var errorDescription: String? {
            switch self {
            case .unavailable: "Solo funciona en la app (build-app.sh), no con swift run."
            case .denied: "macOS no dio acceso a Calendarios. Se cambia en Ajustes del Sistema → Privacidad y seguridad → Calendarios."
            case .noSource: "No se pudo crear el calendario VOTsidian en ninguna de tus cuentas."
            }
        }
    }

    struct Report: Equatable {
        var created = 0
        var updated = 0
        var removed = 0

        var text: String {
            let parts = [created > 0 ? plural(created, "nuevo", "nuevos") : nil, updated > 0 ? plural(updated, "actualizado", "actualizados") : nil,
                         removed > 0 ? plural(removed, "quitado", "quitados") : nil].compactMap { $0 }
            return parts.isEmpty ? "Todo al día." : parts.joined(separator: ", ") + "."
        }
    }

    /// EventKit necesita el permiso declarado en el Info.plist del .app; sin él, macOS cierra la app al pedirlo.
    static var available: Bool {
        Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    private static let idKey = "calendarSyncID", fingerprintsKey = "calendarSyncFingerprints"
    /// Una sincronización a la vez: dos a la vez verían el calendario sin lo que la otra aún no ha guardado y duplicarían eventos.
    private static var running = false
    private static func uid(of e: EKEvent) -> String? { e.url.flatMap { $0.scheme == "votsidian" && $0.host == "aviso" ? $0.lastPathComponent : nil } }

    /// Sincroniza los avisos con el calendario «VOTsidian» (lo crea si falta). Sin `userInitiated`, no quita nada si de pronto
    /// no hay ningún aviso: lo más probable es que las notas aún no se hayan leído (iCloud).
    static func sync(_ events: [ICSEvent], today: Date = DayKey.today(), userInitiated: Bool = true) async throws -> Report {
        guard available else { throw Failure.unavailable }
        while running { try await Task.sleep(for: .milliseconds(200)) }
        running = true
        defer { running = false }
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw Failure.denied }
        let calendar = try targetCalendar(store)
        let defaults = UserDefaults.standard
        let known = defaults.dictionary(forKey: fingerprintsKey) as? [String: String] ?? [:]

        // Lo que ya hay: una entrada por aviso. De una serie, el primer evento; si hay series repetidas del mismo aviso, sobran.
        let range = store.predicateForEvents(withStart: DayKey.adding(days: -366, to: today), end: DayKey.adding(days: 3 * 365 - 10, to: today), calendars: [calendar])   // EventKit admite como mucho 4 años
        var present: [String: EKEvent] = [:]
        var extras: [EKEvent] = []
        var seenIDs = Set<String>()
        for occurrence in store.events(matching: range) {
            guard let uid = uid(of: occurrence) else { continue }
            let e = occurrence.hasRecurrenceRules ? (occurrence.eventIdentifier.flatMap { store.event(withIdentifier: $0) } ?? occurrence) : occurrence
            guard seenIDs.insert(e.eventIdentifier ?? "\(uid)-\(e.startDate.timeIntervalSince1970)").inserted else { continue }
            if present[uid] == nil { present[uid] = e } else { extras.append(e) }
        }

        let desired = events.map(CalendarEventSpec.init)
        var actions = CalendarPlan.diff(desired: desired, known: known, present: Set(present.keys))
        if desired.isEmpty, !present.isEmpty, !userInitiated { actions.stale = [] }

        var report = Report()
        var fingerprints = known.filter { present[$0.key] != nil }
        for s in actions.create {
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            e.url = URL(string: "votsidian://aviso/\(s.uid)")
            fill(e, s)
            try store.save(e, span: .thisEvent, commit: false)
            report.created += 1
        }
        for s in actions.update {
            guard let e = present[s.uid] else { continue }
            fill(e, s)
            try store.save(e, span: .futureEvents, commit: false)
            report.updated += 1
        }
        for uid in actions.stale {
            guard let e = present[uid], CalendarPlan.shouldRemove(start: e.startDate, recurring: e.hasRecurrenceRules, today: today) else { continue }
            try store.remove(e, span: .futureEvents, commit: false)
            fingerprints[uid] = nil
            report.removed += 1
        }
        for e in extras {
            try store.remove(e, span: .futureEvents, commit: false)
            report.removed += 1
        }
        try store.commit()
        for s in desired { fingerprints[s.uid] = s.fingerprint }
        defaults.set(fingerprints, forKey: fingerprintsKey)
        return report
    }

    /// Borra el calendario «VOTsidian» con todo lo que tiene (la app lo vuelve a crear si sigues sincronizando).
    static func removeCalendar() async throws {
        guard available else { throw Failure.unavailable }
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw Failure.denied }
        if let id = UserDefaults.standard.string(forKey: idKey), let c = store.calendar(withIdentifier: id) { try store.removeCalendar(c, commit: true) }
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: fingerprintsKey)
    }

    private static func targetCalendar(_ store: EKEventStore) throws -> EKCalendar {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: idKey), let c = store.calendar(withIdentifier: id), c.allowsContentModifications { return c }
        if let c = store.calendars(for: .event).first(where: { $0.title == calendarName && $0.allowsContentModifications }) {
            defaults.set(c.calendarIdentifier, forKey: idKey)
            return c
        }
        // La cuenta del calendario por defecto (iCloud, normalmente: así sale también en el iPhone); si no deja, la local.
        let sources = [store.defaultCalendarForNewEvents?.source].compactMap { $0 } + store.sources.filter { $0.sourceType == .local }
        for source in sources {
            let c = EKCalendar(for: .event, eventStore: store)
            c.title = calendarName
            c.cgColor = CGColor(red: 0.16, green: 0.62, blue: 0.50, alpha: 1)
            c.source = source
            if (try? store.saveCalendar(c, commit: true)) != nil {
                defaults.set(c.calendarIdentifier, forKey: idKey)
                return c
            }
        }
        throw Failure.noSource
    }

    private static func fill(_ e: EKEvent, _ s: CalendarEventSpec) {
        e.title = s.title
        e.notes = s.notes
        e.isAllDay = s.allDay
        e.startDate = s.start
        e.endDate = s.end
        e.alarms?.forEach { e.removeAlarm($0) }
        for a in s.alarms { e.addAlarm(EKAlarm(relativeOffset: a)) }
        e.recurrenceRules?.forEach { e.removeRecurrenceRule($0) }
        if let r = s.recurrence { e.addRecurrenceRule(rule(r)) }
    }

    private static func rule(_ r: CalendarEventSpec.Recurrence) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch r.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: r.interval,
                                daysOfTheWeek: r.weekday.flatMap(EKWeekday.init(rawValue:)).map { [EKRecurrenceDayOfWeek($0)] },
                                daysOfTheMonth: r.monthDay.map { [NSNumber(value: $0)] }, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                daysOfTheYear: nil, setPositions: nil, end: r.until.map { EKRecurrenceEnd(end: $0) })
    }
}

extension Store {
    /// Con la sincronización activada en Avisos, deja el calendario «VOTsidian» como piden las notas. Sin `force` espera unos
    /// segundos, por si siguen llegando cambios, y junta varias llamadas en una.
    func refreshCalendarSync(force: Bool = false) {
        guard persistsModules, UserDefaults.standard.bool(forKey: "calendarSync"), CalendarSync.available else { return }
        calendarSyncTask?.cancel()
        calendarSyncTask = Task { @MainActor [weak self] in
            if !force {
                try? await Task.sleep(for: .seconds(8))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            let events = ICS.events(reminderSources(), plan: reminderPlan())
            let status: String
            do {
                status = try await CalendarSync.sync(events, userInitiated: false).text
                Log.calendar.info("Calendario VOTsidian al día: \(status, privacy: .public)")
            } catch {
                status = error.localizedDescription
                Log.calendar.error("No se pudo sincronizar con Calendar: \(status, privacy: .public)")
            }
            UserDefaults.standard.set("\(Store.stamp("d/M HH:mm")): \(status)", forKey: "calendarSyncStatus")
        }
    }
}
