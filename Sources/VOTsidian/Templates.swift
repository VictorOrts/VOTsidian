import Foundation

enum Template {
    static func week(key: String, monday: Date, habits: [HabitDef]) -> String {
        let rows = habits.map { "| \($0.name) |  |  |  |  |  |  |  | \($0.criterion) |" }.joined(separator: "\n")
        return #"""
        ---
        tipo: revision_semanal
        semana: "\#(key)"
        fecha: "\#(DayKey.string(monday))"
        tags:
          - revision
          - semanal
        ---

        # Revisión semanal \#(key)

        > Hazla el mismo día cada semana (15 min). Marca los hábitos con ✅ en los días cumplidos.

        ## 1. Hábitos de la semana

        | Hábito | L | M | X | J | V | S | D | Criterio |
        | :----- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :------- |
        \#(rows)

        ## 2. Mirar atrás
        - **Logros:** 
        - **Lo que no salió:** 

        ## 3. Semana siguiente
        **Tres objetivos:**
        1. 
        2. 
        3. 

        **Fechas importantes:**
        - [ ] 

        ---
        [[Inbox]]
        """#
    }
}

extension Template {
    static func month(key: String, monthStart: Date) -> String {
        """
        ---
        tipo: revision_mensual
        mes: "\(key)"
        fecha: "\(DayKey.string(monthStart))"
        tags:
          - revision
          - mensual
        ---

        # Revisión mensual \(key)

        > Hazla el último día del mes (20 min): peso, medidas, hábitos y objetivos.

        ## 1. Mirar atrás
        - **Logros:** 
        - **Lo que no salió:** 

        ## 2. Mes siguiente
        **Tres objetivos:**
        1. 
        2. 
        3. 

        ---
        [[Peso]]
        """
    }
}

enum NoteTemplates {
    static let names = ["En blanco", "Reforma o compra", "Proyecto", "Cita médica", "Evento"]

    static func defaultFolder(_ template: String) -> String {
        switch template {
        case "Reforma o compra": "Casa"
        case "Proyecto": "Proyectos"
        case "Cita médica": "Organización/Médico"
        case "Evento": "Finanzas"
        default: ""
        }
    }

    static func body(_ template: String, title: String, today: Date = Date()) -> String {
        let day = DayKey.string(today)
        switch template {
        case "Reforma o compra":
            return "---\ntipo: casa_item\ntipo_casa: Reforma\nestado: Idea\nprioridad: Media\ncoste:\ntags:\n  - casa\n---\n\n# \(title)\n\n## Detalle\n\n## Presupuestos\n\n## Tareas\n- [ ] \n\n---\n[[Casa]]\n"
        case "Proyecto":
            return "---\ntipo: proyecto\nestado: activo\narea:\ninicio: \(day)\nfecha_limite:\nprioridad: media\ntags:\n  - proyecto\n---\n\n# \(title)\n\n> [!INFO] Resultado esperado\n> \n\n## Siguientes acciones\n- [ ] \n\n---\n[[Objetivos]]\n"
        case "Cita médica":
            return "---\ntipo: cita_medica\nfecha: \(day)\nespecialidad:\ntags:\n  - medico\n---\n\n# \(title)\n\n## Motivo\n\n## Resultado\n\n## Próximos pasos\n- [ ] \n\n---\n[[Médico]]\n"
        case "Evento":
            return "---\ntipo: evento\nestado: pendiente\nfecha_evento:\naportacion_eur:\ntags:\n  - evento\n---\n\n# \(title)\n\n## Pendiente\n- [ ] \n\n---\n[[Finanzas]]\n"
        default:
            return "# \(title)\n\n"
        }
    }
}
