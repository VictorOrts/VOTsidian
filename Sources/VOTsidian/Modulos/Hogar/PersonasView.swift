import SwiftUI

struct PersonasView: View {
    @Environment(Store.self) private var store
    @State private var allPeople = false
    private let file = VaultPath.personas

    var body: some View {
        let _ = BodyCounter.hit("PersonasView")
        let people = store.people
        let today = DayKey.today()
        let upcoming = people.compactMap { p -> (Person, Date, Int?, Int)? in
            guard let b = p.nextBirthday() else { return nil }
            return (p, b.date, b.age, DayKey.days(from: today, to: b.date))
        }.sorted { $0.3 < $1.3 }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MissingNoteBanner(module: .personas)
                Card(title: "Próximos cumpleaños", icon: "gift") {
                    if upcoming.isEmpty { EmptyNote(people.isEmpty ? "Sin personas. Añádelas en la tabla de la nota Personas, con su cumpleaños." : "Añade fechas de cumpleaños en la tabla de abajo.", icon: "gift") }
                    ForEach(upcoming.prefix(6), id: \.0.id) { p, date, age, days in
                        HStack {
                            Text(p.name).fontWeight(.medium)
                            Spacer()
                            Text(shortDate(date) + (age.map { " · \($0) años" } ?? "")).foregroundStyle(.secondary)
                            Text(relativeDays(days)).foregroundStyle(days <= 7 ? Brand.warn : .secondary).frame(width: 100, alignment: .trailing)
                        }
                    }
                }
                Card(title: "Contacto", icon: "bubble.left.and.bubble.right") {
                    if people.isEmpty { EmptyNote("Sin personas.") }
                    // Primero con quien hace más que no hablas: si son muchas, basta con las primeras.
                    ForEach(people.sorted { ($0.lastContact ?? .distantPast) < ($1.lastContact ?? .distantPast) }.prefix(allPeople ? people.count : 30)) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).fontWeight(.medium)
                                Text(p.relation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let d = p.lastContact {
                                let n = DayKey.days(from: d, to: today)
                                Text(relativeDays(-n)).foregroundStyle(n > 60 ? Brand.warn : .secondary)
                            } else { Text("sin registro").foregroundStyle(.secondary) }
                            Button("Hablé hoy") { markContact(p) }.controlSize(.small)
                        }
                    }
                    ShowAllButton(total: people.count, limit: 30, noun: "personas", showAll: $allPeople)
                }
                NoteTables(file: file, icon: "person.2", include: { $0.col("persona") != nil })
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle("Personas")
    }

    private func markContact(_ p: Person) {
        store.edit(file) { text in
            guard let t = Parse.tables(text).first(where: { $0.col("persona") != nil }), let c = t.col("ultima vez"),
                  let row = t.rows.first(where: { $0.line == p.line || $0.cells.first == p.name }) else { return nil }
            var cells = row.cells
            while cells.count < t.header.count { cells.append("") }
            cells[c] = DayKey.string(DayKey.today())
            return Edit.updateRow(text, line: row.line, expectFirst: row.cells.first ?? "", cells: cells)
        }
    }
}
