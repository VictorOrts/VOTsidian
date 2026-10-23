# VOTsidian

Agenda personal para Mac: tareas, hábitos, revisiones, notas, salud, dinero y casa, todo guardado como notas Markdown en una carpeta tuya. No necesita Obsidian, pero lee y escribe los mismos archivos, así que puedes usar los dos a la vez.

## Empezar

```bash
./scripts/build-app.sh       # crea build/VOTsidian.app para abrirla con doble clic
swift run VOTsidian          # o ábrela desde la terminal
```

La primera vez sale el asistente «Empecemos». En él eliges la carpeta (por defecto `iCloud Drive/VOTsidian`) y los módulos que quieres, y la app crea las notas con su formato. El formato de cada nota está en [GUIA.md](GUIA.md).

## Qué puedes hacer

### Día a día
- **Inicio:** saludo, lo que pide atención, lo de hoy y tarjetas de cada módulo. «Personalizar» las reordena y las oculta.
- **Tareas:**
  - fecha, prioridad y repetición («cada mes», «cada 2 semanas»);
  - se escriben en lenguaje natural: «llamar al dentista el viernes», «pagar 25/11»;
  - «Planificar semana» es un tablero de lunes a domingo donde se arrastran las tareas.
- **Calendario:** tareas, citas, pagos, cumpleaños y caducidades, con la nota del día, el ánimo y el sueño.
- **Revisiones:**
  - semanal, con hábitos y su criterio, cumplimiento y racha;
  - mensual, con aviso el último día del mes;
  - «Cerrar el día» repasa lo pendiente y prepara mañana.
- **Proyectos y Objetivos:** lista o tablero, tareas por proyecto y revisión trimestral.
- **Captura rápida (⇧⌘N):** tarea, gasto, peso, toma de medicación o idea.
- **Barra de menús:** tareas y hábitos de hoy, tomas de medicación, ánimo y añadir tareas, sin abrir la ventana.
- **Avisos:**
  - dentro de la app, ordenados por urgencia y con botón para resolverlos;
  - también como eventos de Calendar y notificaciones de macOS (solo en la app compilada).

### Notas
- **Editor:**
  - pestañas y guardado automático;
  - `[[` sugiere notas y `#` sugiere etiquetas;
  - etiquetas, notas fijadas y exportar a PDF;
  - si la nota cambia fuera de la app mientras la editas, avisa en vez de pisarla.
- **Enlaces entre notas:** `![[Nota]]` o `![[Nota#Sección]]` incrustan otra nota y `![[foto.png]]` una imagen. «Enlazada desde» muestra la línea que enlaza, con vista previa.
- **Plantillas:**
  - 10 de ejemplo: Reunión, Idea, Lectura, Viaje, Receta, Película o serie, Entrenamiento, Comparar opciones, Curso y Meta de ahorro;
  - pueden hacer preguntas al crear la nota (`{{?Destino}}`) y sugerir carpeta.
- **Gráficas en una nota:** un bloque `grafica` dibuja una tabla de la nota en línea, barras, área, puntos o tarta.
- **Buscar (⌘K):**
  - notas, tareas y pantallas, con sinónimos («médico» encuentra «doctor») y filtros (`#etiqueta`, `carpeta:casa`, `tipo:evento`, «el viernes»);
  - órdenes directas: `peso 105,5`, `ánimo 4`, `dormí 7,5`, `pinchazo hoy`, `tarea … el viernes`, `cita endocrino el 29/10`, `cintura 98`, `compra leche y pan`.
- **Bases, Grafo y Enlaces rotos:**
  - Bases es una tabla de propiedades por tipo de nota, con filtros y vistas guardadas;
  - Grafo es el mapa de enlaces;
  - Enlaces rotos sugiere con qué nota arreglar cada enlace.

### Salud
- **Peso:**
  - tendencia suavizada y ritmo de 4 y 2 meses;
  - fecha estimada de llegada al objetivo, tanto para bajar como para subir;
  - hitos, cambio entre pesajes, medidas corporales y fotos de progreso.
- **Correlaciones:** peso, hábitos, ánimo y sueño semana a semana.
- **Plan nutricional:** calorías y macros, y reparto por comidas.
- **Medicación:**
  - varios medicamentos a la vez: pastillas diarias (una casilla por toma), inyecciones cada N días (con la zona alternada) y lo que se toma cuando hace falta;
  - avisos por medicamento y hora, y cumplimiento de 30 días.
- **Salud y médicos:**
  - próximas citas, tratamientos, análisis en PDF y notas de cada visita;
  - un resumen para copiar y llevar a la consulta.

### Dinero
- **Gastos:**
  - presupuesto mensual por partidas;
  - se apunta escribiendo «22 € cena con Ana»: la app adivina la partida y aprende de tus correcciones;
  - «Puedes gastar hoy», ritmo del mes y lo que sobrará;
  - pagos fijos con aviso, cargos trimestrales o anuales y fondo de emergencia.
- **Resumen del año:** ingresos, gastos y ahorro por mes, comparación con el año anterior y peso de cada partida. Se puede guardar como nota.
- **Finanzas:** eventos y aportaciones (bodas, regalos…) que se dan por pagadas con un clic.

### Casa y vida
- **Casa:** reformas y compras en lista o tablero, electrodomésticos y tareas de mantenimiento sugeridas según tus aparatos.
- **Compra:** lista por secciones con casillas.
- **Ropa:** lo que quieres comprar, con precio, prioridad y estado.
- **Mascota:** ficha, visitas y vacunas, con aviso de la próxima.
- **Personas:** cumpleaños y última vez que hablasteis.
- **Documentos:** caducidades, con aviso 30 días antes.

### Tus datos
- **Copias de seguridad:**
  - antes del primer cambio de cada día se copia toda la carpeta (se guardan 14 copias);
  - se pueden cifrar con contraseña guardada en el Llavero;
  - aviso si una copia falla o la última es vieja.
- **Deshacer:** cualquier cambio se deshace con ⌥⌘Z.
- **Recuperar:** el historial de una nota permite restaurar versiones anteriores, y una copia entera se puede restaurar (antes se guarda el estado actual).
- **iCloud:** aviso si iCloud duplica una nota por conflicto o si hay archivos sin descargar.
- **Exportar:** resumen del año en PDF, tus datos en CSV y todas las notas en .zip.
- **Ajustes → Módulos:** muestra u oculta cada módulo (peso, medicación, gastos, mascota…) y permite cambiar la ruta de cada nota.

## Atajos

| Atajo | Hace |
|---|---|
| ⌘K | Buscar y órdenes rápidas |
| ⇧⌘N | Captura rápida |
| ⌘1 … ⌘9 | Ir a una pantalla |
| ⌘S | Guardar la nota |
| ⌥⌘Z | Deshacer el último cambio |
| ⌘T / ⌘W | Nueva pestaña / cerrar pestaña |

## Desarrollo

```bash
swift test                                        # tests (trabajan sobre copias temporales)
VAULT_COPY=/ruta/a/tus/notas swift test           # además, tests sobre una copia de tus notas
VOT_SHOTS=/carpeta VAULT_COPY=/ruta swift test --filter screenshots   # capturas de todas las pantallas
```

Para firmar de verdad: `SIGN_ID="Developer ID Application: …" ./scripts/build-app.sh`; sin él, usa tu certificado «Apple Development».
