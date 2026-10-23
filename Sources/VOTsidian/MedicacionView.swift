import Charts
import SwiftUI

let injectionSites = ["Abdomen izquierdo", "Abdomen derecho", "Muslo izquierdo", "Muslo derecho", "Brazo izquierdo", "Brazo derecho", "Abdomen"]

struct MedicacionView: View {
    @Environment(Store.self) private var store
    @State private var date = Date()
    @State private var dose = ""
    @State private var site = "Abdomen izquierdo"
    @State private var note = ""
    @State private var spec: RowSpec?
    // Medicamento nuevo
    @State private var newName = ""
    @State private var newDose = ""
    @State private var newForm = "Pastilla"
    @State private var newFrequency = 1   // 1 cada día, 7 cada semana, -1 otro, 0 si hace falta
    @State private var newEvery = 3
    @State private var newTimes = ""

    var body: some View {
        let m = store.medicacion
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MissingNoteBanner(module: .medicacion)
                todayCard(m)
                if let main = m.main { mainSection(m, main) }
                medsCard(m)
                addCard(m)
                logCard(m)
                Text("La medicación y sus cambios los decide tu médico. Esta sección solo registra, calcula y recuerda.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(store.medicacion.name)
        .sheet(item: $spec) { RowSheet(spec: $0) }
        .onAppear { resetEntry() }
    }

    private func resetEntry() {
        let m = store.medicacion
        dose = m.last?.dose ?? m.main?.dose ?? ""
        site = m.suggestedSite
        note = ""
    }

    // MARK: Hoy

    private func todayCard(_ m: MedicacionData) -> some View {
        let today = DayKey.today()
        let meds = m.active(on: today)
        return Card(title: "Hoy", icon: "checklist", info: "Marca cada toma al hacerla. Se apunta en el registro con la fecha y se puede deshacer.") {
            if meds.isEmpty { EmptyNote(m.meds.isEmpty ? "Añade tu primer medicamento más abajo." : "Ningún tratamiento activo hoy.", icon: "pills") }
            ForEach(meds) { med in
                HStack(spacing: 12) {
                    Image(systemName: med.icon).foregroundStyle(Brand.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(med.name + (med.dose.isEmpty ? "" : " · \(med.dose)")).fontWeight(.medium)
                        Text(status(med, m, today)).font(.caption).foregroundStyle(statusColor(med, m, today))
                    }
                    Spacer()
                    todayControls(med, m, today)
                }
            }
        }
    }

    private func status(_ med: Medication, _ m: MedicacionData, _ today: Date) -> String {
        if med.asNeeded {
            let n = m.taken(med, on: today)
            return n > 0 ? "Cuando haga falta · hoy \(n)" : "Cuando haga falta" + (m.last(of: med).map { " · última \(dayLabel($0.date))" } ?? "")
        }
        if med.every == 1 { return med.frequencyText }
        if m.taken(med, on: today) > 0 { return "Hecho hoy · \(med.frequencyText.lowercased())" }
        guard let d = m.daysUntil(med, today: today) else { return "\(med.frequencyText) · sin registros todavía" }
        return d < 0 ? "Va \(-d) \(-d == 1 ? "día" : "días") tarde" : d == 0 ? "Toca hoy" : "Próximo \(dayLabel(DayKey.adding(days: d, to: today))) (\(relativeDays(d)))"
    }

    private func statusColor(_ med: Medication, _ m: MedicacionData, _ today: Date) -> Color {
        guard !med.asNeeded, med.every > 1, m.taken(med, on: today) == 0, let d = m.daysUntil(med, today: today) else { return .secondary }
        return d < 0 ? Brand.bad : d == 0 ? Brand.warn : .secondary
    }

    @ViewBuilder private func todayControls(_ med: Medication, _ m: MedicacionData, _ today: Date) -> some View {
        let taken = m.taken(med, on: today)
        if med.asNeeded {
            Button("Apuntar toma") { store.take(med) }.controlSize(.small)
        } else if med.every == 1 {
            IntakeChecks(med: med)
        } else if taken > 0 {
            Label("Hecho", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.accent)
        } else if let d = m.daysUntil(med, today: today), d <= 1 {
            Button(med.isInjection ? "Me pinché hoy" : "Tomada hoy") {
                if med == m.main { store.injectToday() } else { store.take(med) }
                resetEntry()
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    // MARK: Medicamento periódico (inyectable)

    @ViewBuilder private func mainSection(_ m: MedicacionData, _ main: Medication) -> some View {
        let d = m.daysUntilNext
        let doses = m.doses
        HStack(spacing: 12) {
            Tile(title: "Último", value: m.last.map { dayLabel($0.date) } ?? "–", note: m.last?.dose)
            Tile(title: "Próximo", value: m.next.map { dayLabel($0) } ?? "–", note: d.map(relativeDays), tint: (d ?? 0) < 0 ? Brand.bad : nil)
            Tile(title: "Intervalo", value: "\(main.every) días", note: main.name)
            Tile(title: main.isInjection ? "Pinchazos" : "Tomas", value: "\(doses.count)", note: doses.first.map { "desde \(dayLabel($0.date))" })
        }

        let points = doses.compactMap { x in x.mg.map { (x.date, $0) } }
        if points.count > 1 {
            let top = points.map(\.1).max() ?? 0
            // Paso «redondo» que deja como mucho 4 rayas: 0,25 mg para 0,5 mg; 2,5 mg para 7,5 mg; 250 mg para 850 mg…
            let step = [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 25, 50, 100, 250, 500, 1000].first { top / $0 <= 4 } ?? (top / 4).rounded(.up)
            Chart {
                ForEach(points, id: \.0) { p in
                    AreaMark(x: .value("Día", p.0), y: .value("mg", p.1)).interpolationMethod(.stepEnd).foregroundStyle(Brand.accent.opacity(0.12))
                    LineMark(x: .value("Día", p.0), y: .value("mg", p.1)).interpolationMethod(.stepEnd).foregroundStyle(Brand.accent)
                    PointMark(x: .value("Día", p.0), y: .value("mg", p.1)).foregroundStyle(Brand.accent).symbolSize(20)
                }
            }
            // El eje llega un escalón por encima de la dosis más alta, no a un tope fijo.
            .chartYScale(domain: 0...((top / step + 1).rounded(.down) * step))
            .chartYAxis { AxisMarks(values: .stride(by: step)) { v in AxisGridLine(); AxisValueLabel { if let mg = v.as(Double.self) { Text(MD.formatNumber(mg, comma: true)) } } } }
            .chartYAxisLabel("mg")
            .frame(height: 130)
            .accessibilityLabel("Gráfica de dosis de \(main.name)")
            .accessibilityValue(points.suffix(5).map { "\(DayKey.dmy($0.0)) \(fmt($0.1, 1)) mg" }.joined(separator: ", "))
        }

        let periods = m.periods(weights: store.weight.records)
        if !periods.isEmpty, !store.weight.records.isEmpty { periodsCard(periods, act: main.isInjection ? "Pinchazos" : "Tomas") }

        Card(title: main.isInjection ? "Registrar pinchazo de \(main.name)" : "Registrar toma de \(main.name)", icon: "plus.circle",
             info: "Se añade una fila a \(VaultPath.medicacion)." + (main.isInjection ? " Zona sugerida para alternar: \(m.suggestedSite)." : "")) {
            HStack(spacing: 20) {
                DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).fixedSize()
                TextField("Dosis (p. ej. 7,5 mg)", text: $dose).frame(width: 150)
                if main.isInjection { Picker("Zona", selection: $site) { ForEach(injectionSites, id: \.self) { Text($0).tag($0) } }.fixedSize() }
                Spacer()
            }
            HStack {
                TextField("Notas", text: $note)
                Button("Guardar") {
                    store.take(main, date: DayKey.calendar().startOfDay(for: date), dose: dose, site: main.isInjection ? site : "", note: note)
                    resetEntry()
                }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func periodsCard(_ periods: [DosePeriod], act: String) -> some View {
        Card(title: "Peso por dosis", icon: "chart.bar.xaxis", info: "Peso al empezar y al terminar cada tramo de dosis, con el pesaje más cercano. Orientativo: pesas una vez al mes.") {
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 7) {
                GridRow { Text("Dosis"); Text("Desde"); Text(act); Text("Peso inicial"); Text("Peso final"); Text("Perdidos"); Text("Ritmo") }
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(periods) { p in
                    GridRow {
                        Text(MD.formatNumber(p.mg, comma: true) + " mg").fontWeight(.medium)
                        Text(DayKey.dmy(p.start)).monospacedDigit()
                        Text("\(p.count)").monospacedDigit()
                        Text(fmt(p.startKg, unit: " kg")).monospacedDigit()
                        Text(fmt(p.endKg, unit: " kg")).monospacedDigit()
                        Text(fmt(p.lostKg, unit: " kg")).monospacedDigit().foregroundStyle(Brand.accent)
                        Text(p.kgPerMonth.map { fmt($0, unit: " kg/mes") } ?? "–").monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: Medicamentos

    private func medsCard(_ m: MedicacionData) -> some View {
        Card(title: "Medicamentos", icon: "pills",
             info: "Cumplimiento: días de los últimos 30 (sin contar hoy) con todas las tomas apuntadas. Solo en lo diario.") {
            if m.meds.isEmpty { EmptyNote("Todavía no hay medicamentos.", icon: "pills") }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(m.meds) { med in
                    GridRow {
                        Image(systemName: med.icon).foregroundStyle(Brand.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(med.name).fontWeight(.medium)
                            Text([med.dose, med.form].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            // En una nota de antes la frecuencia ya la dice el control de la derecha.
                            Text(med.line < 0 ? "" : med.frequencyText)
                            if let e = med.end { Text(e < DayKey.today() ? "acabó el \(DayKey.dmy(e))" : "hasta el \(DayKey.dmy(e))").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let a = m.adherence(med) {
                            Text("\(Int((Double(a.done) / Double(a.total) * 100).rounded())) % · \(a.done) de \(a.total) días")
                                .monospacedDigit().foregroundStyle(a.done * 10 >= a.total * 9 ? Brand.accent : a.done * 10 >= a.total * 7 ? Brand.warn : Brand.bad)
                        } else { Text("") }
                        if med.line >= 0 {
                            EditButton { spec = RowSpec(file: VaultPath.medicacion, mode: .edit(line: med.line), title: "medicamento") }
                        } else {
                            Stepper("Cada \(med.every) días", value: Binding(get: { med.every }, set: { store.setEvery(med, days: $0) }), in: 1...60).fixedSize()
                        }
                    }
                }
            }
            if m.legacy, !m.meds.isEmpty {
                Text("Al añadir otro medicamento, la nota pasa a tener una tabla de medicamentos y una columna «Medicamento» en el registro. Se puede deshacer.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func addCard(_ m: MedicacionData) -> some View {
        let every = newFrequency == -1 ? newEvery : newFrequency
        let name = newName.trimmingCharacters(in: .whitespaces)
        return Card(title: "Añadir medicamento", icon: "plus.circle",
                    info: "Las horas sirven para los avisos y para marcar cada toma del día por separado (por ejemplo 09:00, 21:00).") {
            HStack(spacing: 12) {
                TextField("Medicamento", text: $newName).frame(minWidth: 180)
                TextField("Dosis (p. ej. 1 pastilla, 500 mg)", text: $newDose).frame(minWidth: 200)
                Picker("Forma", selection: $newForm) { ForEach(Medication.forms, id: \.self) { Text($0).tag($0) } }.fixedSize()
            }
            HStack(spacing: 12) {
                Picker("Cada", selection: $newFrequency) {
                    Text("Cada día").tag(1); Text("Cada semana").tag(7); Text("Cada N días").tag(-1); Text("Si hace falta").tag(0)
                }.fixedSize()
                if newFrequency == -1 { Stepper("\(newEvery) días", value: $newEvery, in: 2...90).fixedSize() }
                if newFrequency != 0 { TextField("Horas (opcional): 09:00, 21:00", text: $newTimes).frame(minWidth: 220) }
                Spacer()
                Button("Añadir") {
                    store.addMedication(Medication(name: name, dose: newDose.trimmingCharacters(in: .whitespaces), form: newForm,
                                                   every: every, times: every == 0 ? [] : Medication.times(newTimes)))
                    newName = ""; newDose = ""; newTimes = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || m.meds.contains { MD.fold($0.name) == MD.fold(name) })
            }
        }
    }

    // MARK: Registro

    private func logCard(_ m: MedicacionData) -> some View {
        let recent = Array(m.intakes.reversed().prefix(20))
        return Card(title: "Registro", icon: "list.bullet", info: "Las últimas 20 tomas. Todas están en la nota.",
                    actionTitle: "Abrir la nota", action: { store.pendingNote = VaultPath.medicacion }) {
            if recent.isEmpty { EmptyNote("Sin tomas apuntadas.") }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                if !recent.isEmpty {
                    GridRow { Text("Fecha"); if !m.legacy { Text("Medicamento") }; Text("Dosis"); Text("Zona"); Text("Notas"); Text("") }.font(.caption).foregroundStyle(.secondary)
                    Divider()
                }
                ForEach(recent) { x in
                    GridRow {
                        Text(DayKey.string(x.date)).monospacedDigit()
                        if !m.legacy { Text(x.med) }
                        Text(x.dose); Text(x.site)
                        Text(x.note).foregroundStyle(.secondary).lineLimit(1)
                        EditButton { spec = RowSpec(file: VaultPath.medicacion, mode: .edit(line: x.line), title: "toma") }
                    }
                }
            }
        }
    }
}

/// Una casilla por toma del día de un medicamento diario: marcar apunta una toma; desmarcar quita la última de hoy.
struct IntakeChecks: View {
    @Environment(Store.self) private var store
    let med: Medication

    var body: some View {
        let taken = store.medicacion.taken(med, on: DayKey.today())
        HStack(spacing: 10) {
            ForEach(0..<med.perDay, id: \.self) { i in
                let on = i < taken
                Button { if on { store.untake(med) } else { store.take(med) } } label: {
                    Label(med.times.indices.contains(i) ? med.times[i] : "Tomada", systemImage: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Brand.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help(on ? "Quitar la toma" : "Marcar como tomada")
            }
        }
    }
}
