import SwiftUI

/// Número para mostrar en español: coma decimal y `digits` decimales fijos («105,0»). Para escribir en notas usa `MD.formatNumber`.
func fmt(_ v: Double?, _ digits: Int = 1, unit: String = "") -> String {
    guard let v else { return "–" }
    return v.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(Locale(identifier: "es_ES"))) + unit
}

func fmtDelta(_ v: Double?, unit: String = " kg") -> String {
    guard let v else { return "–" }
    return (v >= 0 ? "+" : "") + fmt(v, 1, unit: unit)
}

func shortDate(_ d: Date) -> String { DayKey.esLong(d, .dateTime.day().month(.abbreviated)) }
/// Fecha para tarjetas y textos: «18 oct», y «18 oct 2025» si no es de este año.
func dayLabel(_ d: Date) -> String {
    let cal = DayKey.calendar()
    return cal.component(.year, from: d) == cal.component(.year, from: Date()) ? shortDate(d) : DayKey.esLong(d, .dateTime.day().month(.abbreviated).year())
}
func longDate(_ d: Date) -> String { DayKey.esLong(d, .dateTime.weekday(.wide).day().month(.wide)) }

/// «1 día», «3 días»: cuenta con la palabra en singular o plural.
func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

func relativeDays(_ n: Int) -> String {
    switch n {
    case 0: "hoy"
    case 1: "mañana"
    case -1: "ayer"
    case let x where x > 0: "en \(x) días"
    default: "hace \(-n) días"
    }
}

/// Para lo que ya tocaba: «3 días tarde» en vez de «hace 3 días», que se lee como si ya estuviera hecho.
func dueDays(_ n: Int) -> String {
    n < 0 ? "\(-n) \(n == -1 ? "día" : "días") tarde" : relativeDays(n)
}

struct Tile: View {
    let title: String
    let value: String
    var note: String? = nil
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            // Un cero o un «–» no dicen nada: van atenuados y sin color, para que destaque lo que sí importa.
            let empty = value == "0" || value == "–"
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(empty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint ?? .primary)).lineLimit(1).minimumScaleFactor(0.7)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous).stroke(.quaternary.opacity(0.6), lineWidth: 0.5))
    }
}

/// Solo el icono cuando no cabe el texto (barras de botones con el panel Hoy abierto); el texto sigue en la ayuda.
struct CompactLabelStyle: LabelStyle {
    var iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { Label(configuration).labelStyle(.iconOnly) } else { Label(configuration).labelStyle(.titleAndIcon) }
    }
}

/// Fila de `Tile`: todas con la altura de la más alta (una nota de dos líneas descolocaba los valores de las demás).
struct TileRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) { content }.fixedSize(horizontal: false, vertical: true)
    }
}

struct Card<Content: View>: View {
    let title: String
    var icon: String? = nil
    /// Explicación de la tarjeta: sale en un ⓘ de la cabecera en vez de ocupar una línea al final.
    var info: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label { Text(title) } icon: { Image(systemName: icon ?? "circle").foregroundStyle(Brand.accent) }
                    .labelStyle(.titleAndIcon).font(.headline)
                if let info { InfoButton(text: info) }
                Spacer()
                if let actionTitle, let action {
                    Button(action: action) { Text("\(actionTitle) ›") }.buttonStyle(.accentLink).font(.callout)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Brand.radiusLarge, style: .continuous).stroke(.quaternary.opacity(0.6), lineWidth: 0.5))
    }
}

/// «Ver las 300» / «Ver solo las últimas 40» bajo una lista recortada. Una lista de cientos de filas se pinta entera cada vez
/// que cambia algo, así que por defecto se enseñan solo las últimas.
struct ShowAllButton: View {
    let total: Int
    let limit: Int
    var noun = "filas"
    @Binding var showAll: Bool

    var body: some View {
        if total > limit {
            HStack(spacing: 8) {
                if !showAll { Text("Se ven \(limit) de \(total).").font(.caption).foregroundStyle(.secondary) }
                Button(showAll ? "Ver solo \(limit)" : "Ver las \(total) \(noun)") { showAll.toggle() }.buttonStyle(.accentLink).font(.callout)
            }
        }
    }
}

/// Aviso de «no hay nada» dentro de una tarjeta. Mismo aspecto en toda la app: icono tenue y texto secundario.
struct EmptyNote: View {
    let text: String
    var icon = "tray"

    init(_ text: String, icon: String = "tray") { self.text = text; self.icon = icon }

    var body: some View {
        Label { Text(text).foregroundStyle(.secondary) } icon: { Image(systemName: icon).foregroundStyle(.tertiary) }
            .font(.callout)
    }
}

/// Coloca las vistas en fila y pasa a la siguiente línea cuando no caben (etiquetas, filtros…).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.items + [i], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// ⓘ que enseña una explicación al pasar el ratón o al pulsarlo.
struct InfoButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle").accessibilityLabel("Más información") }
            .buttonStyle(.plain).foregroundStyle(.tertiary).help(text)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 300).padding(12)
            }
    }
}

struct Ring<Content: View>: View {
    var progress: Double
    var color: Color = Brand.accent
    var line: CGFloat = 12
    var size: CGFloat = 112
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: size, height: size)
        .padding(line / 2)
    }
}

func capitalizedFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

struct TaskRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @State private var editing = false
    @State private var hover = false

    var body: some View {
        let _ = BodyCounter.hit("TaskRow")
        HStack(spacing: 8) {
            Button { store.setTask(task, done: !task.done) } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(.plain).accessibilityLabel(task.done ? "Marcar como pendiente" : "Marcar como hecha").foregroundStyle(task.done ? Brand.good : Brand.accent)
            if task.priority > 0 && !task.done { Image(systemName: "flag.fill").font(.caption).foregroundStyle(task.priority == 3 ? Brand.bad : task.priority == 2 ? Brand.warn : Brand.info).help(["", "Prioridad baja", "Prioridad media", "Prioridad alta"][task.priority]).accessibilityLabel(["", "Prioridad baja", "Prioridad media", "Prioridad alta"][task.priority]) }
            Text(MDParser.inline(task.text)).strikethrough(task.done).foregroundStyle(task.done ? .secondary : .primary).lineLimit(2)
            if task.muted { Image(systemName: "bell.slash").font(.caption).foregroundStyle(.secondary).help("Sin aviso en Calendar ni notificaciones").accessibilityLabel("Sin aviso") }
            if let r = task.recurrence { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary).help(Recurrence.describe(r)).accessibilityLabel(Recurrence.describe(r)) }
            Spacer(minLength: 8)
            if let due = task.due {
                let n = DayKey.days(from: DayKey.today(), to: due)
                Text((n < 0 && !task.done ? "vencida \(dayLabel(due))" : dayLabel(due)) + (task.time.map { " · \(TimeOfDay.text($0))" } ?? ""))
                    .font(.caption).foregroundStyle(n < 0 && !task.done ? Brand.bad : .secondary)
            }
            Button(task.noteName) { store.pendingNote = task.file }
                .buttonStyle(.accentLink).font(.caption)
            // Aplazar y editar solo se ven al pasar el ratón por la fila: así la lista no se llena de iconos repetidos.
            HStack(spacing: 8) {
                if !task.done {
                    Menu {
                        Button("Hoy") { store.reschedule(task, to: DayKey.today()) }
                        Button("Mañana") { store.reschedule(task, to: DayKey.adding(days: 1, to: DayKey.today())) }
                        Button("En una semana") { store.reschedule(task, to: DayKey.adding(days: 7, to: DayKey.today())) }
                        Button("El lunes") {
                            let wd = DayKey.calendar().component(.weekday, from: DayKey.today())
                            store.reschedule(task, to: DayKey.adding(days: (9 - wd) % 7 == 0 ? 7 : (9 - wd) % 7, to: DayKey.today()))
                        }
                    } label: { Image(systemName: "clock.arrow.circlepath").accessibilityLabel("Aplazar") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).help("Aplazar")
                }
                EditButton { editing = true }
            }
            .opacity(hover || editing ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            if !task.done {
                let m = task.duration ?? 25
                Button("Empezar enfoque (\(TaskDuration.human(m)))") { store.startFocus(task.text, minutes: m) }
            }
            Button("Editar…") { editing = true }
            Button("Ver la nota «\(task.noteName)» al lado") { store.peekNote = task.file }
        }
        .sheet(isPresented: $editing) { TaskSheet(task: task) }
    }
}

extension View {
    /// Limita el contenido a `Brand.contentWidth` y lo centra en ventanas grandes.
    func readableWidth() -> some View { frame(maxWidth: Brand.contentWidth).frame(maxWidth: .infinity) }

    /// Si `day` enseñaba hoy cuando cambia el día (medianoche, el Mac despierta), pasa al día nuevo. Vale también para la fecha
    /// de un formulario (`Date()`, con hora): si no, con la app abierta toda la noche, el peso de la mañana se apuntaba ayer.
    func followsToday(_ day: Binding<Date>) -> some View { modifier(FollowsToday(day: day)) }
}

private struct FollowsToday: ViewModifier {
    @Environment(Store.self) private var store
    @Binding var day: Date

    func body(content: Content) -> some View {
        content.onChange(of: store.today) { old, new in
            if let moved = DayKey.following(day, from: old, to: new) { day = moved }
        }
    }
}

/// Enlace con el color de la app: el `.link` del sistema siempre es azul. Se subraya al pasar el ratón.
struct AccentLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LinkLabel(configuration: configuration) }

    private struct LinkLabel: View {
        let configuration: Configuration
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .foregroundStyle(enabled ? Brand.accent : Color.secondary)
                .underline(hover && enabled)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .pointerStyle(.link)
        }
    }
}

extension ButtonStyle where Self == AccentLinkStyle {
    static var accentLink: AccentLinkStyle { AccentLinkStyle() }
}

/// Colores de la app. Usa estos en vez de los del sistema (`.green`, `.blue`…) para que todo combine en claro y oscuro.
enum Brand {
    static let accent = Color(red: 0.16, green: 0.62, blue: 0.50)
    static let warn = Color(red: 0.93, green: 0.55, blue: 0.20)
    static let bad = Color(red: 0.88, green: 0.28, blue: 0.25)
    /// Lo que va bien (kilos perdidos, hecho, guardado): el verde de la app, no el del sistema.
    static let good = accent
    /// Datos neutros y previsiones (proyecciones, prioridad baja, diario).
    static let info = Color(red: 0.29, green: 0.50, blue: 0.86)

    // Categorías (calendario, nutrición, gráficas): tonos medios que se distinguen entre sí y con el acento.
    static let violet = Color(red: 0.56, green: 0.38, blue: 0.82)
    static let amber = Color(red: 0.86, green: 0.64, blue: 0.16)
    static let sky = Color(red: 0.22, green: 0.66, blue: 0.86)
    static let rose = Color(red: 0.86, green: 0.36, blue: 0.62)
    static let clay = Color(red: 0.70, green: 0.48, blue: 0.34)
    static let lime = Color(red: 0.52, green: 0.70, blue: 0.26)
    static let slate = Color(red: 0.46, green: 0.52, blue: 0.60)
    /// Esquinas: controles y resaltados pequeños, filas y paneles, tarjetas.
    static let radiusSmall: CGFloat = 6
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 16
    /// Ancho máximo del contenido de las pantallas de tarjetas: más ancho, las líneas se leen mal.
    static let contentWidth: CGFloat = 1100

    /// Para series sin significado propio (carpetas del grafo…).
    static let series: [Color] = [accent, amber, info, violet, clay, sky, rose, lime, slate, bad]
}
