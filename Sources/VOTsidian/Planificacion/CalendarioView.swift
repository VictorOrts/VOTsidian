import SwiftUI

struct CalendarioView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case tarea = "Tarea", cita = "Cita", nota = "Nota", peso = "Peso", pinchazo = "Pinchazo"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @State private var monthOffset = 0
    @State private var weekOffset = 0
    /// Mes (rejilla) o semana por horas. Se recuerda.
    @AppStorage("calendarWeek") private var weekMode = false
    /// Panel del día a la derecha. Plegado, la rejilla gana 400 pt y los títulos se cortan menos. Se recuerda.
    @AppStorage("calendarPanel") private var showPanel = true
    /// Elemento seleccionado del día elegido (bloque de la semana, ficha de la cabecera o fila del panel): su ficha va arriba del panel.
    @State private var selectedEvent: EventSelection?
    @State private var focusToken = 0
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
        let _ = BodyCounter.hit("CalendarioView")
        HStack(spacing: 0) {
            Group { if weekMode { week } else { month } }
                .padding(20)
                .frame(maxWidth: .infinity)
            if showPanel {
                Divider()
                dayPanel(agenda: store.agenda(from: selected, to: selected)[DayKey.string(selected)] ?? [])
                    .frame(width: 400)
                    .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle("Calendario")
        .onAppear { loadNote() }
        .onDisappear { saveNote() }
        .autosave(on: noteDraft) { saveNote(quiet: true) }
        .onChange(of: store.read(Store.diaryPath(selected))) { if noteDraft == noteBase { loadNote() } }
        // Pasada la medianoche, si se miraba hoy, pasa al día nuevo (guardando antes la nota del día).
        .onChange(of: store.today) { old, new in if selected == old { select(new) } }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: $weekMode) { Text("Mes").tag(false); Text("Semana").tag(true) }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            Button { withAnimation(.snappy) { showPanel.toggle() } } label: {
                Image(systemName: "sidebar.right").accessibilityLabel(showPanel ? "Ocultar el panel del día" : "Mostrar el panel del día")
            }
            .help(showPanel ? "Ocultar el panel del día" : "Mostrar el panel del día")
        }
    }

    // MARK: Mes

    private var month: some View {
        let first = monthStart
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let days = cal.range(of: .day, in: .month, for: first)!.count
        let gridStart = DayKey.adding(days: -lead, to: first)
        let rows = Int(ceil(Double(lead + days) / 7))
        let gridEnd = DayKey.adding(days: rows * 7 - 1, to: gridStart)
        let agenda = store.agenda(from: gridStart, to: gridEnd)
        let kinds = Set(agenda.values.joined().map(\.kind))

        return VStack(alignment: .leading, spacing: 12) {
                // Si no cabe la leyenda al lado del mes, va debajo.
                ViewThatFits(in: .horizontal) {
                    HStack { monthNavigation(first); Spacer(); legend(kinds); modePicker }
                    VStack(alignment: .leading, spacing: 8) { HStack { monthNavigation(first); Spacer(); modePicker }; legend(kinds) }
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
    }

    // MARK: Semana por horas

    /// Siete columnas de horas (lunes a domingo). Arriba, lo de todo el día y las tareas sin hora; soltar una tarea en una
    /// columna le pone ese día y esa hora, y en la cabecera, solo el día.
    private var week: some View {
        let start = DayKey.adding(days: weekOffset * 7, to: DayKey.weekStart(DayKey.today()))
        let days = (0..<7).map { DayKey.adding(days: $0, to: start) }
        let agenda = store.agenda(from: start, to: days[6])
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Semana anterior") }
                Text(weekTitle(start, days[6])).font(.title2.weight(.semibold)).frame(minWidth: 230)
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Semana siguiente") }
                Button("Hoy") { weekOffset = 0; select(DayKey.today()) }
                Spacer()
                modePicker
            }
            HStack(alignment: .top, spacing: 4) {
                Color.clear.frame(width: 42, height: 1)
                ForEach(days, id: \.self) { d in weekHeader(d, items: (agenda[DayKey.string(d)] ?? []).filter { $0.minutes == nil && $0.kind != .done && $0.kind != .diary }) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 4) {
                        HourLabels()
                        ForEach(days, id: \.self) { d in
                            TimelineColumn(day: d, blocks: store.dayPlan(d, agenda: agenda[DayKey.string(d)] ?? []).blocks, compact: true,
                                           selected: d == selected ? selectedEvent : nil) { b, focus in
                                if let b { selectEvent(EventSelection(id: b.id, title: b.title), on: d, focus: focus) } else { selectedEvent = nil }
                            }
                                .background(d == selected ? Brand.accent.opacity(0.05) : .clear)
                        }
                    }.padding(.vertical, 8)
                }
                .onAppear { proxy.scrollTo("h7", anchor: .top) }
            }
        }
    }

    private func weekTitle(_ a: Date, _ b: Date) -> String {
        let sameMonth = cal.isDate(a, equalTo: b, toGranularity: .month)
        return "\(cal.component(.day, from: a))" + (sameMonth ? "" : " de " + DayKey.esLong(a, .dateTime.month(.wide))) + " – " + DayKey.esLong(b, .dateTime.day().month(.wide))
    }

    private func weekHeader(_ day: Date, items: [AgendaItem]) -> some View {
        let isToday = day == DayKey.today(), isSel = day == selected
        return Button { select(day) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(DayKey.esLong(day, .dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                    Text("\(cal.component(.day, from: day))").font(.system(size: 15, weight: isToday ? .bold : .medium, design: .rounded)).foregroundStyle(isToday ? Brand.accent : .primary)
                }
                ForEach(items.prefix(3)) { item in
                    Text(item.title).font(.caption2).lineLimit(1).padding(.horizontal, 4).padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item.kind.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                        .overlay { if selectedEvent == EventSelection(id: item.id, title: item.title) && day == selected { RoundedRectangle(cornerRadius: 4).stroke(Brand.accent, lineWidth: 1.5) } }
                        .contentShape(Rectangle())
                        .help(item.title)
                        .onTapGesture { selectEvent(item, on: day) }
                        .draggable(item.task.map(\.id) ?? "")
                }
                if items.count > 3 { Text("+\(items.count - 3) más").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background(isSel ? Brand.accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Brand.radius))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .dropDestination(for: String.self) { ids, _ in
            guard let t = store.tasks.first(where: { ids.contains($0.id) && !$0.done }) else { return false }
            store.reschedule(t, to: day)
            feedback = "«\(t.text)» movida al \(shortDate(day))"
            return true
        }
    }

    // MARK: Rejilla

    private func monthNavigation(_ first: Date) -> some View {
        HStack {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Anterior") }
            Text(capitalizedFirst(DayKey.esLong(first, .dateTime.month(.wide).year()))).font(.title2.weight(.semibold)).frame(minWidth: 190)
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }
            Button("Hoy") { monthOffset = 0; select(DayKey.today()) }
        }
    }

    /// Los tipos que salen en el mes, no una lista fija: antes, una suscripción se pintaba con el violeta que la leyenda llamaba
    /// «pinchazo». Los que comparten color van juntos («medicación / suscripción»).
    private func legend(_ kinds: Set<AgendaItem.Kind>) -> some View {
        let order: [AgendaItem.Kind] = [.task, .appointment, .doseNext, .dose, .weight, .birthday, .event, .document, .mascota, .vehiculo,
                                        .suscripcion, .prestamo, .viaje, .lectura, .tramite, .shopping]
        var groups: [(color: Color, names: [String])] = []
        for k in order where kinds.contains(k) {
            let name = label(k)
            if let i = groups.firstIndex(where: { $0.color == k.color }) {
                if !groups[i].names.contains(name) { groups[i].names.append(name) }
            } else { groups.append((k.color, [name])) }
        }
        return HStack(spacing: 10) {
            ForEach(groups.indices, id: \.self) { i in
                // Sin partir la palabra («medica-ción») cuando falta sitio.
                HStack(spacing: 3) {
                    Circle().fill(groups[i].color).frame(width: 7, height: 7)
                    Text(groups[i].names.joined(separator: " / ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
            }
        }
    }

    private func label(_ k: AgendaItem.Kind) -> String {
        switch k {
        case .task: "tarea"
        case .appointment: "cita"
        case .doseNext, .dose: "medicación"
        case .weight: "peso"
        case .birthday: "cumple"
        case .event: "evento"
        case .document: "documento"
        case .mascota: "mascota"
        case .vehiculo: "vehículo"
        case .suscripcion: "suscripción"
        case .prestamo: "préstamo"
        case .viaje: "viaje"
        case .lectura: "lectura"
        case .tramite: "trámite"
        case .shopping: "compra"
        case .done, .diary: ""
        }
    }

    private func cell(_ day: Date, inMonth: Bool, items: [AgendaItem]) -> some View {
        let isToday = day == DayKey.today()
        let isSel = day == selected
        // Hasta dos títulos con el color de su tipo; el resto se resume en «+N».
        let shown = items.filter { $0.kind != .done && $0.kind != .diary }
        return Button { select(day) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(cal.component(.day, from: day))").font(.system(size: 14, weight: isToday ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isToday ? Brand.accent : inMonth ? Color.primary : Color.secondary.opacity(0.5))
                ForEach(shown.prefix(2)) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.kind.color).frame(width: 6, height: 6)
                        Text((item.timeText.map { $0 + " " } ?? "") + item.title).font(.caption2).lineLimit(1).foregroundStyle(inMonth ? .primary : .secondary)
                    }.help((item.timeText.map { $0 + " " } ?? "") + item.title)
                }
                if shown.count > 2 { Text("+\(shown.count - 2) más").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .topLeading)
            .background(isSel ? Brand.accent.opacity(0.18) : Color.primary.opacity(inMonth ? 0.05 : 0.02), in: RoundedRectangle(cornerRadius: Brand.radius))
            .overlay(RoundedRectangle(cornerRadius: Brand.radius).stroke(isSel ? Brand.accent : isToday ? Brand.accent.opacity(0.5) : .clear, lineWidth: isSel ? 2 : 1))
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
        let event = selectedEvent?.resolve(day: selected, blocks: store.dayPlan(selected, agenda: agenda).blocks, agenda: agenda)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capitalizedFirst(DayKey.esLong(selected, .dateTime.weekday(.wide).day().month(.wide)))).font(.title3.weight(.semibold))
                        Text(relativeDays(DayKey.days(from: DayKey.today(), to: selected))).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.pendingPlanDay = selected; store.screen = .dia } label: { Label("Por horas", systemImage: "calendar.day.timeline.left") }
                        .controlSize(.small).help("Abrir este día en Mi día")
                }

                if let event { EventPanel(event: event, focusToken: focusToken) { selectedEvent = nil } }
                if visible.isEmpty { EmptyNote("Nada este día.", icon: "checkmark.circle") }
                ForEach(visible) { item in row(item) }

                Divider()
                Text("Añadir a este día").font(.headline)
                // Con cinco tipos el segmentado no cabe en los 400 pt del panel: si no cabe, menú (si no, empuja el panel y pierde el margen).
                ViewThatFits(in: .horizontal) {
                    Picker("", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                    Picker("Tipo", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).fixedSize()
                }
                HStack {
                    TextField(placeholder, text: $text).focused($focused).onSubmit(add)
                    Button("Añadir", action: add).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if kind == .tarea, let guess = Capture.interpret(text, defaultDay: selected, tasksOnly: true) { CaptureChips(guess: guess) }
                else { Text(hint).font(.caption).foregroundStyle(.secondary) }
                if !feedback.isEmpty { Label(feedback, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(Brand.accent) }

                Divider()
                HStack {
                    Text("Nota del día").font(.headline)
                    Spacer()
                    if noteDraft != noteBase { Circle().fill(Brand.warn).frame(width: 8, height: 8) }
                    Button("Guardar") { saveNote() }.controlSize(.small).buttonStyle(.borderedProminent).disabled(noteDraft == noteBase)
                }
                TextEditor(text: $noteDraft)
                    .font(.body).frame(minHeight: 140)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Brand.radius))
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
            if let h = item.timeText { Text(h).monospacedDigit().foregroundStyle(.secondary) }
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
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(selectedEvent == EventSelection(id: item.id, title: item.title) ? Brand.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectEvent(item, on: selected, focus: true) }
        .simultaneousGesture(TapGesture().onEnded { selectEvent(item, on: selected) })
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
        case .cita: "Va a Médico, en Próximas citas, con la fecha de este día. Con «a las 17:30», también la hora."
        case .nota: "Se añade con la hora a la nota del día."
        case .peso: "Se añade a la tabla de Peso en esta fecha."
        case .pinchazo: "Registra el pinchazo en este día con la dosis y la zona sugeridas."
        }
    }

    // MARK: Acciones

    /// Selecciona un elemento de `day` (y ese día, si no lo estaba). Con `focus`, el cursor va al texto de la ficha.
    private func selectEvent(_ sel: EventSelection, on day: Date, focus: Bool = false) {
        if day != selected { select(day) }
        selectedEvent = sel
        // La ficha vive en el panel: si estaba plegado, se abre.
        if !showPanel { withAnimation(.snappy) { showPanel = true } }
        if focus { focusToken += 1 }
    }

    private func selectEvent(_ item: AgendaItem, on day: Date, focus: Bool = false) {
        selectEvent(EventSelection(id: item.id, title: item.title), on: day, focus: focus)
    }

    private func select(_ day: Date) {
        saveNote()
        if day != selected { selectedEvent = nil }
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
            feedback = store.addTask(NaturalDate.extractTask(raw), defaultDue: selected)
        case .cita:
            let p = NaturalDate.extractDateTime(raw)
            let day = p.date ?? selected
            store.addAppointment(p.text, date: day, time: p.time)
            feedback = "Cita añadida para \(shortDate(day))" + (p.time.map { " a las \(TimeOfDay.text($0))" } ?? "")
        case .nota:
            store.appendToDiary(selected, text: raw)
            loadNote()
            feedback = "Añadido a la nota del \(shortDate(selected))"
        case .peso:
            guard let kg = MD.number(raw) else { feedback = "Escribe el peso en kg, por ejemplo 105,5"; return }
            store.addWeight(date: selected, kg: kg, note: "")
            feedback = "Peso guardado"
        case .pinchazo:
            store.injectToday(date: selected, note: raw)
            feedback = "Pinchazo registrado"
        }
        text = ""
        focused = true
    }
}
