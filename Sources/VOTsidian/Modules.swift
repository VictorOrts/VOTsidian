import Foundation

// MARK: - Módulos: las partes opcionales de la app
//
// Tareas, calendario, revisiones, proyectos y notas son la base y siempre están. El resto (peso, gastos, casa…)
// es un módulo: tiene sus pantallas y las notas que necesita, con una plantilla que la app sabe leer. Así alguien
// que empieza de cero elige lo que quiere y la app le crea esas notas con el formato correcto.

enum Module: String, CaseIterable, Identifiable {
    case peso, nutricion, medicacion, salud, finanzas, casa, compra, moda, mascota, vehiculo, personas, documentos, objetivos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .peso: "Peso y medidas"
        case .nutricion: "Plan nutricional"
        case .medicacion: "Medicación"
        case .salud: "Salud y médicos"
        case .finanzas: "Finanzas y gastos"
        case .casa: "Casa"
        case .compra: "Lista de la compra"
        case .moda: "Ropa"
        case .mascota: "Mascota"
        case .vehiculo: "Vehículo"
        case .personas: "Personas"
        case .documentos: "Documentos"
        case .objetivos: "Objetivos"
        }
    }

    var detail: String {
        switch self {
        case .peso: "Registro de peso con tendencia y fecha estimada de llegada a tu objetivo, medidas y correlaciones con tus hábitos."
        case .nutricion: "Calorías y macros diarios y reparto por comidas."
        case .medicacion: "Pastillas diarias, inyecciones semanales o lo que tomas cuando hace falta: qué toca hoy, avisos y cumplimiento."
        case .salud: "Próximas citas, tratamientos, análisis y notas de cada visita."
        case .finanzas: "Presupuesto mensual por partidas, gastos del día a día, resumen del año y eventos o pagos."
        case .casa: "Reformas, compras para la casa, electrodomésticos y mantenimiento."
        case .compra: "Lista de la compra por secciones, con casillas."
        case .moda: "Lo que quieres comprar de ropa, con precio, prioridad y estado."
        case .mascota: "Ficha, visitas al veterinario, vacunas y avisos de la próxima."
        case .vehiculo: "ITV, seguro e impuesto con aviso, mantenimiento por km o meses, repostajes y consumo."
        case .personas: "Cumpleaños y cuándo hablaste por última vez con cada persona."
        case .documentos: "DNI, pasaporte, seguros… con avisos antes de que caduquen."
        case .objetivos: "Objetivos por área y una revisión cada trimestre."
        }
    }

    var icon: String {
        switch self {
        case .peso: "scalemass"
        case .nutricion: "fork.knife"
        case .medicacion: "pills"
        case .salud: "cross.case"
        case .finanzas: "eurosign.circle"
        case .casa: "house.and.flag"
        case .compra: "cart"
        case .moda: "tshirt"
        case .mascota: "pawprint"
        case .vehiculo: "car"
        case .personas: "person.2"
        case .documentos: "doc.on.doc"
        case .objetivos: "target"
        }
    }

    var screens: [Screen] {
        switch self {
        case .peso: [.peso, .correlaciones]
        case .nutricion: [.nutricion]
        case .medicacion: [.medicacion]
        case .salud: [.salud]
        case .finanzas: [.finanzas, .gastos]
        case .casa: [.casa]
        case .compra: [.compra]
        case .moda: [.moda]
        case .mascota: [.mascota]
        case .vehiculo: [.vehiculo]
        case .personas: [.personas]
        case .documentos: [.documentos]
        case .objetivos: [.objetivos]
        }
    }

    /// Claves de `VaultPath` de las notas que usa. Gastos crea sola la nota de cada mes, así que no hace falta.
    var files: [String] {
        switch self {
        case .peso: ["peso"]
        case .nutricion: ["plan"]
        case .medicacion: ["medicacion"]
        case .salud: ["medico"]
        case .finanzas: ["finanzas"]
        case .casa: ["casa"]
        case .compra: ["compra"]
        case .moda: ["moda"]
        case .mascota: ["mascota"]
        case .vehiculo: ["vehiculo"]
        case .personas: ["personas"]
        case .documentos: ["documentos"]
        case .objetivos: ["objetivos"]
        }
    }

    /// Lo que se marca de entrada en el asistente: lo que sirve a casi cualquiera.
    static let suggested: Set<Module> = [.finanzas, .compra, .salud, .personas, .documentos, .objetivos]

    /// Módulo al que pertenece una pantalla; `nil` para las de la base, que no se pueden ocultar.
    static func of(_ screen: Screen) -> Module? { allCases.first { $0.screens.contains(screen) } }
}

// MARK: - Plantillas

enum Starter {
    /// Nombre de cada ruta configurable, para Ajustes.
    static let labels: [String: String] = [
        "peso": "Peso", "medidas": "Medidas", "plan": "Plan nutricional", "proyecto": "Proyecto con hitos de peso",
        "medicacion": "Medicación", "medico": "Salud y médicos", "mascota": "Mascota", "vehiculo": "Vehículo", "casa": "Casa", "moda": "Ropa",
        "inbox": "Bandeja de tareas", "documentos": "Documentos", "personas": "Personas", "objetivos": "Objetivos",
        "finanzas": "Finanzas", "gastos": "Carpeta de gastos (una nota por mes)", "revisiones": "Carpeta de revisiones", "compra": "Lista de la compra",
    ]

    /// Valor para el encabezado YAML: entre comillas si lleva algo que lo pueda romper.
    static func yaml(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard t.contains(where: { ":#\"'[]{},&*!|>%@`".contains($0) }) else { return t }
        return "\"" + t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Nota vacía con el formato que lee cada pantalla, o `nil` si esa ruta no tiene plantilla.
    /// `name` es el nombre de la mascota, si se conoce.
    static func text(forKey key: String, name: String? = nil) -> String? {
        let name = name.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        switch key {
        case "peso":
            return """
            ---
            tipo: control_peso
            peso_inicial_kg:
            objetivo_peso_kg:
            fecha_inicio:
            ---

            # Peso

            > Un pesaje por fila (DD/MM/AAAA). Sin peso inicial, cuenta el primer pesaje. El objetivo se pone en la pantalla Peso.

            | Fecha | Peso (kg) | Notas |
            | :---- | :-------: | :---- |

            """
        case "medidas": return Measures.template
        case "medicacion":
            return """
            ---
            tipo: medicacion
            ---

            # Medicación

            > Una fila por medicamento. «Cada»: días entre tomas (1 = cada día, 7 = cada semana) o «Si hace falta». «Horas»: 09:00, 21:00 si se toma varias veces al día. Fechas en AAAA-MM-DD.

            ## Medicamentos

            | Medicamento | Dosis | Forma | Cada | Horas | Desde | Hasta | Notas |
            | :---------- | :---- | :---- | :--: | :---- | :---- | :---- | :---- |

            ## Registro

            | Fecha | Medicamento | Dosis | Zona | Notas |
            | :---- | :---------- | :---- | :--- | :---- |

            """
        case "mascota":
            let n = name ?? "Mascota"
            return """
            ---
            tipo: mascota
            nombre: \(yaml(n))
            nacimiento:
            comida:
            ---

            # \(n)

            ## Visitas y vacunas

            > Fechas en AAAA-MM-DD. Con «Próxima», la app avisa cuando se acerca.

            | Fecha | Tipo | Detalle | Próxima | Coste |
            | ----- | ---- | ------- | ------- | ----- |

            """
        case "vehiculo":
            return """
            ---
            tipo: vehiculo
            nombre:
            matricula:
            km:
            ---

            # Vehículo

            ## Fechas

            > ITV, seguro, impuesto… Fechas en AAAA-MM-DD o DD/MM/AAAA. La app avisa 30 días antes.

            | Qué | Vence | Notas |
            | :-- | :---- | :---- |
            | ITV | | |
            | Seguro | | |
            | Impuesto de circulación | | |

            ## Mantenimiento

            > Una fila por visita al taller. Con «Cada (km)» o «Cada (meses)», la app calcula cuándo toca la siguiente.

            | Fecha | Km | Qué | Taller | Coste | Cada (km) | Cada (meses) |
            | :---- | -: | :-- | :----- | ----: | --------: | -----------: |

            ## Repostajes

            > Llena el depósito cada vez para que el consumo salga bien.

            | Fecha | Km | Litros | Importe |
            | :---- | -: | -----: | ------: |

            """
        case "plan":
            return """
            ---
            tipo: plan_nutricional
            kcal_objetivo:
            proteina_g:
            carbohidratos_g:
            grasas_g:
            ---

            # Plan nutricional

            > Los objetivos diarios se ponen en la pantalla Plan nutricional. Consúltalos con tu médico o dietista.

            ## Reparto del día

            | Comida | kcal | Proteína (g) |
            | :----- | ---: | -----------: |
            | Desayuno | | |
            | Comida | | |
            | Cena | | |

            """
        case "medico":
            return """
            ---
            tipo: salud
            ---

            # Salud y médicos

            ## Próximas citas

            ## Tratamientos

            ## Análisis

            | Fecha | Prueba | Resultado | Notas |
            | :---- | :----- | :-------- | :---- |

            """
        case "casa":
            return """
            ---
            tipo: casa
            ---

            # Casa

            ## Reformas

            | Qué | Estancia | Prioridad | Coste estimado | Cuándo | Estado |
            | :-- | :------- | :-------: | -------------: | :----- | :----- |

            ## Compras

            | Qué | Estancia | Prioridad | Precio estimado | Dónde | Estado |
            | :-- | :------- | :-------: | --------------: | :---- | :----- |

            ## Electrodomésticos

            | Aparato | Marca | Modelo | Comprado | Garantía hasta |
            | :------ | :---- | :----- | :------- | :------------- |

            ## Pequeños electrodomésticos

            | Aparato | Marca | Modelo | Comprado | Garantía hasta |
            | :------ | :---- | :----- | :------- | :------------- |

            """
        case "moda":
            return """
            ---
            tipo: armario
            ---

            # Armario

            ## Por comprar

            | Prenda | Modelo | Prioridad | Precio | Fecha objetivo | Estado |
            | :----- | :----- | :-------: | -----: | :------------- | :----- |

            ## Armario

            | Categoría | Qué tengo | Notas |
            | :-------- | :-------- | :---- |

            ## Estrategia

            ## Calzado y accesorios

            """
        case "personas":
            return """
            ---
            tipo: personas
            ---

            # Personas

            > Cumpleaños en AAAA-MM-DD (o MM-DD si no sabes el año). «Última vez» en AAAA-MM-DD.

            | Persona | Relación | Cumpleaños | Última vez | Notas |
            | :------ | :------- | :--------- | :--------- | :---- |

            """
        case "documentos":
            return """
            ---
            tipo: documentos
            ---

            # Documentos

            > Solo la referencia, nunca el documento. La app avisa antes de cada caducidad (AAAA-MM-DD o DD/MM/AAAA).

            ## Identidad

            | Documento | Número o referencia | Caduca / renueva | Notas |
            | :-------- | :------------------ | :--------------- | :---- |

            ## Seguros y contratos

            | Documento | Número o referencia | Caduca / renueva | Notas |
            | :-------- | :------------------ | :--------------- | :---- |

            """
        case "objetivos":
            return """
            ---
            tipo: objetivos
            ---

            # Objetivos

            | Objetivo | Área | Para cuándo | Estado |
            | :------- | :--- | :---------- | :----- |

            ## Revisión trimestral

            - **Trimestre:**
            - **Qué ha avanzado:**
            - **Qué cambio o elimino:**

            """
        case "finanzas":
            return """
            ---
            tipo: finanzas
            ---

            # Finanzas

            > El presupuesto de cada mes está en la pantalla Gastos. Aquí van los objetivos de ahorro y pagos sueltos, como tareas.

            ## Objetivos de ahorro y pagos

            """
        case "compra": return Shopping.template
        case "inbox": return "# Inbox\n\n## Pendiente de clasificar\n\n## Ideas\n"
        default: return nil
        }
    }
}

// MARK: - Store

extension Store {
    /// Plantilla para una ruta que aún no existe, si es la de algún módulo.
    func starterText(for rel: String) -> String? {
        guard let key = VaultPath.defaults.keys.sorted().first(where: { VaultPath.path($0) == rel }) else { return nil }
        let name = key == "mascota" ? UserDefaults.standard.string(forKey: "starterPet") : nil
        return Starter.text(forKey: key, name: name)
    }

    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url(rel).path) }

    /// Notas del módulo que todavía no existen (las que están en iCloud sin descargar no cuentan como que faltan).
    func missingFiles(_ m: Module) -> [String] {
        m.files.map(VaultPath.path).filter { !exists($0) && !pendingDownloads.contains($0) }
    }

    /// Crea las notas que falten de los módulos, sin tocar las que ya existen. Devuelve las creadas.
    @discardableResult
    func createStarterNotes(_ modules: [Module], petName: String? = nil) -> [String] {
        if let petName, !petName.trimmingCharacters(in: .whitespaces).isEmpty { UserDefaults.standard.set(petName, forKey: "starterPet") }
        var created: [String] = []
        grouped {
            for m in modules {
                for rel in missingFiles(m) {
                    guard let text = starterText(for: rel) else { continue }
                    if writeNote(rel, text: text) { created.append(rel) }
                }
            }
        }
        return created
    }

    /// Lo que hace el asistente del principio: crea la carpeta y las notas de los módulos elegidos y oculta el resto.
    func setUp(modules: Set<Module>, petName: String? = nil, templates: Bool = false) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let inbox = VaultPath.inbox
        if !exists(inbox), let t = Starter.text(forKey: "inbox") { writeNote(inbox, text: t) }
        createStarterNotes(Module.allCases.filter(modules.contains), petName: petName)
        if templates { createSampleTemplates() }
        hiddenModules = Set(Module.allCases).subtracting(modules)
        modulesConfigured = true
        undoStack.removeAll()   // lo recién creado no es un cambio que deshacer
        lastChange = nil
    }

    func isVisible(_ s: Screen) -> Bool { Module.of(s).map { !hiddenModules.contains($0) } ?? true }

    /// Ninguna nota de ningún módulo existe: es una carpeta nueva o de otra persona, y conviene el asistente.
    var looksNew: Bool {
        Module.allCases.allSatisfy { m in m.files.allSatisfy { !exists(VaultPath.path($0)) } }
    }

    /// Nombre de la pantalla. Medicación y mascota toman el de su nota («nombre:»).
    func title(_ s: Screen) -> String {
        switch s {
        case .medicacion: medicacion.name
        case .mascota: mascota.name
        case .vehiculo: vehiculo.name
        default: s.rawValue
        }
    }
}
