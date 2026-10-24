import AppKit
import Foundation

struct ReminderPlan: Equatable {
    var medicacion = true
    var medicacionMinutes = 9 * 60
    var review = true
    var reviewWeekday = 1 // 1 = domingo (Calendar gregoriano)
    var reviewMinutes = 19 * 60
    var monthlyWeight = true
    var weightMinutes = 9 * 60
    var tasks = true
    var mascota = true
    var birthdays = true
    var documents = true
    var events = true
    var payments = true
    /// Revisión mensual, el último día del mes.
    var monthlyReview = true
    var monthlyReviewMinutes = 19 * 60
    /// ITV, seguro… (30 días antes) y mantenimientos con fecha (7 días antes).
    var vehiculo = true
    /// Renovaciones y fin de prueba (el día antes), cuotas de préstamos y viajes (7 días antes).
    var suscripciones = true
    var prestamos = true
    var viajes = true
    /// Plazos de trámites (7 días antes) y renovaciones de seguros (30 días antes).
    var tramites = true

    /// El plan guardado en Avisos (mismas claves y valores por defecto que `RemindersView`).
    static var stored: ReminderPlan {
        let d = UserDefaults.standard
        func flag(_ k: String) -> Bool { d.object(forKey: k) as? Bool ?? true }
        func int(_ k: String, _ v: Int) -> Int { d.object(forKey: k) as? Int ?? v }
        var plan = ReminderPlan(medicacion: flag("remMedicacion"), medicacionMinutes: int("remMedicacionMin", 540),
                            review: flag("remReview"), reviewWeekday: int("remReviewDay", 1), reviewMinutes: int("remReviewMin", 1140),
                            monthlyWeight: flag("remWeight"), weightMinutes: int("remWeightMin", 540),
                            tasks: flag("remTasks"), mascota: flag("remMascota"), birthdays: flag("remBirthdays"),
                            documents: flag("remDocs"), events: flag("remEvents"), payments: flag("remPayments"))
        plan.monthlyReview = flag("remMonthReview")
        plan.monthlyReviewMinutes = int("remMonthReviewMin", 1140)
        plan.vehiculo = flag("remVehiculo")
        plan.suscripciones = flag("remSuscripciones")
        plan.prestamos = flag("remPrestamos")
        plan.viajes = flag("remViajes")
        plan.tramites = flag("remTramites")
        return plan
    }
}

struct ReminderSources {
    var medicacion = MedicacionData()
    var tasks: [TaskItem] = []
    var mascota = MascotaData()
    var vehiculo = VehiculoData()
    var suscripciones = SuscripcionesData()
    var prestamos = PrestamosData()
    var viajes = ViajesData()
    var tramites = TramitesData()
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
        let medicacion = src.medicacion, tasks = src.tasks, mascota = src.mascota
        var out: [ICSEvent] = []

        // Un aviso por medicamento y hora: lo diario cada día; lo periódico cada N días desde la última toma.
        if plan.medicacion {
            for m in medicacion.active(on: today) where !m.asNeeded {
                let start: Date
                if m.every == 1 { start = max(today, m.start ?? today) }
                else if let next = medicacion.next(of: m) { start = max(next, today) }
                else { continue }
                let times = m.times.isEmpty ? [nil] : m.times.map(Medication.minutes)
                for (i, minutes) in times.enumerated() {
                    out.append(ICSEvent(uid: "med-\(ICS.stableID(MD.fold(m.name)))-\(i)",
                                        title: (m.isInjection ? "Pinchazo " : "Tomar ") + m.name + (m.dose.isEmpty ? "" : " (\(m.dose))"),
                                        notes: "Anótalo en \(VaultPath.medicacion). \(m.frequencyText).",
                                        start: start, minutes: minutes ?? plan.medicacionMinutes,
                                        rule: "FREQ=DAILY;INTERVAL=\(m.every)" + (m.end.map { ";UNTIL=\(DayKey.string($0).replacingOccurrences(of: "-", with: ""))" } ?? "")))
                }
            }
        }
        if plan.review {
            let delta = (plan.reviewWeekday - cal.component(.weekday, from: today) + 7) % 7
            let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            out.append(ICSEvent(uid: "revision-semanal", title: "Revisión semanal",
                                notes: "Marca hábitos, logros y tres objetivos de la semana.",
                                start: DayKey.adding(days: delta, to: today), minutes: plan.reviewMinutes,
                                rule: "FREQ=WEEKLY;BYDAY=\(codes[plan.reviewWeekday - 1])"))
        }
        if plan.monthlyReview {
            let first = cal.dateInterval(of: .month, for: today)!.start
            let end = DayKey.adding(days: -1, to: cal.date(byAdding: .month, value: 1, to: first)!)
            out.append(ICSEvent(uid: "revision-mensual", title: "Revisión mensual",
                                notes: "Logros, lo que no salió y tres objetivos para el mes siguiente (20 minutos).",
                                start: end, minutes: plan.monthlyReviewMinutes, rule: "FREQ=MONTHLY;BYMONTHDAY=-1"))
        }
        if plan.monthlyWeight {
            let first = cal.dateInterval(of: .month, for: today)!.start
            let end = DayKey.adding(days: -1, to: cal.date(byAdding: .month, value: 1, to: first)!)
            out.append(ICSEvent(uid: "peso-mensual", title: "Pesaje mensual",
                                notes: "En ayunas. Anótalo en \(VaultPath.peso).",
                                start: end, minutes: plan.weightMinutes, rule: "FREQ=MONTHLY;BYMONTHDAY=-1"))
        }
        if plan.tasks {
            for t in tasks where !t.done {
                guard let due = t.due, due >= today else { continue }
                // Con hora: evento a esa hora con aviso una hora antes. Las citas médicas avisan además el día anterior.
                let medical = t.file == VaultPath.medico
                out.append(ICSEvent(uid: "tarea-" + stableID(t.text + DayKey.string(due)), title: t.text,
                                    notes: medical ? "Cita en la nota \(t.noteName)." : "Tarea en la nota \(t.noteName).", start: due, minutes: t.time, rule: nil,
                                    extraTriggers: (medical ? ["-P1D"] : []) + (t.time != nil ? ["-PT1H"] : [])))
            }
        }
        if plan.mascota {
            for u in mascota.upcoming {
                out.append(ICSEvent(uid: "mascota-" + stableID(u.title + DayKey.string(u.date)), title: "\(mascota.name): \(u.title)",
                                    notes: "Cita o revisión de \(mascota.name).", start: u.date, minutes: nil, rule: nil))
            }
        }
        if plan.vehiculo {
            let v = src.vehiculo
            for d in v.dues where d.date >= today {
                out.append(ICSEvent(uid: "vehiculo-" + stableID(d.name + DayKey.string(d.date)), title: "\(v.name): vence \(d.name)",
                                    notes: "En la nota \(VaultPath.vehiculo).", start: d.date, minutes: nil, rule: nil, extraTriggers: ["-P30D"]))
            }
            for s in v.nextServices(today: today) {
                guard let d = s.date, d >= today else { continue }
                out.append(ICSEvent(uid: "vehiculo-mant-" + stableID(MD.fold(s.what)), title: "\(v.name): \(s.what)",
                                    notes: "Mantenimiento en la nota \(VaultPath.vehiculo).", start: d, minutes: nil, rule: nil, extraTriggers: ["-P7D"]))
            }
        }
        let year = DayKey.adding(days: 365, to: today)
        if plan.suscripciones {
            for i in src.suscripciones.items {
                if i.status == .trial, i.anchor >= today {
                    out.append(ICSEvent(uid: "susc-prueba-" + stableID(i.name + DayKey.string(i.anchor)), title: "Acaba la prueba: \(i.name) (\(Money.exact(i.amount)))",
                                        notes: "Cancela antes si no la quieres.", start: i.anchor, minutes: nil, rule: nil, extraTriggers: ["-P2D"]))
                }
                for d in i.occurrences(from: today, to: year).prefix(12) {
                    out.append(ICSEvent(uid: "susc-" + stableID(i.name + DayKey.string(d)), title: "Renueva: \(i.name) (\(Money.exact(i.amount)))",
                                        notes: "Suscripción en la nota Suscripciones.", start: d, minutes: nil, rule: nil, extraTriggers: ["-P1D"]))
                }
            }
        }
        if plan.prestamos {
            for s in src.prestamos.statuses(today: today) {
                for d in src.prestamos.dueDates(s, upTo: year, limit: 12) {
                    out.append(ICSEvent(uid: "prestamo-" + stableID(s.loan.name + DayKey.string(d)), title: "Cuota: \(s.loan.name) (\(Money.exact(s.loan.installment)))",
                                        notes: "Quedan \(Money.exact(s.remaining)) por pagar. Apúntala en VOTsidian.", start: d, minutes: nil, rule: nil, extraTriggers: ["-P1D"]))
                }
            }
        }
        if plan.viajes {
            for t in src.viajes.upcoming(today: today) {
                guard let s = t.start, s >= today else { continue }
                out.append(ICSEvent(uid: "viaje-" + stableID(t.name + DayKey.string(s)), title: "Viaje: \(t.name)",
                                    notes: "Viaje en la nota Viajes.", start: s, minutes: nil, rule: nil, extraTriggers: ["-P7D"]))
            }
        }
        if plan.tramites {
            for (p, due) in src.tramites.pendingProcedures where due >= today {
                out.append(ICSEvent(uid: "tramite-" + stableID(p.name + DayKey.string(due)), title: "Plazo: \(p.name)" + (p.amount.map { " (\(Money.exact($0)))" } ?? ""),
                                    notes: "Trámite en la nota \(VaultPath.tramites). Márcalo hecho en VOTsidian.", start: due, minutes: nil, rule: nil, extraTriggers: ["-P7D"]))
            }
            for i in src.tramites.insurances {
                for d in i.renewals(from: today, to: year).prefix(12) {
                    out.append(ICSEvent(uid: "seguro-" + stableID(i.name + DayKey.string(d)), title: "Renueva el seguro de \(i.name)" + (i.premium > 0 ? " (\(Money.exact(i.premium)))" : ""),
                                        notes: i.phone.isEmpty ? "Seguro en la nota \(VaultPath.tramites)." : "Asistencia: \(i.phone).", start: d, minutes: nil, rule: nil, extraTriggers: ["-P30D"]))
                }
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
