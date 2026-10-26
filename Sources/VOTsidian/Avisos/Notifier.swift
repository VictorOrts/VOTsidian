import Foundation
import UserNotifications

struct PlannedNotification: Equatable {
    var id: String
    var title: String
    var body: String
    var fire: Date
}

/// Convierte los eventos de avisos en notificaciones del sistema para los próximos días.
enum Notifier {
    static let horizonDays = 30
    static let maxPending = 60
    static let defaultMinutes = 9 * 60

    private static func occurrences(of e: ICSEvent, from today: Date, horizon: Int) -> [Date] {
        var end = DayKey.adding(days: horizon, to: today)
        var days: [Date] = []
        let cal = DayKey.calendar()
        let rule = e.rule ?? ""
        // «UNTIL=AAAAMMDD»: un tratamiento que acaba deja de avisar ese día.
        if let m = rule.firstMatch(of: /UNTIL=([0-9]{4})([0-9]{2})([0-9]{2})/), let until = DayKey.date("\(m.1)-\(m.2)-\(m.3)") { end = min(end, until) }
        if rule.hasPrefix("FREQ=DAILY") || rule.hasPrefix("FREQ=WEEKLY") {
            // «INTERVAL» cuenta semanas en FREQ=WEEKLY y días en FREQ=DAILY.
            let unit = rule.hasPrefix("FREQ=WEEKLY") ? 7 : 1
            var step = unit
            if let r = rule.range(of: "INTERVAL="), let n = Int(rule[r.upperBound...].prefix { ("0"..."9").contains($0) }), n > 0, n <= 3660 { step = n * unit }
            var d = e.start
            while d < today { d = DayKey.adding(days: step, to: d) }
            while d <= end { days.append(d); d = DayKey.adding(days: step, to: d) }
        } else if rule.contains("FREQ=MONTHLY") {
            var month = cal.dateInterval(of: .month, for: today)!.start
            for _ in 0...(horizon / 28 + 1) {
                let next = cal.date(byAdding: .month, value: 1, to: month)!
                let last = DayKey.adding(days: -1, to: next)
                if last >= today, last <= end { days.append(last) }
                month = next
            }
        } else if e.start >= today, e.start <= end {
            days.append(e.start)
        }
        return days
    }

    private static func offsetDays(_ trigger: String) -> Int? {
        guard trigger.hasPrefix("-P"), trigger.hasSuffix("D"), let n = Int(trigger.dropFirst(2).dropLast()) else { return nil }
        return n
    }

    static func plan(_ events: [ICSEvent], now: Date = Date(), today: Date = DayKey.today()) -> [PlannedNotification] {
        let cal = DayKey.calendar()
        func at(_ day: Date, _ minutes: Int) -> Date {
            cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
        }
        var out: [PlannedNotification] = []
        for e in events {
            let minutes = e.minutes ?? defaultMinutes
            for day in occurrences(of: e, from: today, horizon: horizonDays) {
                out.append(PlannedNotification(id: "\(e.uid)-\(DayKey.string(day))", title: e.title, body: e.notes, fire: at(day, minutes)))
                for t in e.extraTriggers {
                    // «-PT1H»: tanto antes de la hora del evento («Dentro de 1 h»).
                    if offsetDays(t) == nil, e.minutes != nil, let secs = CalendarEventSpec.seconds(t), secs < 0 {
                        let mins = Int(-secs / 60)
                        out.append(PlannedNotification(id: "\(e.uid)-\(DayKey.string(day))-\(t)", title: e.title,
                                                       body: (mins % 60 == 0 ? "Dentro de \(mins / 60) h. " : "Dentro de \(mins) min. ") + e.notes,
                                                       fire: at(day, minutes).addingTimeInterval(secs)))
                        continue
                    }
                    guard let n = offsetDays(t) else { continue }
                    let early = DayKey.adding(days: -n, to: day)
                    guard early >= today else { continue }
                    out.append(PlannedNotification(id: "\(e.uid)-\(DayKey.string(day))-\(t)", title: e.title,
                                                   body: (n == 1 ? "Mañana. " : "En \(n) días. ") + e.notes, fire: at(early, defaultMinutes)))
                }
            }
        }
        return out.filter { $0.fire > now }.sorted { $0.fire < $1.fire }.prefix(maxPending).map { $0 }
    }

    /// `UNUserNotificationCenter` solo funciona dentro de un .app, no con `swift run`.
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    @MainActor
    static func schedule(_ events: [ICSEvent]) async -> Int? {
        guard available else { return nil }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return nil }
        center.removeAllPendingNotificationRequests()
        let cal = DayKey.calendar()
        let planned = plan(events)
        for p in planned {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            do { try await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)) }
            catch { Log.notifications.error("macOS rechazó una notificación: \(error.localizedDescription, privacy: .public)") }
        }
        return planned.count
    }

    static func cancelAll() {
        guard available else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
