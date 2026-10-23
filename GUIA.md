# Guía de VOTsidian

VOTsidian es una agenda personal para Mac. Todo lo que apuntas se guarda en notas Markdown (archivos `.md`) dentro de una carpeta tuya. Esas mismas notas se pueden abrir con Obsidian o con cualquier editor de texto: la app no tiene una base de datos aparte.

## Empezar

1. Crea la app con `./scripts/build-app.sh` y ábrela (`build/VOTsidian.app`).
2. La primera vez sale **Empecemos**:
   - **Carpeta.** Por defecto, `iCloud Drive/VOTsidian`, para tenerla en todos tus dispositivos. Con «Elegir otra carpeta…» puedes usar una que ya tengas (por ejemplo, tu vault de Obsidian) o crear una nueva.
   - **Qué quieres llevar.** Marca los módulos que te interesan. Si eliges Mascota, escribe también su nombre. Los medicamentos se añaden después, en su pantalla.
3. Pulsa **Crear notas y empezar**. La app crea una nota por módulo, con el formato que sabe leer, y oculta los módulos que no marcaste.

Si la carpeta ya tiene notas, no se cambia ninguna: solo se crean las que faltan.

Siempre están **Tareas, Calendario, Planificar semana, Revisión semanal y mensual, Proyectos, Notas, Bases, Grafo, Enlaces rotos y Avisos**.

Todo se cambia después en **Ajustes → Módulos**: mostrar u ocultar módulos, crear la nota que falte o cambiar dónde está cada nota.

## Módulos y sus notas

Si falta la nota de una pantalla, arriba sale un aviso con «Crear la nota». No hace falta pulsarlo: la nota se crea sola la primera vez que apuntas algo desde la pantalla.

| Módulo | Pantallas | Nota en una carpeta nueva |
|---|---|---|
| Peso y medidas | Peso, Correlaciones | `Salud/Peso.md` (y `Salud/Medidas.md` al activar las medidas; las fotos, en `Salud/Fotos`) |
| Plan nutricional | Plan nutricional | `Salud/Plan nutricional.md` |
| Medicación | Medicación | `Salud/Medicación.md` |
| Salud y médicos | Salud y médicos | `Salud/Médico.md` (las notas de visita y los PDF de análisis, en `Salud/`) |
| Finanzas y gastos | Finanzas, Gastos | `Finanzas/Finanzas.md` y una nota por mes en `Finanzas/Gastos/` |
| Casa | Casa | `Casa/Casa.md` |
| Lista de la compra | Compra | `Casa/Lista de la compra.md` |
| Ropa | Moda | `Moda/Armario.md` |
| Mascota | (nombre de la mascota) | `Mascota/Mascota.md` |
| Personas | Personas | `Organización/Personas.md` |
| Documentos | Documentos | `Organización/Documentos.md` |
| Objetivos | Objetivos | `Organización/Objetivos.md` |

Las carpetas que ya usaban la primera versión de la app (`Cambio físico/Peso.md`, `Nala/Nala.md`, `Organización/Médico/Médico.md`…) siguen con esas rutas: el asistente solo pone las nuevas para las notas que no existen todavía.

Si tus notas tienen otros nombres o están en otras carpetas, ponlo en **Ajustes → Módulos → Rutas de las notas**. Cada ruta es relativa a la carpeta de notas, por ejemplo `Salud/Báscula.md`.

## Formato de cada nota

Lo más cómodo es apuntar desde la app. Si prefieres escribir a mano, esto es lo que la app lee. Fíjate en el formato de las fechas: en unas tablas va `DD/MM/AAAA` y en otras `AAAA-MM-DD`.

- **Encabezado.** Va entre dos líneas `---` al principio de la nota (es YAML). Si un valor lleva `:`, ponlo entre comillas.
- **Tablas.** Las columnas se reconocen por su nombre, sin importar tildes ni mayúsculas. En Peso y Mascota cuenta además el orden.

### Peso

```markdown
---
peso_inicial_kg: 98
objetivo_peso_kg: 80
fecha_inicio: 01/09/2026
---

| Fecha | Peso (kg) | Notas |
| :---- | :-------: | :---- |
| 01/09/2026 | 98 | |
```

- Las fechas van en `DD/MM/AAAA`.
- Si no pones peso inicial, cuenta el primer pesaje.
- Si el objetivo está por encima del peso de partida (ganar músculo, recuperar peso), la app cuenta los kilos ganados, y la fecha estimada sale si el peso va subiendo.

### Medicación

Sirve para varios medicamentos a la vez:
- una pastilla diaria, una o varias veces al día;
- una inyección semanal o cada N días;
- lo que solo tomas cuando hace falta.

Lo cómodo es añadirlos en la pantalla Medicación, con «Añadir medicamento». La nota tiene dos tablas:

```markdown
## Medicamentos

| Medicamento | Dosis | Forma | Cada | Horas | Desde | Hasta | Notas |
| :---------- | :---- | :---- | :--: | :---- | :---- | :---- | :---- |
| Metformina | 850 mg | Pastilla | 1 | 09:00, 21:00 | | | |
| Ozempic | 0,5 mg | Inyección | 7 | | 2026-09-01 | | |
| Ibuprofeno | 400 mg | Pastilla | Si hace falta | | | | |

## Registro

| Fecha | Medicamento | Dosis | Zona | Notas |
| :---- | :---------- | :---- | :--- | :---- |
| 2026-10-20 | Ozempic | 0,5 mg | Abdomen izquierdo | |
```

En la tabla **Medicamentos**:
- **Cada:** días entre tomas. `1` es cada día y `7`, cada semana. También vale `diaria`, `semanal` o `cada 2 semanas`. Para lo que tomas solo cuando hace falta, `Si hace falta`.
- **Horas:** opcional. Con dos horas son dos tomas al día, y cada una tiene su casilla y su aviso. Sin horas, una toma al día, avisada a la hora de Avisos.
- **Desde y Hasta:** en `AAAA-MM-DD`. Fuera de esas fechas, el medicamento no sale en «Hoy» ni avisa.
- **Forma:** si contiene «Inyección», la toma lleva zona y la app sugiere el lado contrario al del último pinchazo.

Cómo se usa cada día:
- **Hoy:** cada toma diaria tiene una casilla en la pantalla, en Inicio y en la barra de menús. Marcarla la apunta en el registro; desmarcarla quita la última de hoy.
- **Lo periódico:** avisa dos días antes y cuando va tarde, con el botón «Me pinché hoy» o «Tomada hoy».
- **Cumplimiento:** el de lo diario sale como días completos de los últimos 30, sin contar hoy.

Una nota de la versión anterior (solo `Fecha | Dosis | Zona | Notas` y `cada_dias` en el encabezado) se lee como un único medicamento inyectable. Al añadir otro desde la app, la nota pasa sola a este formato, y se puede deshacer.

### Mascota

```markdown
---
nombre: Luna
nacimiento: 15/03/2021
comida: Pienso senior
---

## Visitas y vacunas

| Fecha | Tipo | Detalle | Próxima | Coste |
| ----- | ---- | ------- | ------- | ----- |
| 2026-10-01 | Vacuna | Rabia | 2027-10-01 | 40 |
```

- `nacimiento` va en `DD/MM/AAAA`; las fechas de la tabla, en `AAAA-MM-DD`.
- Con «Próxima», la app avisa cuando se acerca y cuando vence.

### Plan nutricional

- **Encabezado:** `kcal_objetivo`, `proteina_g`, `carbohidratos_g` y `grasas_g`.
- **Tabla:** una sección `## Reparto del día` con las columnas `Comida | kcal | Proteína (g)`.

### Salud y médicos

Tiene tres secciones:
- **`## Próximas citas`:** una tarea con fecha por cita, por ejemplo `- [ ] Dentista 📅 2026-11-02`.
- **`## Tratamientos`:** una lista con `- `.
- **`## Análisis`:** una tabla `Fecha | Prueba | Resultado | Notas`.

Las notas de cada visita se crean desde la pantalla, con «Nueva nota de visita».

### Casa

Cuatro secciones, cada una con su tabla:
- `## Reformas`: `Qué | Estancia | Prioridad | Coste estimado | Cuándo | Estado`.
- `## Compras`: `Qué | Estancia | Prioridad | Precio estimado | Dónde | Estado`.
- `## Electrodomésticos` y `## Pequeños electrodomésticos`: la primera columna es el aparato. Sirven para sugerir el mantenimiento.

### Ropa

- **`## Por comprar`:** una tabla `Prenda | Modelo | Prioridad | Precio | Fecha objetivo | Estado`. Lo que tiene el estado «Comprado» o «Descartado» deja de contar en el presupuesto.
- **`## Armario`:** una tabla libre.
- **`## Estrategia`** y **`## Calzado y accesorios`:** listas.

### Personas

Una tabla con una columna `Persona`, más `Relación`, `Cumpleaños` y `Última vez`:
- `Cumpleaños` va en `AAAA-MM-DD`, o `MM-DD` si no sabes el año.
- `Última vez` va en `AAAA-MM-DD`.

### Documentos

- Pon cualquier tabla con una columna que contenga «caduca», por ejemplo `Documento | Número o referencia | Caduca / renueva | Notas`.
- La fecha puede ir en `AAAA-MM-DD` o `DD/MM/AAAA`.
- La app avisa 30 días antes de cada caducidad.
- Apunta solo la referencia, nunca el documento.

### Objetivos

- **Objetivos:** una tabla con una columna `Objetivo`.
- **Revisión trimestral:** tres líneas que la pantalla rellena:

```markdown
- **Trimestre:** 
- **Qué ha avanzado:** 
- **Qué cambio o elimino:** 
```

### Finanzas y gastos

Gastos crea solo una nota por mes en `Finanzas/Gastos/AAAA-MM.md`, con tres secciones:
- **`## Ingresos`**
- **`## Partidas`:** `Partida | Previsto | Tipo | Pagado | Día | Cada | Desde`. El tipo puede ser Fijo, Variable o Ahorro.
- **`## Movimientos`:** `Fecha | Importe | Partida | Nota`.

El mes nuevo copia las partidas del anterior.

`Finanzas/Finanzas.md` guarda los objetivos de ahorro y los pagos sueltos, como tareas en `## Objetivos de ahorro y pagos`.

## Tareas

Una tarea es cualquier línea `- [ ] …` de cualquier nota. Las que apuntas desde la app van a `Organización/Inbox.md`. Se escriben igual que en el plugin Tasks de Obsidian:

| Escribe | Significa |
|---|---|
| `📅 2026-11-02` | Fecha límite |
| `⏳ 2026-11-01` | Fecha en que piensas hacerla |
| `🔁 every week` | Se repite (`every day`, `every 2 weeks`, `every month`, `every week when done`…) |
| `⏫`, `🔼`, `🔽` | Prioridad alta, media y baja |

En la captura rápida (⇧⌘N) puedes escribirlo en lenguaje natural: «llamar al dentista el viernes», «pagar el alquiler cada mes».

## Notas que crea la app sola

- **Revisión semanal:** `Revisiones/AAAA-Wnn.md`, con los hábitos de la semana.
- **Nota del día:** `Diario/AAAA-MM-DD.md`, con el ánimo y el sueño.
- **Plantillas:** van en la carpeta `Plantillas/`. El asistente puede crear 10 de ejemplo (Reunión, Idea, Lectura, Viaje, Receta, Película o serie, Entrenamiento, Comparar opciones, Curso y Meta de ahorro); también se crean desde «Nueva nota». Una plantilla puede hacer preguntas al crear la nota (`{{?Pregunta}}` o `{{?Pregunta|valor por defecto}}`) y sugerir carpeta con `plantilla_carpeta:` en el encabezado.

## Gráficas en una nota

Puedes dibujar cualquier tabla de una nota con un bloque `grafica`. Está explicado en el [README](README.md#gráficas-en-una-nota).

## Copias y deshacer

- La app copia toda la carpeta antes del primer cambio de cada día. Guarda las últimas 14 copias automáticas.
- Cada cambio se deshace con ⌥⌘Z.
- Para recuperar una versión antigua de una nota: Notas → ⋯ → Historial.
