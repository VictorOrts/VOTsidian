import Foundation

// MARK: - Plantillas de ejemplo
//
// Se copian a la carpeta Plantillas (sin pisar las que ya existan) desde el asistente del principio o al crear una
// nota. Usan lo que entiende la app: {{titulo}}, {{fecha}}, {{hora}}, {{dia}}, preguntas {{?Pregunta|por defecto}},
// «plantilla_carpeta» para la carpeta sugerida y bloques ```grafica que dibujan la tabla de la nota.

enum SampleTemplates {
    static let all: [(name: String, text: String)] = [
        ("Reunión", """
        ---
        plantilla_carpeta: Reuniones
        tipo: reunion
        fecha: {{fecha}}
        con: {{?Con quién}}
        tags:
          - reunion
        ---

        # {{titulo}}

        **Cuándo:** {{dia}} {{fecha}}, {{hora}} · **Con:** {{?Con quién}}

        ## Antes
        - Para qué es la reunión: 
        - Temas:
          - 

        ## Notas
        - 

        ## Decisiones
        - 

        ## Tareas
        - [ ] 

        """),
        ("Idea", """
        ---
        tipo: idea
        fecha: {{fecha}}
        estado: {{?Estado|en el aire}}
        tags:
          - idea
        ---

        # {{titulo}}

        > [!TIP] En una frase
        > 

        ## Por qué merece la pena

        ## Cómo podría ser
        - 

        ## Primer paso
        - [ ] 

        """),
        ("Lectura", """
        ---
        plantilla_carpeta: Lecturas
        tipo: lectura
        autor: {{?Autor}}
        estado: {{?Estado|pendiente}}
        empezado:
        terminado:
        valoracion:
        tags:
          - lectura
        ---

        # {{titulo}}

        **Autor:** {{?Autor}}

        ## Por qué quiero leerlo

        ## Ideas clave
        1. 
        2. 
        3. 

        ## Frases
        > 

        ## Qué me llevo

        """),
        ("Viaje", """
        ---
        plantilla_carpeta: Viajes
        tipo: viaje
        estado: idea
        destino: {{?Destino}}
        fecha_inicio: {{?Fecha de salida (AAAA-MM-DD)}}
        fecha_fin: {{?Fecha de vuelta (AAAA-MM-DD)}}
        tags:
          - viaje
        ---

        # {{titulo}}

        **Destino:** {{?Destino}} · del {{?Fecha de salida (AAAA-MM-DD)}} al {{?Fecha de vuelta (AAAA-MM-DD)}}

        ## Reservas
        - [ ] Transporte
        - [ ] Alojamiento
        - [ ] Seguro de viaje

        ## Plan por días
        | Día | Plan |
        | :-- | :--- |
        | 1 | |
        | 2 | |

        ## Maleta
        - [ ] Documentación (DNI o pasaporte)
        - [ ] Cargadores
        - [ ] Medicación

        ## Presupuesto
        | Concepto | Importe |
        | :------- | ------: |
        | Transporte | 0 € |
        | Alojamiento | 0 € |
        | Comidas | 0 € |
        | Actividades | 0 € |

        ```grafica
        tabla: Presupuesto
        tipo: tarta
        titulo: Reparto del presupuesto
        ```

        """),
        ("Receta", """
        ---
        plantilla_carpeta: Recetas
        tipo: receta
        raciones: {{?Raciones|2}}
        tiempo_min: {{?Tiempo (min)|30}}
        tags:
          - receta
        ---

        # {{titulo}}

        **Raciones:** {{?Raciones|2}} · **Tiempo:** {{?Tiempo (min)|30}} min

        ## Ingredientes
        - 

        ## Pasos
        1. 

        ## Notas
        - 

        """),
        ("Película o serie", """
        ---
        plantilla_carpeta: Ocio
        tipo: pelicula_serie
        formato: {{?¿Película o serie?|Película}}
        plataforma: {{?Dónde verla}}
        estado: {{?Estado|pendiente}}
        valoracion:
        tags:
          - ocio
        ---

        # {{titulo}}

        **{{?¿Película o serie?|Película}}** · {{?Dónde verla}}

        ## Por qué la quiero ver

        ## Qué me pareció
        - Valoración (1–5): 
        - 

        """),
        ("Entrenamiento", """
        ---
        plantilla_carpeta: Salud
        tipo: entrenamiento
        ejercicio: {{?Ejercicio|Press banca}}
        tags:
          - entrenamiento
        ---

        # {{titulo}}

        > Una fila por sesión de **{{?Ejercicio|Press banca}}**. La gráfica se actualiza sola.

        ## Registro
        | Fecha | Peso (kg) | Series | Reps | Notas |
        | :---- | --------: | -----: | ---: | :---- |
        | {{fecha}} | | | | |

        ```grafica
        tabla: Registro
        x: Fecha
        y: Peso (kg)
        tipo: linea
        titulo: Progreso
        ```

        """),
        ("Comparar opciones", """
        ---
        tipo: decision
        fecha: {{fecha}}
        estado: {{?Estado|abierta}}
        tags:
          - decision
        ---

        # {{titulo}}

        **Qué hay que decidir:** {{?Qué hay que decidir}}

        ## Opciones
        | Opción | Precio | A favor | En contra | Nota (1–10) |
        | :----- | -----: | :------ | :-------- | ----------: |
        | A | | | | |
        | B | | | | |

        ```grafica
        tabla: Opciones
        x: Opción
        y: Nota (1–10)
        tipo: barras
        titulo: Comparación
        ```

        ## Decisión
        - Elegida: 
        - Por qué: 

        """),
        ("Curso", """
        ---
        plantilla_carpeta: Aprendizaje
        tipo: curso
        plataforma: {{?Dónde (plataforma, centro…)}}
        estado: {{?Estado|en curso}}
        inicio: {{fecha}}
        tags:
          - aprendizaje
        ---

        # {{titulo}}

        **Dónde:** {{?Dónde (plataforma, centro…)}} · **Empecé:** {{fecha}}

        ## Para qué lo hago

        ## Temario
        - [ ] Módulo 1
        - [ ] Módulo 2
        - [ ] Módulo 3

        ## Apuntes
        - 

        ## Qué puedo aplicar ya
        - 

        """),
        ("Meta de ahorro", """
        ---
        plantilla_carpeta: Finanzas
        tipo: meta_ahorro
        objetivo_eur: {{?Objetivo (€)}}
        fecha_limite: {{?Para cuándo (AAAA-MM-DD)}}
        tags:
          - finanzas
        ---

        # {{titulo}}

        **Objetivo:** {{?Objetivo (€)}} € · **Para:** {{?Para cuándo (AAAA-MM-DD)}}

        ## Aportaciones
        | Fecha | Aportado (€) | Notas |
        | :---- | -----------: | :---- |
        | {{fecha}} | | |

        ```grafica
        tabla: Aportaciones
        x: Fecha
        y: Aportado (€)
        tipo: barras
        titulo: Lo que vas apartando
        ```

        """),
    ]

    static var names: [String] { all.map(\.name) }
}
