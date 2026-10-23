import Foundation
import SwiftUI
import Testing
@testable import VOTsidian

let pesoFixture = """
---
tipo: control_peso
objetivo_peso_kg: 85
peso_inicial_kg: 120
fecha_inicio: 12/01/2026
---

# Peso

```dataviewjs
const x = "| 01/01/2020 | 999 |";
```

| Fecha      | Peso (kg) | Notas |
| :--------- | :-------: | :---- |
| 12/01/2026 |    120    | Inicio |
| 30/09/2026 |    101    | Sin cambios |
|            |           |       |

---
"""

let medicacionFixture = """
---
tipo: medicacion
nombre: Ozempic
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
    let fm = FileManager.default
    let dest = fm.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/Vault")
    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.copyItem(at: URL(fileURLWithPath: path), to: dest)
    // Los tests usan las rutas por defecto. Si la app tiene rutas propias (Ajustes → Módulos), en la copia esas notas
    // se mueven a las de por defecto, con lo que va junto a ellas («Menú y compra» junto al plan).
    let appID = ProcessInfo.processInfo.environment["VOT_APP_ID"] ?? "com.votsidian.app"
    let custom = (UserDefaults(suiteName: appID)?.dictionary(forKey: "vaultPathOverrides") as? [String: String]) ?? [:]
    let beside = ["plan": ["Menú y compra.md"]]
    for (key, rel) in custom {
        guard let target = VaultPath.defaults[key], target != rel, fm.fileExists(atPath: dest.appendingPathComponent(rel).path),
              !fm.fileExists(atPath: dest.appendingPathComponent(target).path) else { continue }
        let to = dest.appendingPathComponent(target)
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: dest.appendingPathComponent(rel), to: to)
        for name in beside[key] ?? [] {
            let from = dest.appendingPathComponent(rel).deletingLastPathComponent().appendingPathComponent(name)
            let next = to.deletingLastPathComponent().appendingPathComponent(name)
            if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: next.path) { try fm.moveItem(at: from, to: next) }
        }
    }
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
| Sofá cama   | Salón    |   Media   |             720 | Tienda  | Idea   |
|             |          |           |                 |         |        |

## Electrodomésticos
| Aparato | Marca |
| :--- | :--- |
| Horno | Bosch |
"""


@MainActor func undoVault() throws -> Store {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/V")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent(VaultPath.folder("peso")), withIntermediateDirectories: true)
    try pesoFixture.write(to: dir.appendingPathComponent(VaultPath.peso), atomically: true, encoding: .utf8)
    try "# A\nver [[B]]\n".write(to: dir.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
    try "# B\n".write(to: dir.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
    return Store(root: dir)
}


/// Vault mínimo con peso, medicación, Casa y una revisión, para probar pantallas sin depender de notas reales.
/// Coche con ITV que caduca pronto, aceite cada 15.000 km y dos repostajes.
let vehiculoFixture = """
---
tipo: vehiculo
nombre: Coche
matricula: 1234 ABC
km: 
---

# Coche

## Fechas

| Qué | Vence | Notas |
| :-- | :---- | :---- |
| ITV | \(DayKey.string(DayKey.adding(days: 20, to: DayKey.today()))) | |
| Seguro | 15/03/2030 | Póliza 99 |
| Impuesto de circulación | | |

## Mantenimiento

| Fecha | Km | Qué | Taller | Coste | Cada (km) | Cada (meses) |
| :---- | -: | :-- | :----- | ----: | --------: | -----------: |
| 2026-01-10 | 100.000 | Aceite y filtros | Taller Pepe | 180 € | 15.000 | 12 |
| 2026-05-02 | 108.000 | Ruedas delanteras | | 240 € | | |

## Repostajes

| Fecha | Km | Litros | Importe |
| :---- | -: | -----: | ------: |
| 2026-09-01 | 113.600 | 40 | 62 € |
| 2026-09-20 | 114.100 | 30 | 47,40 € |

"""

func syntheticVault() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)/V")
    let files = [VaultPath.peso: pesoFixture, VaultPath.medicacion: medicacionFixture, VaultPath.casa: casaFixture, VaultPath.vehiculo: vehiculoFixture,
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

/// Partidas de un presupuesto real para los tests de Gastos (préstamos, gym, cuotas…): no dependen de las que trae la app.
let testBudgetLines: [(String, BudgetLine.Kind)] = [
    ("Vivienda (alquiler, hipoteca, impuestos, seguro)", .fijo), ("Alimentación", .variable), ("Transporte", .variable),
    ("Suministros agua y luz", .fijo), ("Restaurantes, viajes, entretenimiento", .variable), ("Préstamo familiar", .fijo),
    ("Préstamo personal", .fijo), ("Ordenador", .fijo), ("Seguro vida", .fijo), ("Gym + fibra", .fijo), ("Gastos comunidad", .fijo),
    ("Imprevistos / otros", .variable), ("Ahorro / fondo de emergencia", .ahorro), ("Suscripciones (música y nube)", .fijo),
]

/// Presupuesto de un mes con lo previsto y gastos repartidos hasta hoy (o el mes entero si `full`).
func gastosFixture(_ date: Date, full: Bool = false) -> String {
    let month = Budget.monthKey(date)
    let planned: [String: Double] = ["Vivienda (alquiler, hipoteca, impuestos, seguro)": 850, "Alimentación": 350, "Transporte": 120,
        "Suministros agua y luz": 90, "Restaurantes, viajes, entretenimiento": 150, "Préstamo familiar": 200, "Préstamo personal": 180,
        "Ordenador": 60, "Seguro vida": 25, "Gym + fibra": 55, "Gastos comunidad": 60, "Imprevistos / otros": 100,
        "Ahorro / fondo de emergencia": 300, "Suscripciones (música y nube)": 15]
    let days = ["Vivienda (alquiler, hipoteca, impuestos, seguro)": 1, "Suministros agua y luz": 5, "Préstamo familiar": 10, "Préstamo personal": 15,
                "Ordenador": 20, "Seguro vida": 3, "Gym + fibra": 1, "Gastos comunidad": 28, "Ahorro / fondo de emergencia": 28, "Suscripciones (música y nube)": 12]
    var text = Edit.budgetNote(month: month, from: nil, defaults: testBudgetLines)
    var b = Parse.budget(text, month: month, path: "")
    for l in b.lines {
        var lines = MD.lines(text)
        lines[l.line] = Edit.rowString([l.name, Edit.budgetNumber(planned[l.name] ?? 0), l.kind.rawValue, "", days[l.name].map(String.init) ?? "", "", ""])
        text = lines.joined(separator: "\n")
    }
    text = text.replacingOccurrences(of: "| Nómina | 0 |  |", with: "| Nómina | 2400 | 2400 |")
    // Un cargo trimestral que toca el mes que viene.
    if let seguro = Parse.budget(text, month: month, path: "").line(named: "Seguro vida"), let m = BudgetLine.monthIndex(month) {
        text = Edit.setSectionCell(text, section: "Partidas", line: seguro.line, expectFirst: seguro.name, column: "Previsto", value: "180") ?? text
        text = Edit.setSectionCell(text, section: "Partidas", line: seguro.line, expectFirst: seguro.name, column: "Cada", value: "3") ?? text
        text = Edit.setSectionCell(text, section: "Partidas", line: seguro.line, expectFirst: seguro.name, column: "Desde", value: BudgetLine.month(m + (full ? 0 : 1))) ?? text
    }
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
