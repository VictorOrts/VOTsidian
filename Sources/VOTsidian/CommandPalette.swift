import SwiftUI

struct PaletteItem: Identifiable {
    var id = UUID()
    var icon: String
    var title: String
    var subtitle = ""
    var highlighted: AttributedString? = nil
    var tag = ""
    var run: () -> Void
}

struct CommandPalette: View {
    enum Scope: String, CaseIterable, Identifiable {
        case todo = "Todo", pantallas = "Pantallas", notas = "Notas", tareas = "Tareas", texto = "Texto"
        var id: String { rawValue }
    }
    enum DateFilter: String, CaseIterable { case cualquiera = "Cualquier fecha", vencidas = "Vencidas", hoy = "Hoy", semana = "Próximos 7 días", sinFecha = "Sin fecha" }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ProcessInfo.processInfo.environment["VOT_QUERY"] ?? ""
    @State private var scope = Scope.todo
    @State private var folder = ""
    @State private var dateFilter = DateFilter.cualquiera
    @State private var includeDone = false
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var folders: [String] { Array(Set(store.notes.map(\.folder))).sorted() }

    private func matchesDate(_ t: TaskItem) -> Bool {
        let today = DayKey.today()
        switch dateFilter {
        case .cualquiera: return true
        case .vencidas: return t.due.map { $0 < today } ?? false
        case .hoy: return t.due == today
        case .semana: return t.due.map { $0 >= today && $0 <= DayKey.adding(days: 7, to: today) } ?? false
        case .sinFecha: return t.due == nil
        }
    }

    private var items: [PaletteItem] {
        let q = SearchQuery.parse(query)
        var out: [PaletteItem] = []
        func go(_ s: Screen) -> () -> Void { { store.screen = s; dismiss() } }
        let actions: [PaletteItem] = [
            PaletteItem(icon: "plus.circle", title: "Captura rápida", subtitle: "Tarea, peso, pinchazo o idea", tag: "Acción") { dismiss(); store.showQuickAdd = true },
            PaletteItem(icon: "note.text", title: "Nota de hoy", subtitle: "Abre o crea Diario/hoy.md", tag: "Acción") { store.openToday(); dismiss() },
            PaletteItem(icon: "moon.stars", title: "Cerrar el día", subtitle: "Revisa lo pendiente y prepara mañana", tag: "Acción") { dismiss(); store.showCierre = true },
            PaletteItem(icon: "scalemass", title: "Registrar peso", subtitle: "Ir a Peso", tag: "Acción", run: go(.peso)),
            PaletteItem(icon: "syringe", title: "Registrar pinchazo", subtitle: "Ir a Mounjaro", tag: "Acción", run: go(.mounjaro)),
            PaletteItem(icon: "square.and.pencil", title: "Nueva nota", subtitle: "Ir a Notas", tag: "Acción", run: go(.notas)),
            PaletteItem(icon: "arrow.uturn.backward", title: "Deshacer último cambio", tag: "Acción") { store.undo(); dismiss() },
        ]
        let screens = Screen.allCases.map { s in PaletteItem(icon: s.icon, title: s.rawValue, subtitle: "Pantalla", tag: "Pantalla", run: go(s)) }
        let hasText = !q.tokens.isEmpty
        if let cmd = QuickCommand.parse(query, categories: store.expenseCategories, people: store.people.map(\.name), learned: store.expenseLearned) {
            out.append(PaletteItem(icon: "bolt.fill", title: cmd.summary, subtitle: "intro para hacerlo", tag: "Orden") { store.run(cmd); dismiss() })
        }
        let folderFilter = folder.isEmpty ? nil : folder

        func noteOK(_ n: NoteFile) -> Bool {
            if let ff = folderFilter, n.folder != ff { return false }
            return SearchEngine.passesFilters(path: n.path, folder: n.folder, type: store.noteMeta[n.path]?["tipo"], tags: store.noteTags[n.path] ?? [], q)
        }

        if scope == .todo || scope == .pantallas {
            let pool = scope == .pantallas ? screens : actions + screens
            if q.tags.isEmpty && q.folder == nil && q.type == nil {
                out += pool.filter { !hasText || SearchEngine.matches(MD.fold($0.title + " " + $0.subtitle), q) }
            }
        }
        // Fecha: todo lo que cae ese día
        if let d = q.date, scope == .todo || scope == .tareas {
            let items = (store.agenda(from: d, to: d)[DayKey.string(d)] ?? []).filter { $0.kind != .diary }
            for it in items {
                out.append(PaletteItem(icon: it.kind.icon, title: it.title, subtitle: "\(shortDate(d)) · \(it.detail)", tag: "Ese día") {
                    if let t = it.task { store.pendingNote = t.file } else if let sc = it.screen { store.screen = sc } else if let p = it.path { store.pendingNote = p }
                    dismiss()
                })
            }
            let diary = Store.diaryPath(d)
            if store.notes.contains(where: { $0.path == diary }) {
                out.append(PaletteItem(icon: "note.text", title: "Nota del día", subtitle: shortDate(d), tag: "Ese día") { store.pendingNote = diary; dismiss() })
            }
        }
        if scope == .todo || scope == .notas {
            for n in store.notes where noteOK(n) && (hasText ? SearchEngine.matches(MD.fold(n.name + " " + n.path), q) : (scope == .notas || !q.tags.isEmpty || q.folder != nil || q.type != nil)) {
                out.append(PaletteItem(icon: "doc.text", title: n.name, subtitle: n.folder, tag: "Nota") { store.pendingNote = n.path; dismiss() })
            }
        }
        if scope == .todo || scope == .tareas {
            for t in store.tasks where (includeDone || !t.done) && matchesDate(t) && (q.date == nil || t.due == q.date) {
                let f = NoteFile(path: t.file)
                guard folderFilter == nil || f.folder == folderFilter, SearchEngine.passesFilters(path: t.file, folder: f.folder, type: store.noteMeta[t.file]?["tipo"], tags: store.noteTags[t.file] ?? [], q) else { continue }
                guard hasText ? SearchEngine.matches(MD.fold(t.text + " " + t.noteName), q) : (scope == .tareas && q.date == nil) else { continue }
                let when = t.due.map { " · " + dayLabel($0) } ?? ""
                out.append(PaletteItem(icon: t.done ? "checkmark.circle" : (t.priority == 3 ? "flag.fill" : "circle"), title: t.text, subtitle: "\(t.noteName)\(when)", highlighted: nil, tag: "Tarea") { store.pendingNote = t.file; dismiss() })
            }
        }
        if (scope == .todo || scope == .texto), hasText {
            var hits = 0
            for n in store.notes where hits < 25 && noteOK(n) && (scope == .texto || !SearchEngine.matches(MD.fold(n.name), q)) {
                let text = store.noteTexts[n.path] ?? ""
                guard SearchEngine.matches(store.foldedText(n.path, text), q), let line = SearchEngine.bestLine(in: text, q) else { continue }
                hits += 1
                out.append(PaletteItem(icon: "text.magnifyingglass", title: n.name, subtitle: line, highlighted: SearchEngine.highlight(line, q), tag: "Texto") { store.pendingNote = n.path; dismiss() })
            }
        }
        return out
    }

    var body: some View {
        let list = items
        let shown = Array(list.prefix(60))
        VStack(spacing: 0) {
            TextField("Busca o escribe una orden: peso 105,5 · ánimo 4 · dormí 7,5 · pinchazo hoy · compra leche", text: $query)
                .textFieldStyle(.plain).font(.title3).padding(16).focused($focused)
                .onSubmit { if shown.indices.contains(selection) { shown[selection].run() } }
                .onKeyPress(.downArrow) { selection = min(selection + 1, max(shown.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                .onChange(of: query) { selection = 0 }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("", selection: $scope) { ForEach(Scope.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 340)
                    Spacer()
                    Text(list.count == 1 ? "1 resultado" : "\(list.count) resultados").font(.caption).foregroundStyle(.secondary).fixedSize()
                }
                HStack(spacing: 8) {
                    if scope != .pantallas {
                        ChoiceMenu(options: [""] + folders, current: folder, width: 170, emptyLabel: "Todas las carpetas") { folder = $0 }
                    }
                    if scope == .tareas || scope == .todo {
                        ChoiceMenu(options: DateFilter.allCases.map(\.rawValue), current: dateFilter.rawValue, width: 150) { dateFilter = DateFilter(rawValue: $0) ?? .cualquiera }
                        Toggle("Hechas", isOn: $includeDone).toggleStyle(.checkbox).font(.caption).fixedSize()
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
            .onChange(of: scope) { selection = 0 }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, it in
                            Button(action: it.run) {
                                HStack(spacing: 12) {
                                    Image(systemName: it.icon).frame(width: 22).foregroundStyle(Brand.accent)
                                    Text(it.title).lineLimit(1)
                                    Spacer()
                                    if let h = it.highlighted { Text(h).font(.caption).foregroundStyle(.secondary).lineLimit(1) } else { Text(it.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    if !it.tag.isEmpty { Text(it.tag).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1).background(Color.primary.opacity(0.08), in: Capsule()) }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(i == selection ? Brand.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(i)
                        }
                        if shown.isEmpty { Text(query.isEmpty && scope != .notas && scope != .tareas ? "Empieza a escribir" : "Sin resultados").foregroundStyle(.secondary).padding(16) }
                    }.padding(8)
                }
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
            .frame(height: 340)
        }
        .frame(width: 680)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
    }
}

struct QuickAddSheet: View {
    enum Kind: String, CaseIterable, Identifiable { case tarea = "Tarea", gasto = "Gasto", peso = "Peso", pinchazo = "Pinchazo", idea = "Idea"; var id: String { rawValue } }

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.tarea
    @State private var text = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var kg = ""
    @State private var date = Date()
    @State private var dose = 7.5
    @State private var site = "Abdomen izquierdo"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Captura rápida").font(.title3.weight(.semibold))
            Picker("", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            switch kind {
            case .tarea:
                TextField("Qué hay que hacer (ej: llamar al dentista el viernes)", text: $text).focused($focused).onSubmit(save)
                HStack { Toggle("Fecha", isOn: $hasDue).toggleStyle(.checkbox); DatePicker("", selection: $due, displayedComponents: .date).labelsHidden().disabled(!hasDue) }
                if !hasDue, let d = NaturalDate.extract(text).date { Label("Se guardará para \(longDate(d))", systemImage: "calendar").font(.caption).foregroundStyle(Brand.accent) }
                else { Text("Va al Inbox. Puedes escribir la fecha en la frase: “mañana”, “el viernes”, “25/11”, “en 3 días”.").font(.caption).foregroundStyle(.secondary) }
            case .gasto:
                TextField("22 € cena con Ana, gasolina 48, ayer 12,50 Mercadona", text: $text).focused($focused).onSubmit(save)
                if let p = store.parseExpense(text) {
                    Label("\(p.amount < 0 ? "Devolución de \(Money.exact(-p.amount))" : Money.exact(p.amount)) en \(p.category ?? "Imprevistos") · \(p.date == DayKey.today() ? "hoy" : longDate(p.date))", systemImage: "creditcard")
                        .font(.caption).foregroundStyle(Brand.accent)
                } else { Text("Se apunta en la nota del mes de Gastos. La partida se adivina por las palabras.").font(.caption).foregroundStyle(.secondary) }
            case .idea:
                TextField("Idea", text: $text).focused($focused).onSubmit(save)
                Text("Se añade a Ideas, en el Inbox.").font(.caption).foregroundStyle(.secondary)
            case .peso:
                HStack { TextField("kg", text: $kg).frame(width: 100).focused($focused).onSubmit(save); DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden() }
                TextField("Notas (opcional)", text: $text)
            case .pinchazo:
                HStack {
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                    Picker("", selection: $dose) { ForEach(mounjaroDoses, id: \.self) { Text(MD.formatNumber($0, comma: true) + " mg").tag($0) } }.labelsHidden().frame(width: 110)
                    Picker("", selection: $site) { ForEach(injectionSites, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 170)
                }
                TextField("Notas (opcional)", text: $text)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!valid)
            }
        }
        .padding(22).frame(width: 460)
        .onAppear { focused = true; if let mg = store.mounjaro.last?.mg { dose = mg }; site = store.mounjaro.suggestedSite }
        .onChange(of: kind) { focused = true }
    }

    private var valid: Bool {
        switch kind {
        case .tarea, .idea: !text.trimmingCharacters(in: .whitespaces).isEmpty
        case .gasto: store.parseExpense(text) != nil
        case .peso: MD.number(kg) != nil
        case .pinchazo: true
        }
    }

    private func save() {
        guard valid else { return }
        let t = text.trimmingCharacters(in: .whitespaces)
        let day = DayKey.calendar().startOfDay(for: date)
        switch kind {
        case .tarea:
            let p = NaturalDate.extractTask(t)
            store.addTask(hasDue ? t : p.text, due: hasDue ? DayKey.calendar().startOfDay(for: due) : p.date, recurrence: hasDue ? nil : p.recurrence, priority: hasDue ? 0 : p.priority)
        case .idea: store.addIdea(t)
        case .gasto: if let p = store.parseExpense(t) { store.addExpense(p) }
        case .peso: if let v = MD.number(kg) { store.addWeight(date: day, kg: v, note: t) }
        case .pinchazo: store.addDose(date: day, dose: dose, site: site, note: t)
        }
        dismiss()
    }
}
