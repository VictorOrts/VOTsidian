import SwiftUI

/// Cinco círculos de 1 (mal) a 5 (genial). Pulsar el mismo valor otra vez lo quita.
struct MoodPicker: View {
    let value: Double?
    let set: (Double?) -> Void
    private let labels = ["Mal", "Regular", "Normal", "Bien", "Genial"]
    private let colors: [Color] = [Brand.bad, Brand.warn, Brand.amber, Brand.lime, Brand.accent]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { n in
                let on = value.map { Int($0) == n } ?? false
                Button { set(on ? nil : Double(n)) } label: {
                    Text("\(n)").font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                        // Sin elegir: gris con el número en su color. Elegido: relleno sólido y un aro, para que se vea de un vistazo.
                        .foregroundStyle(on ? Color.white : colors[n - 1])
                        .background(on ? colors[n - 1] : Color.secondary.opacity(0.12), in: Circle())
                        .overlay { if on { Circle().stroke(colors[n - 1].opacity(0.35), lineWidth: 3).padding(-3) } }
                        .scaleEffect(on ? 1.12 : 1)
                        .animation(.spring(duration: 0.25), value: on)
                }.buttonStyle(.plain).help(labels[n - 1])
            }
        }
    }
}

/// Campo numérico que guarda su valor a los 1,5 s de dejar de escribir.
struct DiaryNumberField: View {
    @Environment(Store.self) private var store
    let day: Date
    let key: String
    let placeholder: String
    @State private var text = ""
    @State private var seen = ""

    private var current: String { store.diaryValue(day, key).map { MD.formatNumber($0) } ?? "" }

    var body: some View {
        TextField(placeholder, text: $text).frame(width: 60)
            .onAppear { text = current; seen = current }
            .onChange(of: day) { old, _ in
                // Lo escrito para el día anterior se guarda en ese día antes de mostrar el nuevo.
                if text != seen { save(on: old) }
                text = current; seen = current
            }
            .onChange(of: store.revision) { if text == seen { text = current }; seen = current }
            .onSubmit { save(on: day) }
            .autosave(on: text) { if text != current { save(on: day) } }
    }

    private func save(on day: Date) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { store.setDiaryValue(day, key, nil) } else if let v = MD.number(t) { store.setDiaryValue(day, key, v) }
    }
}

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
