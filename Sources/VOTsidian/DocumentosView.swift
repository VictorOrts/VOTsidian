import SwiftUI

struct DocumentosView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.documentos

    var body: some View {
        let _ = BodyCounter.hit("DocumentosView")
        let docs = store.documents.sorted { $0.date < $1.date }
        let today = DayKey.today()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MissingNoteBanner(module: .documentos)
                Card(title: "Caducidades", icon: "clock.badge.exclamationmark",
                     info: "Anota solo la referencia del documento, no el documento. Al activar los avisos se crean eventos 30 días antes de cada caducidad.") {
                    if docs.isEmpty { EmptyNote("Ningún documento tiene fecha. Pon la fecha en la columna «Caduca / renueva» (AAAA-MM-DD).", icon: "calendar") }
                    ForEach(Array(docs.enumerated()), id: \.offset) { _, d in
                        let n = DayKey.days(from: today, to: d.date)
                        HStack {
                            Image(systemName: n < 0 ? "xmark.octagon.fill" : n <= 60 ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .foregroundStyle(n < 0 ? Brand.bad : n <= 60 ? Brand.warn : Brand.accent)
                                .accessibilityLabel(n < 0 ? "Caducado" : n <= 60 ? "Caduca pronto" : "En vigor")
                            Text(d.name).fontWeight(.medium)
                            Text(d.section).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(DayKey.dmy(d.date)).monospacedDigit().foregroundStyle(.secondary)
                            Text(n < 0 ? "caducó \(relativeDays(n))" : relativeDays(n)).frame(width: 100, alignment: .trailing)
                        }
                    }
                }
                NoteTables(file: file, icon: "doc.text")
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Documentos")
    }
}
