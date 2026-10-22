import SwiftUI

struct PersonasView: View {
    @Environment(Store.self) private var store
    private let file = VaultPath.personas

    var body: some View {
        let people = store.people
        let today = DayKey.today()
        let upcoming = people.compactMap { p -> (Person, Date, Int?, Int)? in
            guard let b = p.nextBirthday() else { return nil }
            return (p, b.date, b.age, DayKey.days(from: today, to: b.date))
        }.sorted { $0.3 < $1.3 }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Próximos cumpleaños", icon: "gift") {
                    if upcoming.isEmpty { Text("Añade fechas de cumpleaños en la tabla de abajo.").foregroundStyle(.secondary) }
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
                    if people.isEmpty { Text("Sin personas.").foregroundStyle(.secondary) }
                    ForEach(people.sorted { ($0.lastContact ?? .distantPast) < ($1.lastContact ?? .distantPast) }) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).fontWeight(.medium)
                                Text(p.relation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let d = p.lastContact {
                                let n = DayKey.days(from: d, to: today)
                                Text("hace \(n) días").foregroundStyle(n > 60 ? Brand.warn : .secondary)
                            } else { Text("sin registro").foregroundStyle(.secondary) }
                            Button("Hablé hoy") { markContact(p) }.controlSize(.small)
                        }
                    }
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
