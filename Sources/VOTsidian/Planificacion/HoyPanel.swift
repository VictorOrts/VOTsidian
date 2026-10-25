import SwiftUI

/// Panel fijo de la derecha (⌥⌘0): el mes en pequeño con un punto por tipo de evento, lo del día elegido y un campo para añadir.
/// Su pestaña «Nota» enseña la nota de un enlace pulsado sin salir de la pantalla. Es una vista aparte: lo que lee (agenda,
/// tareas) no repinta la pantalla de al lado.
struct HoyPanel: View {
    enum Tab: Hashable { case hoy, nota }

    @Environment(Store.self) private var store
    @State private var day = DayKey.today()
    @State private var monthOffset = 0
    @State private var tab = Tab.hoy

    private var cal: Calendar { DayKey.calendar() }

    var body: some View {
        let _ = BodyCounter.hit("HoyPanel")
        VStack(spacing: 0) {
            if store.peekNote != nil {
                Picker("", selection: $tab) { Text("Hoy").tag(Tab.hoy); Text("Nota").tag(Tab.nota) }
                    .pickerStyle(.segmented).labelsHidden().padding([.horizontal, .top], 14)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == .nota, let p = store.peekNote {
                        NotePeek(path: p)
                    } else {
                        // Una sola consulta para el mes y el día elegido: tras cada cambio la agenda se rehace, y dos rangos
                        // eran dos pasadas por todas las tareas.
                        let grid = monthGrid
                        let agenda = store.agenda(from: grid.start, to: DayKey.adding(days: grid.rows * 7 - 1, to: grid.start))
                        let inGrid = day >= grid.start && day <= DayKey.adding(days: grid.rows * 7 - 1, to: grid.start)
                        month(grid, agenda)
                        Divider()
                        dayList(inGrid ? agenda[DayKey.string(day)] ?? [] : store.agenda(from: day, to: day)[DayKey.string(day)] ?? [])
                        CaptureField(placeholder: day == DayKey.today() ? "Añadir a hoy…" : "Añadir a este día…", defaultDay: day, compact: true)
                    }
                }
                .padding(14)
            }
            Divider()
            footer.padding(10)
        }
        .background(Color.primary.opacity(0.015))
        .onChange(of: store.peekNote, initial: true) { tab = store.peekNote == nil ? .hoy : .nota }
    }

    // MARK: Mes

    private var monthGrid: (first: Date, start: Date, rows: Int) {
        let first = cal.date(byAdding: .month, value: monthOffset, to: cal.dateInterval(of: .month, for: DayKey.today())!.start)!
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let count = cal.range(of: .day, in: .month, for: first)!.count
        return (first, DayKey.adding(days: -lead, to: first), Int(ceil(Double(lead + count) / 7)))
    }

    private func month(_ grid: (first: Date, start: Date, rows: Int), _ agenda: [String: [AgendaItem]]) -> some View {
        let (first, gridStart, rows) = grid
        let today = DayKey.today()
        return VStack(spacing: 6) {
            HStack {
                Text(capitalizedFirst(DayKey.esLong(first, .dateTime.month(.wide).year()))).font(.headline)
                Spacer()
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Mes anterior") }
                Button("Hoy") { monthOffset = 0; day = today }.disabled(monthOffset == 0 && day == today)
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Mes siguiente") }
            }
            .buttonStyle(.borderless).controlSize(.small)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow { ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
                ForEach(0..<rows, id: \.self) { r in
                    GridRow {
                        ForEach(0..<7, id: \.self) { c in
                            let d = DayKey.adding(days: r * 7 + c, to: gridStart)
                            cell(d, inMonth: cal.isDate(d, equalTo: first, toGranularity: .month), today: today, items: agenda[DayKey.string(d)] ?? [])
                        }
                    }
                }
            }
        }
    }

    private func cell(_ d: Date, inMonth: Bool, today: Date, items: [AgendaItem]) -> some View {
        let selected = d == day
        var kinds: [AgendaItem.Kind] = []
        for it in items where it.kind != .diary && it.kind != .done && !kinds.contains(it.kind) { kinds.append(it.kind) }
        return Button { day = d } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: d))").font(.caption.weight(d == today || selected ? .bold : .regular)).monospacedDigit()
                HStack(spacing: 2) {
                    ForEach(kinds.prefix(3), id: \.self) { k in Circle().fill(selected ? Color.white : k.color).frame(width: 4, height: 4) }
                }.frame(height: 4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .foregroundStyle(selected ? Color.white : d == today ? Brand.accent : inMonth ? Color.primary : Color.secondary.opacity(0.5))
            .background(selected ? Brand.accent : d == today ? Brand.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(longDate(d) + (items.isEmpty ? "" : ", \(items.count) cosas"))
    }

    // MARK: Día

    @ViewBuilder private func dayList(_ all: [AgendaItem]) -> some View {
        let today = DayKey.today()
        let items = all.filter { $0.kind != .diary }
        let overdue = day == today ? store.tasks.filter { !$0.done && ($0.due.map { $0 < today } ?? false) } : []
        Text(day == today ? "Hoy, " + longDate(day) : capitalizedFirst(longDate(day))).font(.headline)
        if !overdue.isEmpty {
            Text("Vencidas (\(overdue.count))").font(.caption.weight(.semibold)).foregroundStyle(Brand.bad)
            ForEach(overdue.prefix(5)) { t in taskLine(t, sub: "vencida \(t.due.map(dayLabel) ?? "")", late: true) }
        }
        if items.isEmpty && overdue.isEmpty { EmptyNote("Nada este día.", icon: "checkmark.circle") }
        ForEach(items) { it in
            if let t = it.task { taskLine(t, sub: [it.timeText, t.noteName == "Inbox" ? nil : t.noteName].compactMap { $0 }.joined(separator: " · "), late: false) }
            else { itemLine(it) }
        }
    }

    private func taskLine(_ t: TaskItem, sub: String, late: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { store.setTask(t, done: !t.done) } label: { Image(systemName: t.done ? "checkmark.circle.fill" : "circle") }
                .buttonStyle(.plain).foregroundStyle(t.done ? Brand.good : Brand.accent)
                .accessibilityLabel(t.done ? "Marcar como pendiente" : "Marcar como hecha")
            VStack(alignment: .leading, spacing: 1) {
                Text(MDParser.inline(t.text)).font(.callout).lineLimit(2).strikethrough(t.done).foregroundStyle(t.done ? .secondary : .primary)
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(late ? Brand.bad : .secondary) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !t.done {
                Button("Enfoque de 25 min") { store.startFocus(t.text) }
                Button("Enfoque de 50 min") { store.startFocus(t.text, minutes: 50) }
                Button("Pasar a mañana") { store.reschedule(t, to: DayKey.adding(days: 1, to: DayKey.today())) }
            }
            Button("Ver la nota «\(t.noteName)»") { store.peekNote = t.file }
        }
    }

    private func itemLine(_ it: AgendaItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: it.kind.icon).font(.caption).foregroundStyle(it.kind.color).frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(MDParser.inline(it.title)).font(.callout).lineLimit(2)
                let sub = [it.timeText, it.detail.isEmpty ? nil : it.detail].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let s = it.screen {
                Button { store.screen = s } label: { Image(systemName: "chevron.right").accessibilityLabel("Abrir \(store.title(s))") }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { store.openToday() } label: { Label("Nota de hoy", systemImage: "note.text") }
            Spacer()
            Button { store.showEmpezar = true } label: { Image(systemName: "sunrise").accessibilityLabel("Empezar el día") }.help("Empezar el día")
            Button { store.showCierre = true } label: { Image(systemName: "moon.stars").accessibilityLabel("Cerrar el día") }.help("Cerrar el día")
        }
        .controlSize(.small)
    }
}

/// Una nota leída fuera de Notas: en el panel de la derecha y en su propia ventana. Las casillas y propiedades se pueden tocar;
/// para escribir, «Editar en Notas».
struct NotePeek: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    let path: String
    var inWindow = false

    private var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    /// Lo que se pinta de una nota: el lector tarda medio milisegundo por línea con formato (20.000 líneas, 10 s), así que fuera
    /// de Notas se enseña el principio. Corta siempre en un salto de línea, para que los números de línea de las casillas sigan
    /// siendo los de la nota. Devuelve el texto y cuántas líneas quedan fuera.
    nonisolated static func head(_ text: String, maxLines: Int = 250, maxBytes: Int = 30_000) -> (text: String, cut: Int) {
        guard text.utf8.count > maxBytes || text.utf8.lazy.filter({ $0 == 10 }).count >= maxLines else { return (text, 0) }
        let bytes = Array(text.utf8)
        var lines = 0
        var end: Int?   // posición del salto de línea donde se corta
        for i in 0..<min(bytes.count, maxBytes) where bytes[i] == 10 {
            lines += 1
            end = i
            if lines == maxLines { break }
        }
        // Una sola línea enorme, sin saltos: se enseña un trozo, cortado al principio de un carácter.
        var cutAt = end ?? min(bytes.count, 2000)
        while end == nil, cutAt > 0, cutAt < bytes.count, bytes[cutAt] & 0xC0 == 0x80 { cutAt -= 1 }
        guard cutAt < bytes.count, bytes[cutAt...].contains(where: { $0 != 10 }) else { return (text, 0) }
        let rest = bytes[cutAt...].reduce(0) { $1 == 10 ? $0 + 1 : $0 }
        return (String(decoding: bytes[..<cutAt], as: UTF8.self), max(rest, 1))
    }

    var body: some View {
        let _ = BodyCounter.hit("NotePeek")
        let full = path.isEmpty ? "" : store.read(path)
        let (text, cut) = NotePeek.head(full)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold)).lineLimit(2)
                    Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if !inWindow {
                    Button { store.peekNote = nil } label: { Image(systemName: "xmark").accessibilityLabel("Cerrar la nota") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Cerrar la nota")
                }
            }
            HStack {
                Button("Editar en Notas") {
                    if inWindow { openWindow(id: "main") } else { store.peekNote = nil }
                    store.pendingNote = path
                }
                if !inWindow { Button("Otra ventana") { openWindow(id: "nota", value: path) } }
            }
            .controlSize(.small)
            if text.isEmpty {
                EmptyNote("La nota está vacía o ya no existe.", icon: "doc")
            } else {
                NoteBody(text: text, actions: NoteActions(
                    toggle: { store.toggleLine(path, line: $0, raw: $1) },
                    editRow: { _ in store.pendingNote = path },
                    addRow: { _ in store.pendingNote = path },
                    setProperty: { store.setProperty(path, key: $0, value: $1) }))
                if cut > 0 {
                    Button("Sigue: \(cut) \(cut == 1 ? "línea" : "líneas") más. Abrir en Notas") { if !inWindow { store.peekNote = nil }; store.pendingNote = path }
                        .buttonStyle(.accentLink).font(.callout)
                }
            }
        }
    }
}
