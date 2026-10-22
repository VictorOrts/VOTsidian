import SwiftUI

struct BoardCard: Identifiable {
    var id: String
    var title: String
    var subtitle = ""
    var badge = ""
    var color: Color = Brand.accent
}

/// Tablero tipo Kanban: arrastra una tarjeta a otra columna para cambiar su estado.
struct StatusBoard: View {
    let columns: [String]
    let cards: [String: [BoardCard]]
    var columnWidth: CGFloat = 220
    var open: ((String) -> Void)? = nil
    let move: (String, String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns, id: \.self) { col in
                    let items = cards[col] ?? []
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(col.isEmpty ? "Sin estado" : col.capitalized).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(items) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.title).font(.callout.weight(.medium)).lineLimit(2)
                                if !c.subtitle.isEmpty { Text(c.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                if !c.badge.isEmpty { Text(c.badge).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1).background(c.color.opacity(0.2), in: Capsule()).foregroundStyle(c.color) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Brand.radius))
                            .overlay(RoundedRectangle(cornerRadius: Brand.radius).stroke(Color.primary.opacity(0.08)))
                            .draggable(c.id)
                            .onTapGesture { open?(c.id) }
                        }
                        if items.isEmpty { Text("Suelta aquí").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 44) }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: columnWidth, alignment: .topLeading)
                    .frame(minHeight: 140)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: Brand.radius))
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        move(id, col)
                        return true
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
