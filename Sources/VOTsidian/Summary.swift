import Foundation

extension Store {
    /// Texto listo para pegar o enseñar en una consulta médica.
    func doctorSummary(today: Date = DayKey.today()) -> String {
        var l: [String] = []
        l.append("Resumen para consulta · \(DayKey.dmy(today))")
        l.append("")
        let w = weight
        if let last = w.last {
            l.append("PESO")
            l.append("- Actual: \(fmt(last.kg)) kg (\(DayKey.dmy(last.date)))")
            if let s = w.start { l.append("- Inicio: \(fmt(w.initialKg)) kg el \(DayKey.dmy(s)) → \(fmtDelta(last.kg - w.initialKg))") }
            if w.goalKg > 0 { l.append("- Objetivo: \(fmt(w.goalKg, 0)) kg (faltan \(fmt(w.remainingKg)) kg)") }
            if let r = w.ratePerMonth(window: 120) { l.append("- Ritmo de los últimos 4 meses: \(fmtDelta(r, unit: " kg/mes"))") }
            let recent = w.records.suffix(6).map { "\(DayKey.dmy($0.date)): \(fmt($0.kg))" }.joined(separator: " · ")
            l.append("- Últimos pesajes: \(recent)")
            l.append("")
        }
        let m = mounjaro
        if let last = m.last {
            l.append("MOUNJARO")
            l.append("- Dosis actual: \(last.dose) cada \(m.everyDays) días. Último pinchazo: \(DayKey.dmy(last.date)) (\(last.site))")
            if let first = m.doses.first { l.append("- \(m.doses.count) pinchazos desde \(DayKey.dmy(first.date))") }
            for p in m.periods(weights: w.records) {
                l.append("- \(MD.formatNumber(p.mg, comma: true)) mg desde \(DayKey.dmy(p.start)): \(p.count) pinchazos" + (p.lostKg.map { ", \(fmt($0)) kg perdidos" } ?? "") + (p.kgPerMonth.map { " (\(fmt($0)) kg/mes)" } ?? ""))
            }
            l.append("")
        }
        let weeks = reviews.keys.sorted().suffix(4)
        if !weeks.isEmpty, !habitDefs.isEmpty {
            l.append("HÁBITOS (últimas \(weeks.count) semanas, días cumplidos de 7)")
            for h in habitDefs {
                let counts = weeks.compactMap { reviews[$0]?.habits.first { MD.fold($0.name) == MD.fold(h.name) }?.count }
                if !counts.isEmpty { l.append("- \(h.name): \(counts.map(String.init).joined(separator: ", "))") }
            }
            l.append("")
        }
        if plan.kcal > 0 { l.append("NUTRICIÓN: \(fmt(plan.kcal, 0)) kcal · proteína \(fmt(plan.protein, 0)) g · hidratos \(fmt(plan.carbs, 0)) g · grasas \(fmt(plan.fat, 0)) g"); l.append("") }
        let med = Parse.listItems(read(VaultPath.medico), section: "Tratamientos").map(\.text)
        if !med.isEmpty { l.append("OTROS TRATAMIENTOS"); med.forEach { l.append("- \($0)") }; l.append("") }
        if let t = Parse.tables(read(VaultPath.medico)).first(where: { MD.fold($0.title).contains("analisis") }), let r = t.rows.last {
            l.append("ÚLTIMO ANÁLISIS: " + r.cells.prefix(2).joined(separator: " · "))
            l.append("")
        }
        let outLabs = labsOutOfRange
        if !outLabs.isEmpty {
            l.append("ANALÍTICAS FUERA DE RANGO (último resultado)")
            for r in outLabs { l.append("- \(r.name): \(r.valueText) (\(r.status.label.lowercased())\(r.refText.isEmpty ? "" : ", ref. \(r.refText)")) · \(DayKey.dmy(r.date))") }
            l.append("")
        }
        let next = tasks.filter { !$0.done && $0.file == VaultPath.medico && $0.due != nil }.sorted { $0.due! < $1.due! }
        if !next.isEmpty { l.append("PRÓXIMAS CITAS"); next.forEach { l.append("- \(DayKey.dmy($0.due!)): \($0.text)") } }
        return l.joined(separator: "\n")
    }
}
