import AppKit
import Foundation

struct ReminderPlan: Equatable {
    var mounjaro = true
    var mounjaroMinutes = 9 * 60
    var review = true
    var reviewWeekday = 1 // 1 = domingo (Calendar gregoriano)
    var reviewMinutes = 19 * 60
    var monthlyWeight = true
    var weightMinutes = 9 * 60
    var tasks = true
    var nala = true
    var birthdays = true
    var documents = true
    var events = true
    var payments = true

    /// El plan guardado en Avisos (mismas claves y valores por defecto que `RemindersView`).
    static var stored: ReminderPlan {
        let d = UserDefaults.standard
        func flag(_ k: String) -> Bool { d.object(forKey: k) as? Bool ?? true }
        func int(_ k: String, _ v: Int) -> Int { d.object(forKey: k) as? Int ?? v }
        return ReminderPlan(mounjaro: flag("remMounjaro"), mounjaroMinutes: int("remMounjaroMin", 540),
                            review: flag("remReview"), reviewWeekday: int("remReviewDay", 1), reviewMinutes: int("remReviewMin", 1140),
                            monthlyWeight: flag("remWeight"), weightMinutes: int("remWeightMin", 540),
                            tasks: flag("remTasks"), nala: flag("remNala"), birthdays: flag("remBirthdays"),
                            documents: flag("remDocs"), events: flag("remEvents"), payments: flag("remPayments"))
    }
}

struct ReminderSources {
    var mounjaro = MounjaroData()
    var tasks: [TaskItem] = []
    var nala = NalaData()
    var people: [Person] = []
    var documents: [(name: String, date: Date)] = []
    var events: [(name: String, date: Date)] = []
    var payments: [(name: String, date: Date, amount: Double, saving: Bool)] = []
}

struct ICSEvent: Equatable, Identifiable {
    var uid: String
    var title: String
    var notes: String
    var start: Date
    var minutes: Int?   // nil = evento de día completo
    var rule: String?
    var extraTriggers: [String] = []
    var id: String { uid }
}

enum ICS {
    private static func fmtDate(_ d: Date) -> String { DayKey.string(d).replacingOccurrences(of: "-", with: "") }

    private static func fmtDateTime(_ d: Date, minutes: Int) -> String {
        String(format: "%@T%02d%02d00", fmtDate(d), minutes / 60, minutes % 60)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }

    static func stableID(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
        return String(h, radix: 16)
    }

    static func events(_ src: ReminderSources, plan: ReminderPlan, today: Date = DayKey.today()) -> [ICSEvent] {
        let cal = DayKey.calendar()
        let mounjaro = src.mounjaro, tasks = src.tasks, nala = src.nala
        var out: [ICSEvent] = []

        if plan.mounjaro, let next = mounjaro.next {
            out.append(ICSEvent(uid: "mounjaro", title: "Pinchazo Mounjaro",
                                notes: "Anótalo en Cambio físico/Mounjaro. Se repite cada \(mounjaro.everyDays) días desde el último registro.",
                                start: max(next, today), minutes: plan.mounjaroMinutes, rule: "FREQ=DAILY;INTERVAL=\(mounjaro.everyDays)"))
        }
        if plan.review {
            let delta = (plan.reviewWeekday - cal.component(.weekday, from: today) + 7) % 7
            let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            out.append(ICSEvent(uid: "revision-semanal", title: "Revisión semanal",
                                notes: "Marca hábitos, logros y tres objetivos de la semana.",
                                start: DayKey.adding(days: delta, to: today), minutes: plan.reviewMinutes,
                                rule: "FREQ=WEEKLY;BYDAY=\(codes[plan.reviewWeekday - 1])"))
        }
        if plan.monthlyWeight {
            let first = cal.dateInterval(of: .month, for: today)!.start
            let end = DayKey.adding(days: -1, to: cal.date(byAdding: .month, value: 1, to: first)!)
            out.append(ICSEvent(uid: "peso-mensual", title: "Pesaje mensual",
                                notes: "En ayunas. Anótalo en Cambio físico/Peso.",
                                start: end, minutes: plan.weightMinutes, rule: "FREQ=MONTHLY;BYMONTHDAY=-1"))
        }
        if plan.tasks {
            for t in tasks where !t.done {
                guard let due = t.due, due >= today else { continue }
                out.append(ICSEvent(uid: "tarea-" + stableID(t.text + DayKey.string(due)), title: t.text,
                                    notes: "Tarea en la nota \(t.noteName).", start: due, minutes: nil, rule: nil))
            }
        }
        if plan.nala {
            for u in nala.upcoming {
                out.append(ICSEvent(uid: "nala-" + stableID(u.title + DayKey.string(u.date)), title: "\(nala.name): \(u.title)",
                                    notes: "Cita o revisión de \(nala.name).", start: u.date, minutes: nil, rule: nil))
            }
        }
        if plan.birthdays {
            for p in src.people {
                guard let b = p.nextBirthday(from: today) else { continue }
                out.append(ICSEvent(uid: "cumple-" + stableID(p.name), title: "Cumpleaños de \(p.name)",
                                    notes: b.age.map { "Cumple \($0) años." } ?? "", start: b.date, minutes: nil, rule: "FREQ=YEARLY"))
            }
        }
        if plan.documents {
            for d in src.documents where d.date >= today {
                out.append(ICSEvent(uid: "doc-" + stableID(d.name + DayKey.string(d.date)), title: "Caduca: \(d.name)",
                                    notes: "Documento en la nota Documentos.", start: d.date, minutes: nil, rule: nil, extraTriggers: ["-P30D"]))
            }
        }
        if plan.events {
            for e in src.events where e.date >= today {
                out.append(ICSEvent(uid: "evento-" + stableID(e.name + DayKey.string(e.date)), title: e.name,
                                    notes: "Evento en VOTsidian.", start: e.date, minutes: nil, rule: nil, extraTriggers: ["-P7D"]))
            }
        }
        if plan.payments {
            for p in src.payments where p.date >= today {
                out.append(ICSEvent(uid: "pago-" + stableID(p.name + DayKey.string(p.date)), title: "\(p.saving ? "Apartar" : "Pagar"): \(p.name) (\(Money.format(p.amount)))",
                                    notes: p.saving ? "Ahorro del mes en Gastos. Márcalo en VOTsidian al apartarlo." : "Pago fijo de Gastos. Márcalo como pagado en VOTsidian.",
                                    start: p.date, minutes: nil, rule: nil, extraTriggers: ["-P1D"]))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func build(_ events: [ICSEvent]) -> String {
        var out = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//VOTsidian//ES", "CALSCALE:GREGORIAN"]
        let stamp = fmtDateTime(Date(), minutes: 0)
        for e in events {
            out += ["BEGIN:VEVENT", "UID:\(e.uid)@votsidian", "DTSTAMP:\(stamp)"]
            if let m = e.minutes { out += ["DTSTART:\(fmtDateTime(e.start, minutes: m))", "DURATION:PT15M"] }
            else { out.append("DTSTART;VALUE=DATE:\(fmtDate(e.start))") }
            if let r = e.rule { out.append("RRULE:\(r)") }
            out += ["SUMMARY:\(escape(e.title))", "DESCRIPTION:\(escape(e.notes))",
                    "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(e.title))",
                    e.minutes == nil ? "TRIGGER:PT9H" : "TRIGGER:PT0S", "END:VALARM"]
            for t in e.extraTriggers { out += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(e.title))", "TRIGGER:\(t)", "END:VALARM"] }
            out.append("END:VEVENT")
        }
        out.append("END:VCALENDAR")
        return out.joined(separator: "\r\n") + "\r\n"
    }

    @MainActor
    static func openInCalendar(_ events: [ICSEvent]) -> Bool {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("VOTsidian") else { return false }
        let url = dir.appendingPathComponent("Avisos-VOTsidian.ics")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try build(events).write(to: url, atomically: true, encoding: .utf8)
        } catch { return false }
        return NSWorkspace.shared.open(url)
    }
}
