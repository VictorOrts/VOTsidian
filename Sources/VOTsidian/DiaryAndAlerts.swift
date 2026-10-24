import SwiftUI

/// Avisos agrupados por urgencia: icono en un círculo del color de su nivel, texto y, si se puede, el botón que lo resuelve.
struct AlertList: View {
    @Environment(Store.self) private var store
    let alerts: [Alert]
    var limit: Int? = nil
    /// Texto cuando no hay avisos.
    var emptyText = "No hay nada urgente ni próximo."
    /// Adónde lleva un aviso. Sin él (dentro de la propia pantalla del módulo) el aviso no es un botón ni lleva flecha.
    var go: ((Screen) -> Void)? = nil

    private static let groups: [(Alert.Level, String)] = [(.urgent, "Ahora"), (.soon, "Pronto"), (.info, "Para saber")]

    private func color(_ l: Alert.Level) -> Color { l == .urgent ? Brand.bad : l == .soon ? Brand.warn : Brand.info }

    var body: some View {
        let _ = BodyCounter.hit("AlertList")
        let shown = limit.map { Array(alerts.prefix($0)) } ?? alerts
        if alerts.isEmpty { EmptyNote(emptyText, icon: "checkmark.circle") }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.groups, id: \.0) { level, title in
                let items = shown.filter { $0.level == level }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        // Sin título si todo es del mismo nivel: no aporta nada.
                        if Set(shown.map(\.level)).count > 1 {
                            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(color(level))
                        }
                        ForEach(items) { a in row(a) }
                    }
                }
            }
            if let limit, alerts.count > limit {
                if let go { Button("Ver los \(alerts.count) avisos") { go(.avisos) }.buttonStyle(.accentLink).font(.callout) }
            }
        }
    }

    private func row(_ a: Alert) -> some View {
        let content = HStack(spacing: 10) {
            Image(systemName: a.icon).font(.callout).foregroundStyle(color(a.level))
                .frame(width: 28, height: 28).background(color(a.level).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(a.text).fixedSize(horizontal: false, vertical: true)
                if go != nil { Text(store.title(a.screen)).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
        }.contentShape(Rectangle())
        return HStack(spacing: 10) {
            if let go { Button { go(a.screen) } label: { content }.buttonStyle(.plain) } else { content }
            if let action = a.action {
                Button(action.title) { store.perform(action) }.controlSize(.small)
            }
            if go != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 2)
    }
}
