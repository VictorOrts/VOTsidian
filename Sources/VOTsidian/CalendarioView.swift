import SwiftUI

struct CalendarioView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case tarea = "Tarea", cita = "Cita", nota = "Nota", peso = "Peso", pinchazo = "Pinchazo"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @State private var monthOffset = 0
    @State private var selected = DayKey.today()
    @State private var kind = Kind.tarea
    @State private var text = ""
    @State private var noteDraft = ""
    @State private var noteBase = ""
    @State private var noteDay = DayKey.today()
    @State private var feedback = ""
    @FocusState private var focused: Bool

    private var cal: Calendar { DayKey.calendar() }
    private var monthStart: Date { cal.date(byAdding: .month, value: monthOffset, to: cal.dateInterval(of: .month, for: DayKey.today())!.start)! }

    var body: some View {
        let first = monthStart
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let gridStart = DayKey.adding(days: -lead, to: first)
        let rows = Int(ceil(Double(lead + days) / 7))
        let gridEnd = DayKey.adding(days: rows * 7 - 1, to: gridStart)
        let agenda = store.agenda(from: gridStart, to: gridEnd)

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Anterior") }
                    Text(capitalizedFirst(DayKey.esLong(first, .dateTime.month(.wide).year()))).font(.title2.weight(.semibold)).frame(minWidth: 190)
                    Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }
                    Button("Hoy") { monthOffset = 0; select(DayKey.today()) }
                    Spacer()
                    legend
                }
                HStack(spacing: 6) {
                    ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                VStack(spacing: 6) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { c in
                                let day = DayKey.adding(days: r * 7 + c, to: gridStart)
                                cell(day, inMonth: cal.isDate(day, equalTo: first, toGranularity: .month), items: agenda[DayKey.string(day)] ?? [])
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity)

            Divider()
            dayPanel(agenda: store.agenda(from: selected, to: selected)[DayKey.string(selected)] ?? [])
                .frame(width: 400)
        }
        .navigationTitle("Calendario")
        .onAppear { loadNote() }
        .onDisappear { saveNote() }
        .autosave(on: noteDraft) { saveNote(quiet: true) }
        .onChange(of: store.revision) { if noteDraft == noteBase { loadNote() } }
    }

    // MARK: Rejilla

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([AgendaItem.Kind.task, .appointment, .doseNext, .weight, .birthday, .event], id: \.self) { k in
                HStack(spacing: 3) { Circle().fill(k.color).frame(width: 7, height: 7); Text(label(k)).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private func label(_ k: AgendaItem.Kind) -> String {
        switch k {
        case .task: "tarea"
        case .appointment: "cita"
        case .doseNext, .dose: "pinchazo"
        case .weight: "peso"
        case .birthday: "cumple"
        case .event: "evento"
        default: ""
        }
    }

    private func cell(_ day: Date, inMonth: Bool, items: [AgendaItem]) -> some View {
        let isToday = day == DayKey.today()
        let isSel = day == selected
        let kinds = Array(Set(items.map(\.kind.rawValue))).sorted().compactMap(AgendaItem.Kind.init(rawValue:)).filter { $0 != .done }
        return Button { select(day) } label: {
            VStack(spacing: 4) {
                HStack {
                    Text("\(cal.component(.day, from: day))").font(.system(size: 14, weight: isToday ? .bold : .regular, design: .rounded))
                        .foregroundStyle(isToday ? Brand.accent : inMonth ? Color.primary : Color.secondary.opacity(0.5))
                    Spacer()
                    if items.filter({ $0.kind != .done && $0.kind != .diary }).count > 1 {
                        Text("\(items.filter { $0.kind != .done && $0.kind != .diary }.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 3) { ForEach(kinds.prefix(6), id: \.self) { Circle().fill($0.color).frame(width: 7, height: 7) } ; Spacer(minLength: 0) }
                if let t = items.first(where: { $0.kind == .task || $0.kind == .appointment }) {
                    Text(t.title).font(.caption2).lineLimit(1).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else { Spacer(minLength: 0) }
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .topLeading)
            .background(isSel ? Brand.accent.opacity(0.18) : Color.primary.opacity(inMonth ? 0.05 : 0.02), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSel ? Brand.accent : isToday ? Brand.accent.opacity(0.5) : .clear, lineWidth: isSel ? 2 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .dropDestination(for: String.self) { ids, _ in
            guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }) else { return false }
            store.reschedule(t, to: day)
            feedback = "«\(t.text)» movida al \(shortDate(day))"
            return true
        }
    }

    // MARK: Panel del día

    private func dayPanel(agenda: [AgendaItem]) -> some View {
        let visible = agenda.filter { $0.kind != .diary }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capitalizedFirst(DayKey.esLong(selected, .dateTime.weekday(.wide).day().month(.wide)))).font(.title3.weight(.semibold))
                    Text(relativeDays(DayKey.days(from: DayKey.today(), to: selected))).foregroundStyle(.secondary)
                }

                if visible.isEmpty { Text("Nada este día.").foregroundStyle(.secondary) }
                ForEach(visible) { item in row(item) }

                Divider()
                HStack(spacing: 10) {
                    Text("Ánimo").font(.headline)
                    MoodPicker(value: store.diaryValue(selected, "animo")) { store.setDiaryValue(selected, "animo", $0) }
                    Spacer()
                    Text("Sueño").font(.headline)
                    DiaryNumberField(day: selected, key: "sueno_h", placeholder: "h")
                }
                Divider()
                Text("Añadir a este día").font(.headline)
                Picker("", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    TextField(placeholder, text: $text).focused($focused).onSubmit(add)
                    Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(hint).font(.caption).foregroundStyle(.secondary)
                if !feedback.isEmpty { Label(feedback, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent) }

                Divider()
                HStack {
                    Text("Nota del día").font(.headline)
                    Spacer()
                    if noteDraft != noteBase { Circle().fill(Brand.warn).frame(width: 8, height: 8) }
                    Button("Guardar") { saveNote() }.controlSize(.small).disabled(noteDraft == noteBase)
                }
                TextEditor(text: $noteDraft)
                    .font(.body).frame(minHeight: 140)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                Text("Se guarda en Diario/\(DayKey.string(selected)).md al cambiar de día o pulsar Guardar.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            if let t = item.task, item.kind != .done {
                Button { store.setTask(t, done: true) } label: { Image(systemName: "circle").accessibilityLabel("Completar").foregroundStyle(item.kind.color) }.buttonStyle(.plain).help("Completar")
            } else {
                Image(systemName: item.kind.icon).foregroundStyle(item.kind.color).frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(MDParser.inline(item.title)).strikethrough(item.kind == .done).foregroundStyle(item.kind == .done ? .secondary : .primary)
                if !item.detail.isEmpty { Text(item.detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let t = item.task, item.kind != .done {
                Menu {
                    Button("Mañana") { store.reschedule(t, to: DayKey.adding(days: 1, to: DayKey.today())) }
                    Button("En una semana") { store.reschedule(t, to: DayKey.adding(days: 7, to: selected)) }
                    Button("Un día después") { store.reschedule(t, to: DayKey.adding(days: 1, to: selected)) }
                } label: { Image(systemName: "clock.arrow.circlepath").accessibilityLabel("Aplazar") }.menuStyle(.borderlessButton).fixedSize().help("Aplazar")
            }
            if let s = item.screen { Button { store.screen = s } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }.buttonStyle(.borderless).foregroundStyle(.tertiary) }
            else if let p = item.path { Button { store.pendingNote = p } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }.buttonStyle(.borderless).foregroundStyle(.tertiary) }
        }
        .draggable(item.task.map { $0.id } ?? "")
    }

    private var placeholder: String {
        switch kind {
        case .tarea: "Qué hay que hacer"
        case .cita: "Cita (médico, motivo)"
        case .nota: "Apunta algo del día"
        case .peso: "Peso en kg"
        case .pinchazo: "Notas (opcional)"
        }
    }

    private var hint: String {
        switch kind {
        case .tarea: "Va al Inbox con la fecha de este día (📅). Si escribes otra fecha, como “el viernes”, usa esa."
        case .cita: "Va a Médico, en Próximas citas, con la fecha de este día."
        case .nota: "Se añade con la hora a la nota del día."
        case .peso: "Se añade a la tabla de Peso en esta fecha."
        case .pinchazo: "Registra el pinchazo en este día con la dosis y la zona sugeridas."
        }
    }

    // MARK: Acciones

    private func select(_ day: Date) {
        saveNote()
        selected = day
        feedback = ""
        loadNote()
    }

    private func loadNote() {
        noteDay = selected
        let t = store.read(Store.diaryPath(selected))
        noteDraft = t; noteBase = t
    }

    private func saveNote(quiet: Bool = false) {
        guard noteDraft != noteBase else { return }
        let rel = Store.diaryPath(noteDay)
        var body = noteDraft
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !FileManager.default.fileExists(atPath: store.url(rel).path) { noteBase = noteDraft; return }
        if !body.hasPrefix("---") { body = Store.diaryTemplate(noteDay) + body }
        let isNew = !FileManager.default.fileExists(atPath: store.url(rel).path)
        if !isNew, store.readOptional(rel) != noteBase {
            feedback = "La nota de ese día cambió fuera de la app. Se ha vuelto a cargar para no pisarla."
            noteDraft = store.read(rel); noteBase = noteDraft
            return
        }
        if store.writeNote(rel, text: body, quiet: quiet) {
            noteBase = noteDraft
            if isNew { store.connectDiary(noteDay) }
        }
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        switch kind {
        case .tarea:
            let p = NaturalDate.extractTask(raw)
            let day = p.date ?? selected
            store.addTask(p.text, due: day, recurrence: p.recurrence, priority: p.priority)
            feedback = "Tarea añadida para \(shortDate(day))" + (p.recurrence.map { " · \(Recurrence.describe($0))" } ?? "")
        case .cita:
            let p = NaturalDate.extract(raw)
            let day = p.date ?? selected
            store.edit(VaultPath.medico) { Edit.appendToSection($0, section: "Próximas citas", line: "- [ ] \(p.text) 📅 \(DayKey.string(day))") }
            feedback = "Cita añadida para \(shortDate(day))"
        case .nota:
            store.appendToDiary(selected, text: raw)
            loadNote()
            feedback = "Añadido a la nota del \(shortDate(selected))"
        case .peso:
            guard let kg = MD.number(raw) else { feedback = "Escribe el peso en kg, por ejemplo 105,5"; return }
            store.addWeight(date: selected, kg: kg, note: "")
            feedback = "Peso guardado"
        case .pinchazo:
            store.addDose(date: selected, dose: store.mounjaro.last?.mg ?? 7.5, site: store.mounjaro.suggestedSite, note: raw)
            feedback = "Pinchazo registrado"
        }
        text = ""
        focused = true
    }
}
