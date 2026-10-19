import SwiftUI

struct DocumentosView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.documentos

    var body: some View {
        let docs = store.documents.sorted { $0.date < $1.date }
        let today = DayKey.today()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Caducidades", icon: "clock.badge.exclamationmark") {
                    if docs.isEmpty { Text("Ningún documento tiene fecha. Pon la fecha en la columna “Caduca / renueva” (AAAA-MM-DD).").foregroundStyle(.secondary) }
                    ForEach(Array(docs.enumerated()), id: \.offset) { _, d in
                        let n = DayKey.days(from: today, to: d.date)
                        HStack {
                            Image(systemName: n < 0 ? "xmark.octagon.fill" : n <= 60 ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .foregroundStyle(n < 0 ? Brand.bad : n <= 60 ? Brand.warn : Brand.accent)
                            Text(d.name).fontWeight(.medium)
                            Text(d.section).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(DayKey.dmy(d.date)).monospacedDigit().foregroundStyle(.secondary)
                            Text(n < 0 ? "caducado" : relativeDays(n)).frame(width: 100, alignment: .trailing)
                        }
                    }
                }
                NoteTables(file: file, icon: "doc.text")
                Text("Anota solo la referencia del documento, no el documento. Al activar los avisos se crean eventos 30 días antes de cada caducidad.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Documentos")
    }
}
