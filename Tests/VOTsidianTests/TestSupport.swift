import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

let pesoFixture = """
---
tipo: control_peso
objetivo_peso_kg: 90
peso_inicial_kg: 136
fecha_inicio: 24/02/2026
---

# Peso

```dataviewjs
const x = "| 01/01/2020 | 999 |";
```

| Fecha      | Peso (kg) | Notas |
| :--------- | :-------: | :---- |
| 24/02/2026 |    136    | Inicio |
| 30/09/2026 |    106    | Atascado |
|            |           |       |

---
"""

let mounjaroFixture = """
---
tipo: mounjaro
cada_dias: 9
---
## Registro

| Fecha      | Dosis  | Zona    | Notas |
| ---------- | ------ | ------- | ----- |
| 2026-09-30 | 7,5 mg | Abdomen | |
| 2026-10-09 | 7,5 mg | Abdomen izquierdo | |
"""

let weekFixture = """
---
tipo: revision_semanal
---
## 1. Hábitos de la semana

| Hábito   |  L  |  M  |  X  |  J  |  V  |  S  |  D  |
| :------- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| Proteína |  ✅  |     |     |     |     |     |     |
| Pasos    |     |     |     |     |     |     |     |

## 2. Mirar atrás
- **Logros:** Todo bien
- **Lo que no salió:** 

## 3. Semana siguiente
**Tres objetivos:**
1. Uno
2. 
3. 

**Fechas importantes:**
- Dentista el martes

---
"""


func tempVaultCopy(_ path: String) throws -> URL {
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/VictorBrain")
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dest)
    return dest
}

// Integración opcional: VAULT_COPY=/ruta/a/copia swift test

let casaFixture = """
# Casa
## Reformas
| Qué             | Estancia         | Prioridad | Coste estimado | Cuándo | Estado |
| :-------------- | :--------------- | :-------: | -------------: | :----- | :----- |
| Puerta enrasada | Baño invitados   |   Alta    |           2000 |        | Idea   |
| Pintar techo    | Pasillo y cocina |   Media   |         1.000  |        |        |

## Compras
| Qué         | Estancia | Prioridad | Precio estimado | Dónde   | Estado |
| :---------- | :------- | :-------: | --------------: | :------ | :----- |
| Sillon piel | Salon    |   Media   |             940 | Natuzzi | Idea   |
|             |          |           |                 |         |        |

## Electrodomésticos
| Aparato | Marca |
| :--- | :--- |
| Horno | Bosch |
"""


@MainActor func undoVault() throws -> Store {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/V")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("Cambio físico"), withIntermediateDirectories: true)
    try pesoFixture.write(to: dir.appendingPathComponent(VaultPath.peso), atomically: true, encoding: .utf8)
    try "# A\nver [[B]]\n".write(to: dir.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
    try "# B\n".write(to: dir.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
    return Store(root: dir)
}


/// Vault mínimo con peso, Mounjaro, Casa y una revisión, para probar pantallas sin depender de notas reales.
func syntheticVault() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/V")
    let files = [VaultPath.peso: pesoFixture, VaultPath.mounjaro: mounjaroFixture, VaultPath.casa: casaFixture,
                 "\(VaultPath.revisiones)/\(DayKey.weekKey(Date())).md": weekFixture,
                 "Notas/A.md": "# A\nver [[B]]\n", "Notas/B.md": "# B\ntexto\n",
                 "Finanzas/Gastos/\(Budget.monthKey(Date())).md": gastosFixture(Date()),
                 "Finanzas/Gastos/\(Budget.monthKey(DayKey.calendar().date(byAdding: .month, value: -1, to: Date())!)).md":
                    gastosFixture(DayKey.calendar().date(byAdding: .month, value: -1, to: Date())!, full: true)]
    for (rel, text) in files {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    return dir
}

/// Presupuesto de un mes con lo previsto y gastos repartidos hasta hoy (o el mes entero si `full`).
func gastosFixture(_ date: Date, full: Bool = false) -> String {
    let month = Budget.monthKey(date)
    let planned: [String: Double] = ["Vivienda (alquiler, hipoteca, impuestos, seguro)": 850, "Alimentación": 350, "Transporte": 120,
        "Suministros agua y luz": 90, "Restaurantes, viajes, entretenimiento": 150, "Préstamo padre": 200, "Préstamo personal": 180,
        "Ordenador": 60, "Seguro vida": 25, "Gym + O2": 55, "Gastos comunidad": 60, "Imprevistos / otros": 100,
        "Ahorro / fondo de emergencia": 300, "Suscripciones (Music + iCloud)": 15]
    let days = ["Vivienda (alquiler, hipoteca, impuestos, seguro)": 1, "Suministros agua y luz": 5, "Préstamo padre": 10, "Préstamo personal": 15,
                "Ordenador": 20, "Seguro vida": 3, "Gym + O2": 1, "Gastos comunidad": 28, "Ahorro / fondo de emergencia": 28, "Suscripciones (Music + iCloud)": 12]
    var text = Edit.budgetNote(month: month, from: nil)
    var b = Parse.budget(text, month: month, path: "")
    for l in b.lines {
        var lines = MD.lines(text)
        lines[l.line] = Edit.rowString([l.name, Edit.budgetNumber(planned[l.name] ?? 0), l.kind.rawValue, "", days[l.name].map(String.init) ?? ""])
        text = lines.joined(separator: "\n")
    }
    text = text.replacingOccurrences(of: "| Nómina | 0 |  |", with: "| Nómina | 2400 | 2400 |")
    b = Parse.budget(text, month: month, path: "")
    let today = full ? 31 : DayKey.calendar().component(.day, from: date)
    for l in b.lines where l.kind == .fijo {
        guard let d = l.day, d <= today else { continue }
        text = Edit.setSectionCell(text, section: "Partidas", line: l.line, expectFirst: l.name, column: "Pagado", value: "✅") ?? text
    }
    let spends: [(Int, Double, String, String)] = [(2, 64.3, "Alimentación", "Mercadona"), (4, 18, "Transporte", "metro"), (6, 42, "Restaurantes, viajes, entretenimiento", "cena con [[Ana]]"),
        (9, 71.2, "Alimentación", "compra semanal"), (11, 48, "Transporte", "gasolina"), (13, 35, "Restaurantes, viajes, entretenimiento", "cine"),
        (16, 58.9, "Alimentación", "Mercadona"), (18, 40, "Imprevistos / otros", "regalo"), (19, 104, "Suministros agua y luz", "factura luz"),
        (20, 62, "Restaurantes, viajes, entretenimiento", "cumpleaños"), (21, 22, "Restaurantes, viajes, entretenimiento", "cena con [[Ana]]"),
        (22, 60.5, "Alimentación", "compra"), (25, 30, "Transporte", "taxi"), (28, 300, "Ahorro / fondo de emergencia", "transferencia")]
    for (d, v, c, n) in spends where d <= today {
        guard let day = DayKey.date("\(month)-\(String(format: "%02d", d))") else { continue }
        text = Edit.addBudgetMove(text, date: day, amount: v, category: c, note: n) ?? text
    }
    return text
}
