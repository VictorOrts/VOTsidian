import SwiftUI

// MARK: - Bases: calendario y tablero
//
// Las notas de una base, por una propiedad de fecha (calendario) o por una de pocos valores (tablero). Arrastrar una nota cambia
// esa propiedad en su encabezado, y se deshace con ⌥⌘Z como cualquier otro cambio.

/// Una nota de la base como tarjeta que se puede arrastrar.
private struct BaseCard: View {
    @Environment(Store.self) private var store
    let path: String
    var details: [String] = []
    var compact = false

    var body: some View {
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let meta = store.noteMeta[path] ?? [:]
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(compact ? .caption : .callout.weight(.medium)).lineLimit(compact ? 1 : 2)
            if !compact {
                ForEach(details.filter { !(meta[$0] ?? "").isEmpty }.prefix(2), id: \.self) { k in
                    Text("\(BasesView.pretty(k)): \(meta[k] ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, compact ? 5 : 9).padding(.vertical, compact ? 2 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.accent.opacity(compact ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.pendingNote = path }
        .draggable(path)
        .help("\(title). Arrastra para cambiarla de \(compact ? "día" : "columna"); doble clic para abrirla.")
    }
}

/// Calendario de un mes con las notas en el día de `dateKey`.
struct BaseCalendarView: View {
    @Environment(Store.self) private var store
    let paths: [String]
    let dateKey: String
    @State private var month = DayKey.calendar().dateInterval(of: .month, for: Date())!.start
    @State private var targeted: String?

    var body: some View {
        let cal = DayKey.calendar()
        let (days, undated) = BaseQuery.byDay(paths: paths, meta: store.noteMeta, key: dateKey)
        let start = DayKey.weekStart(month)
        let weeks = Int(ceil(Double(DayKey.days(from: start, to: cal.date(byAdding: .month, value: 1, to: month)!)) / 7))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").accessibilityLabel("Mes anterior") }
                Text(capitalizedFirst(DayKey.esLong(month, .dateTime.month(.wide).year()))).font(.headline).frame(minWidth: 150)
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").accessibilityLabel("Mes siguiente") }
                Button("Hoy") { month = cal.dateInterval(of: .month, for: Date())!.start }
                Spacer()
            }.buttonStyle(.borderless)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow { ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }
                ForEach(0..<weeks, id: \.self) { w in
                    GridRow {
                        ForEach(0..<7, id: \.self) { d in
                            let day = DayKey.adding(days: w * 7 + d, to: start)
                            cell(day, items: days[DayKey.string(day)] ?? [], inMonth: cal.isDate(day, equalTo: month, toGranularity: .month))
                        }
                    }
                }
            }
            if !undated.isEmpty {
                Text("Sin \(BasesView.pretty(dateKey).lowercased()) · arrástralas a un día").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) { ForEach(undated, id: \.self) { BaseCard(path: $0, compact: true).fixedSize() } }
            }
        }
    }

    private func cell(_ day: Date, items: [String], inMonth: Bool) -> some View {
        let key = DayKey.string(day)
        let isToday = day == DayKey.today()
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(DayKey.calendar().component(.day, from: day))").font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Brand.accent : inMonth ? Color.primary : Color.secondary.opacity(0.5))
            ForEach(items.prefix(3), id: \.self) { BaseCard(path: $0, compact: true) }
            if items.count > 3 { Text("+\(items.count - 3) más").font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(targeted == key ? Brand.accent.opacity(0.18) : Color.primary.opacity(inMonth ? 0.04 : 0.015), in: RoundedRectangle(cornerRadius: Brand.radiusSmall))
        .dropDestination(for: String.self) { dropped, _ in
            for path in dropped { store.setProperty(path, key: dateKey, value: BaseQuery.format(day, like: store.noteMeta[path]?[dateKey])) }
            return !dropped.isEmpty
        } isTargeted: { targeted = $0 ? key : (targeted == key ? nil : targeted) }
    }
}

/// Tablero con una columna por cada valor de `groupKey`.
struct BaseBoardView: View {
    @Environment(Store.self) private var store
    let paths: [String]
    let groupKey: String
    let details: [String]
    @State private var targeted: String?

    var body: some View {
        let columns = BaseQuery.columns(paths: paths, meta: store.noteMeta, key: groupKey)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(columns, id: \.value) { col in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(col.value.isEmpty ? "Sin \(BasesView.pretty(groupKey).lowercased())" : col.value).font(.subheadline.weight(.semibold))
                            Text("\(col.paths.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(col.paths.prefix(60), id: \.self) { BaseCard(path: $0, details: details.filter { $0 != groupKey }) }
                        if col.paths.count > 60 { Text("y \(col.paths.count - 60) más").font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: 230, alignment: .topLeading)
                    .frame(minHeight: 160, alignment: .topLeading)
                    .background(targeted == col.value ? Brand.accent.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Brand.radius))
                    .dropDestination(for: String.self) { dropped, _ in
                        for path in dropped { store.setProperty(path, key: groupKey, value: col.value) }
                        return !dropped.isEmpty
                    } isTargeted: { targeted = $0 ? col.value : (targeted == col.value ? nil : targeted) }
                }
            }
            .padding(.bottom, 6)
        }
    }
}
