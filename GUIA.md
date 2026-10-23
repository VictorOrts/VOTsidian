# Guía de VOTsidian

VOTsidian es una agenda personal para Mac. Todo lo que apuntas se guarda en notas Markdown (archivos `.md`) dentro de una carpeta tuya. Esas mismas notas se pueden abrir con Obsidian o con cualquier editor de texto: la app no tiene una base de datos aparte.

## Empezar

1. Crea la app con `./scripts/build-app.sh` y ábrela (`build/VOTsidian.app`).
2. La primera vez sale **Empecemos**:
   - **Carpeta.** Por defecto, `iCloud Drive/VOTsidian`, para tenerla en todos tus dispositivos. Con «Elegir otra carpeta…» puedes usar una que ya tengas (por ejemplo, tu vault de Obsidian) o crear una nueva.
   - **Qué quieres llevar.** Marca los módulos que te interesan. Si eliges Mascota o Medicación, escribe también su nombre.
3. Pulsa **Crear notas y empezar**. La app crea una nota por módulo, con el formato que sabe leer, y oculta los módulos que no marcaste.

Si la carpeta ya tiene notas, no se cambia ninguna: solo se crean las que faltan.

Siempre están **Tareas, Calendario, Planificar semana, Revisión semanal y mensual, Proyectos, Notas, Bases, Grafo, Enlaces rotos y Avisos**.

Todo se cambia después en **Ajustes → Módulos**: mostrar u ocultar módulos, crear la nota que falte o cambiar dónde está cada nota.

## Módulos y sus notas

Si falta la nota de una pantalla, arriba sale un aviso con «Crear la nota». No hace falta pulsarlo: la nota se crea sola la primera vez que apuntas algo desde la pantalla.

| Módulo | Pantallas | Nota (ruta por defecto) |
|---|---|---|
| Peso y medidas | Peso, Correlaciones | `Cambio físico/Peso.md` (y `Cambio físico/Medidas.md` al activar las medidas) |
| Plan nutricional | Plan nutricional | `Cambio físico/Plan Nutricional.md` |
| Medicación inyectable | (nombre del medicamento) | `Cambio físico/Mounjaro.md` |
| Salud y médicos | Salud y médicos | `Organización/Médico/Médico.md` |
| Finanzas y gastos | Finanzas, Gastos | `Finanzas/Finanzas.md` y una nota por mes en `Finanzas/Gastos/` |
| Casa | Casa | `Casa/Casa.md` |
| Lista de la compra | Compra | `Cambio físico/Lista de la compra.md` |
| Ropa | Moda | `Moda/Armario.md` |
| Mascota | (nombre de la mascota) | `Nala/Nala.md` |
| Personas | Personas | `Organización/Personas.md` |
| Documentos | Documentos | `Organización/Documentos.md` |
| Objetivos | Objetivos | `Organización/Objetivos.md` |

Si tus notas tienen otros nombres o están en otras carpetas, ponlo en **Ajustes → Módulos → Rutas de las notas**. Cada ruta es relativa a la carpeta de notas, por ejemplo `Salud/Báscula.md`.

## Formato de cada nota

Lo más cómodo es apuntar desde la app. Si prefieres escribir a mano, esto es lo que la app lee. Fíjate en el formato de las fechas: en unas tablas va `DD/MM/AAAA` y en otras `AAAA-MM-DD`.

- **Encabezado.** Va entre dos líneas `---` al principio de la nota (es YAML). Si un valor lleva `:`, ponlo entre comillas.
- **Tablas.** Las columnas se reconocen por su nombre, sin importar tildes ni mayúsculas. En Peso, Medicación y Mascota cuenta además el orden.

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

### Medicación

```markdown
---
nombre: Ozempic
cada_dias: 7
---

| Fecha | Dosis | Zona | Notas |
| ----- | ----- | ---- | ----- |
| 2026-10-01 | 0,5 mg | Abdomen | |
```

- **Fechas:** van en `AAAA-MM-DD`.
- **`cada_dias`:** dice cada cuántos días toca. Si no lo pones, la app cuenta 9.
- **`nombre`:** es el nombre de la pantalla y de los avisos. Una nota sin `nombre` se muestra como «Mounjaro»; si aún no hay nota, como «Medicación».

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
- **Plantillas propias:** van en la carpeta `Plantillas/`. Una plantilla puede hacer preguntas al crear la nota, con `{{?Pregunta}}`.

## Gráficas en una nota

Puedes dibujar cualquier tabla de una nota con un bloque `grafica`. Está explicado en el [README](README.md#gráficas-en-una-nota).

## Copias y deshacer

- La app copia toda la carpeta antes del primer cambio de cada día. Guarda las últimas 14 copias automáticas.
- Cada cambio se deshace con ⌥⌘Z.
- Para recuperar una versión antigua de una nota: Notas → ⋯ → Historial.
