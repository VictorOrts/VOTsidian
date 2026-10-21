import SwiftUI

struct SemanaView: View {
    @Environment(Store.self) private var store
    @State private var offset = 0
    @State private var draft = WeekReview(key: "")
    @State private var fechasText = ""
    @State private var base = WeekReview(key: "")
    @State private var baseFechas = ""
    @State private var saved = false
    @State private var showHabits = false

    private var monday: Date { DayKey.adding(days: offset * 7, to: DayKey.weekStart(Date())) }
    private var key: String { DayKey.weekKey(monday) }

    var body: some View {
        let review = store.reviews[key]
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left").accessibilityLabel("Anterior") }
                    Text("Revisión semanal \(key)").font(.title3.weight(.semibold))
                    Button { offset += 1 } label: { Image(systemName: "chevron.right").accessibilityLabel("Siguiente / abrir") }.disabled(offset >= 0)
                    if offset != 0 { Button("Esta semana") { offset = 0 } }
                    Spacer()
                    Text("\(shortDate(monday)) – \(shortDate(DayKey.adding(days: 6, to: monday)))").foregroundStyle(.secondary)
                    Button { showHabits = true } label: { Label("Hábitos", systemImage: "slider.horizontal.3") }.controlSize(.small)
                }

                if let review {
                    weekTiles(review)
                    habitGrid(review)
                    doneCard
                    Card(title: "Mirar atrás", icon: "arrow.uturn.backward") {
                        TextField("Logros", text: $draft.logros, axis: .vertical).lineLimit(1...4)
                        LinkPreview(text: draft.logros)
                        Button { fillAchievements() } label: { Label("Rellenar logros con las tareas hechas", systemImage: "sparkles") }.controlSize(.small)
                        TextField("Lo que no salió", text: $draft.noSalio, axis: .vertical).lineLimit(1...4)
                        LinkPreview(text: draft.noSalio)
                    }
                    Card(title: "Semana siguiente", icon: "target") {
                        ForEach(0..<3, id: \.self) { i in
                            TextField("Objetivo \(i + 1)", text: $draft.objetivos[i])
                            LinkPreview(text: draft.objetivos[i])
                        }
                        Button { objectivesToTasks() } label: { Label("Convertir objetivos en tareas", systemImage: "checklist") }
                            .controlSize(.small).disabled(draft.objetivos.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                        Text("Fechas importantes").font(.subheadline.weight(.semibold))
                        TextEditor(text: $fechasText).frame(minHeight: 70).font(.body)
                            .scrollContentBackground(.hidden).padding(6)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        ForEach(fechasText.components(separatedBy: "\n").filter { $0.contains("[[") }, id: \.self) { LinkPreview(text: $0) }
                    }
                    HStack {
                        Button("Guardar revisión") { saveWeek(quiet: false) }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
                        if saved { Label("Guardado", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        Spacer()
                        Button("Editar la nota completa") { store.pendingNote = store.reviewFile(key) }.buttonStyle(.link)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Sin revisión para \(key)", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Se crea Revisiones/Revisión semanal \(key).md con el mismo formato que tus otras semanas.")
                    } actions: {
                        Button("Crear revisión") { store.createReview(key: key, monday: monday) }.buttonStyle(.borderedProminent)
                    }
                }
                trend
                heatmap
            }
            .padding(24)
        }
        .navigationTitle("Revisión semanal")
        .onAppear { autoCreate(); load() }
        .onChange(of: key) { autoCreate(); load() }
        .onChange(of: store.reviews[key]) { if textsUnchanged { load() } }
        .onChange(of: draft) { if !textsUnchanged { saved = false } }
        .autosave(on: WeekSnapshot(draft: draft, fechas: fechasText)) { if !textsUnchanged, store.reviews[key] != nil { saveWeek(quiet: true) } }
        .sheet(isPresented: $showHabits) { HabitsSheet() }
    }

    /// La revisión de la semana en curso se crea sola al entrar, con los hábitos de la anterior.
    private func autoCreate() {
        if offset == 0, store.reviews[key] == nil { store.createReview(key: key, monday: monday) }
    }

    private func saveWeek(quiet: Bool) {
        draft.fechas = fechasText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        store.saveReviewText(key: key, draft, quiet: quiet)
        base = draft; baseFechas = fechasText
        saved = true
    }

    /// Los campos de texto no tienen cambios sin guardar, así que se pueden recargar sin perder nada.
    private var textsUnchanged: Bool {
        draft.logros == base.logros && draft.noSalio == base.noSalio && draft.objetivos == base.objetivos && fechasText == baseFechas
    }

    private func load() {
        draft = store.reviews[key] ?? WeekReview(key: key)
        fechasText = draft.fechas.joined(separator: "\n")
        base = draft
        baseFechas = fechasText
        saved = false
    }

    private func weekTiles(_ r: WeekReview) -> some View {
        let pct = r.totalPossible > 0 ? Double(r.totalDone) / Double(r.totalPossible) : 0
        let prevKey = DayKey.weekKey(DayKey.adding(days: -7, to: monday))
        let prev = store.reviews[prevKey]
        let prevPct = prev.flatMap { $0.totalPossible > 0 ? Double($0.totalDone) / Double($0.totalPossible) : nil }
        let best = r.habits.max { $0.count < $1.count }
        return HStack(spacing: 12) {
            Tile(title: "Cumplimiento", value: "\(Int(pct * 100)) %", note: "\(r.totalDone) de \(r.totalPossible) hábitos", tint: pct >= 0.8 ? Brand.accent : nil)
            Tile(title: "Semana anterior", value: prevPct.map { "\(Int($0 * 100)) %" } ?? "–", note: prevPct == nil ? "sin revisión previa" : prevKey)
            Tile(title: "Racha", value: "\(streak) \(streak == 1 ? "semana" : "semanas")", note: "seguidas con 80 % o más", tint: streak >= 3 ? Brand.accent : nil)
            Tile(title: "Mejor hábito", value: best.map { $0.count > 0 ? $0.name : "–" } ?? "–", note: best.flatMap { $0.count > 0 ? "\($0.count) / 7 días" : nil })
        }
    }

    /// Mapa de calor estilo GitHub: cada columna es una semana y cada fila un día; más oscuro = más hábitos cumplidos.
    private var heatmap: some View {
        let keys = (0..<12).map { DayKey.weekKey(DayKey.adding(days: -$0 * 7, to: DayKey.weekStart(Date()))) }.reversed()
        let weeks = Array(keys)
        return Card(title: "Mapa de calor · 12 semanas", icon: "square.grid.3x3.fill") {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(height: 18) }
                }
                ForEach(weeks, id: \.self) { k in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let r = store.reviews[k]
                            let total = r?.habits.count ?? 0
                            let done = r?.habits.filter { $0.days[d] }.count ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(total == 0 ? Color.secondary.opacity(0.1) : Brand.accent.opacity(done == 0 ? 0.12 : 0.25 + 0.75 * Double(done) / Double(total)))
                                .frame(width: 18, height: 18)
                                .help(total == 0 ? "Sin revisión" : "\(done) de \(total) hábitos")
                        }
                        Text(k.suffix(2)).font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            }
            Text("Cada cuadro es un día. Gris: semana sin revisión.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var streak: Int {
        let keys = store.reviews.keys.sorted().reversed().filter { $0 <= key }
        var n = 0
        for k in keys {
            guard let r = store.reviews[k], r.totalPossible > 0 else { break }
            let pct = Double(r.totalDone) / Double(r.totalPossible)
            if pct >= 0.8 { n += 1 } else if k == key { continue } else { break }
        }
        return n
    }

    private var doneCard: some View {
        let end = DayKey.adding(days: 6, to: monday)
        let done = store.tasks.filter { t in t.done && (t.completed.map { $0 >= monday && $0 <= end } ?? false) }
        return Card(title: "Hecho esta semana", icon: "checkmark.seal") {
            if done.isEmpty { Text("Ninguna tarea completada con fecha en estos días.").foregroundStyle(.secondary) }
            ForEach(done) { t in
                HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.accent); Text(MDParser.inline(t.text)); Spacer(); Text(t.noteName).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func fillAchievements() {
        let end = DayKey.adding(days: 6, to: monday)
        let done = store.tasks.filter { t in t.done && (t.completed.map { $0 >= monday && $0 <= end } ?? false) }.map(\.text)
        guard !done.isEmpty else { return }
        draft.logros = draft.logros.isEmpty ? done.joined(separator: "; ") : draft.logros + "; " + done.joined(separator: "; ")
    }

    private func objectivesToTasks() {
        let due = DayKey.adding(days: 13, to: monday)
        store.addTasks(draft.objetivos.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { ($0, due) })
    }

    private func habitGrid(_ r: WeekReview) -> some View {
        Card(title: "Hábitos de la semana", icon: "checkmark.square") {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(r.habits, id: \.name) { h in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(h.name)
                            if !h.criterion.isEmpty { Text(h.criterion).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        }.frame(maxWidth: 190, alignment: .leading).gridColumnAlignment(.leading)
                        ForEach(0..<7, id: \.self) { d in
                            Button { store.toggleHabit(key: key, habit: h.name, day: d) } label: {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(h.days[d] ? Brand.accent : Color.secondary.opacity(0.16))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .overlay { if h.days[d] { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } }
                            }.buttonStyle(.plain)
                            .accessibilityLabel("\(h.name), día \(d + 1)")
                            .accessibilityValue(h.days[d] ? "hecho" : "pendiente")
                        }
                        Text("\(h.count) / 7").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var trend: some View {
        let keys = (0..<8).map { DayKey.weekKey(DayKey.adding(days: -$0 * 7, to: DayKey.weekStart(Date()))) }.reversed()
        let habits = store.habitNames
        return Card(title: "Últimas 8 semanas", icon: "chart.bar") {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(Array(keys), id: \.self) { Text($0.suffix(3)).font(.caption2).foregroundStyle(.secondary) }
                    Text("8 sem").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(habits, id: \.self) { h in
                    GridRow {
                        Text(h).gridColumnAlignment(.leading)
                        ForEach(Array(keys), id: \.self) { k in
                            let c = store.reviews[k]?.habits.first { MD.fold($0.name) == MD.fold(h) }?.count
                            RoundedRectangle(cornerRadius: 4)
                                .fill(c == nil ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.15 + 0.85 * Double(c!) / 7))
                                .frame(width: 34, height: 22)
                                .overlay { if let c { Text("\(c)").font(.caption2).foregroundStyle(c >= 5 ? .white : .primary) } }
                        }
                        let counts = keys.compactMap { k in store.reviews[k]?.habits.first { MD.fold($0.name) == MD.fold(h) }?.count }
                        Text(counts.isEmpty ? "–" : "\(Int(Double(counts.reduce(0, +)) / Double(counts.count * 7) * 100)) %")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Text("Días cumplidos por semana. Gris: sin revisión.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct HabitsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var defs: [HabitDef] = []
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hábitos").font(.title3.weight(.semibold))
            Text("Nombre y qué cuenta como cumplido.").font(.callout).foregroundStyle(.secondary)
            ForEach(defs.indices, id: \.self) { i in
                HStack {
                    TextField("Hábito", text: $defs[i].name).frame(width: 150)
                    TextField("Qué cuenta como cumplido", text: $defs[i].criterion)
                    Button { defs.remove(at: i) } label: { Image(systemName: "minus.circle").accessibilityLabel("Quitar") }.buttonStyle(.borderless).foregroundStyle(.red)
                }
            }
            HStack {
                TextField("Nuevo hábito", text: $newName).frame(width: 150).onSubmit(add)
                Button("Añadir", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Se aplica a la revisión de esta semana y a las que crees después. Las semanas pasadas no cambian.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    store.saveHabits(defs.map { HabitDef(name: $0.name.trimmingCharacters(in: .whitespaces), criterion: $0.criterion.trimmingCharacters(in: .whitespaces)) }.filter { !$0.name.isEmpty })
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(minWidth: 620)
        .onAppear { defs = store.habitDefs }
    }

    private func add() {
        let t = newName.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        defs.append(HabitDef(name: t)); newName = ""
    }
}

struct WeekSnapshot: Equatable { var draft: WeekReview; var fechas: String }
