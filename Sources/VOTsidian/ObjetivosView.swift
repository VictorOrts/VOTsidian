import SwiftUI

struct ObjetivosView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.objetivos

    var body: some View {
        let _ = BodyCounter.hit("ObjetivosView")
        let w = store.weight
        let text = store.read(file)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MissingNoteBanner(module: .objetivos)
                if let l = w.last, w.goalKg > 0 {
                    Card(title: "Objetivo de peso", icon: "scalemass", actionTitle: "Ver peso", action: { store.screen = .peso }) {
                        ProgressView(value: w.progress).tint(Brand.accent)
                        Text("\(fmt(l.kg, unit: " kg")) ahora · meta \(fmt(w.goalKg, 0)) kg · faltan \(fmt(w.remainingKg)) kg (\(Int(w.progress * 100)) %)").font(.callout)
                        if let d = w.projection()?.date {
                            Text("Al ritmo reciente llegarías hacia \(DayKey.esLong(d, .dateTime.month(.wide).year())).").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                NoteTables(file: file, icon: "target", include: { $0.col("objetivo") != nil })
                Card(title: "Revisión trimestral", icon: "calendar.badge.clock") {
                    ForEach(["Trimestre", "Qué ha avanzado", "Qué cambio o elimino"], id: \.self) { f in
                        LineField(file: file, marker: "**\(f):**", label: f, text: text)
                    }
                }
                Button("Abrir Objetivos como nota") { store.pendingNote = file }.buttonStyle(.accentLink)
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Objetivos")
    }
}

/// Campo para una línea tipo `- **Etiqueta:** texto`.
struct LineField: View {
    @Environment(Store.self) private var store
    let file: String
    let marker: String
    let label: String
    let text: String
    @State private var value = ""
    @State private var seen = ""

    private var current: String {
        guard let l = MD.lines(text).first(where: { $0.contains(marker) }), let r = l.range(of: marker) else { return "" }
        return String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
            TextField("", text: $value, axis: .vertical).lineLimit(1...4)
                .onSubmit { store.edit(file) { Edit.setValue($0, after: marker, value: value) } }
        }
        .autosave(on: value, delay: 2) { if value != current { store.edit(file, quiet: true) { Edit.setValue($0, after: marker, value: value) } } }
        .onAppear { value = current; seen = current }
        .onChange(of: current) { if value == seen { value = current }; seen = current }
    }
}
