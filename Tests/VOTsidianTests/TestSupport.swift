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
