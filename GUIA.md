# Guía de VOTsidian

VOTsidian es una agenda personal para Mac. Todo lo que apuntas se guarda en notas Markdown (archivos `.md`) dentro de una carpeta tuya. Esas notas se abren igual con Obsidian o con cualquier editor de texto: la app no tiene una base de datos aparte.

Esta guía explica cómo empezar y qué formato tiene cada nota, por si prefieres escribirlas o arreglarlas a mano.

## Contenido

- [Empezar](#empezar)
- [Módulos y sus notas](#módulos-y-sus-notas)
- [Convenciones](#convenciones)
- [Formato de cada nota](#formato-de-cada-nota)
  - [Peso](#peso) · [Medidas](#medidas) · [Plan nutricional](#plan-nutricional) · [Medicación](#medicación) · [Salud y médicos](#salud-y-médicos)
  - [Finanzas y gastos](#finanzas-y-gastos) · [Suscripciones](#suscripciones) · [Préstamos y deudas](#préstamos-y-deudas)
  - [Casa](#casa) · [Lista de la compra](#lista-de-la-compra) · [Ropa](#ropa) · [Mascota](#mascota) · [Vehículo](#vehículo) · [Viajes](#viajes) · [Lecturas](#lecturas)
  - [Personas](#personas) · [Documentos](#documentos) · [Trámites y seguros](#trámites-y-seguros) · [Objetivos](#objetivos)
- [Tareas](#tareas) · [Mi día](#mi-día) · [La ventana](#la-ventana) · [Órdenes rápidas](#órdenes-rápidas-k)
- [Notas que crea la app](#notas-que-crea-la-app)
- [Gráficas en una nota](#gráficas-en-una-nota)
- [Lienzos](#lienzos)
- [Calendar y avisos](#calendar-y-avisos)
- [Siri y Atajos](#siri-y-atajos)
- [Copias y deshacer](#copias-y-deshacer)

## Empezar

1. Crea la app con `./scripts/build-app.sh` y ábrela (`build/VOTsidian.app`).
2. La primera vez sale **Empecemos**:
   - **Carpeta.** Por defecto, `iCloud Drive/VOTsidian`, para tenerla en todos tus dispositivos. Con «Elegir otra carpeta…» puedes usar una que ya tengas (por ejemplo, tu vault de Obsidian) o crear una nueva.
   - **Qué quieres llevar.** Marca los módulos que te interesan. Si eliges Mascota, escribe también su nombre. Los medicamentos se añaden después, en su pantalla.
3. Pulsa **Crear notas y empezar**. La app crea una nota por módulo, con el formato que sabe leer, y oculta los módulos que no marcaste.

Si la carpeta ya tiene notas, no se cambia ninguna: solo se crean las que faltan.

Siempre están **la Agenda (Mi día, Planificar semana y Tareas), Calendario, Revisión semanal y mensual, Proyectos, Notas, Bases, Grafo, Lienzo, Enlaces rotos y Avisos**. Todo lo demás se cambia en **Ajustes → Módulos**: mostrar u ocultar módulos, crear la nota que falte o cambiar dónde está cada nota. Los módulos que lleguen en una actualización quedan ocultos en una carpeta ya configurada (la app avisa), salvo que ya tengas su nota: los activas cuando quieras.

## Módulos y sus notas

Si falta la nota de una pantalla, arriba sale un aviso con «Crear la nota». No hace falta pulsarlo: la nota se crea sola la primera vez que apuntas algo desde la pantalla.

| Módulo | Pantallas | Nota (ruta por defecto) |
|---|---|---|
| Peso y medidas | Peso, Correlaciones | `Salud/Peso.md` (y `Salud/Medidas.md` al activar las medidas; las fotos, en `Salud/Fotos`) |
| Plan nutricional | Plan nutricional | `Salud/Plan nutricional.md` |
| Medicación | Medicación | `Salud/Medicación.md` |
| Salud y médicos | Salud y médicos | `Salud/Médico.md` (las notas de visita y los PDF de análisis, en `Salud/`) |
| Finanzas y gastos | Finanzas, Gastos | `Finanzas/Finanzas.md` y una nota por mes en `Finanzas/Gastos/` |
| Suscripciones | Suscripciones | `Finanzas/Suscripciones.md` |
| Préstamos y deudas | Préstamos | `Finanzas/Préstamos.md` |
| Casa | Casa | `Casa/Casa.md` |
| Lista de la compra | Compra | `Casa/Lista de la compra.md` |
| Ropa | Moda | `Moda/Armario.md` |
| Mascota | (nombre de la mascota) | `Mascota/Mascota.md` |
| Vehículo | (nombre del vehículo) | `Vehículo/Vehículo.md` |
| Viajes | Viajes | `Viajes/Viajes.md` |
| Lecturas | Lecturas | `Lecturas/Lecturas.md` |
| Personas | Personas | `Organización/Personas.md` |
| Documentos | Documentos | `Organización/Documentos.md` |
| Trámites y seguros | Trámites y seguros | `Organización/Trámites y seguros.md` |
| Objetivos | Objetivos | `Organización/Objetivos.md` |

Si tus notas tienen otros nombres o están en otras carpetas, ponlo en **Ajustes → Módulos → Rutas de las notas**. Cada ruta es relativa a la carpeta de notas, por ejemplo `Salud/Báscula.md`.

## Convenciones

Lo más cómodo es apuntar desde la app. Si escribes a mano, ten en cuenta esto:

- **Encabezado.** Va entre dos líneas `---` al principio de la nota (es YAML). Si un valor lleva `:`, ponlo entre comillas.
- **Tablas.** Las columnas se reconocen por su nombre, sin importar tildes ni mayúsculas. En Peso y Mascota cuenta además el orden.
- **Números.** Se acepta coma decimal y punto de millares: `105,5`, `1.234,50 €`. En los km del vehículo, el punto es siempre de millares.
- **Fechas.** Cada nota usa un formato. Donde pone «cualquiera», valen los dos.

| Nota | Formato de fecha |
|---|---|
| Peso, Medidas | `DD/MM/AAAA` |
| Mascota (`nacimiento`) | `DD/MM/AAAA` |
| Mascota (tabla), Medicación, Personas, Salud, Gastos, Tareas | `AAAA-MM-DD` |
| Documentos, Vehículo, Suscripciones, Préstamos, Viajes, Lecturas, Trámites y seguros | cualquiera |

## Formato de cada nota

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

- Si no pones peso inicial, cuenta el primer pesaje.
- Si el objetivo está por encima del peso de partida (ganar músculo, recuperar peso), la app cuenta los kilos ganados, y la fecha estimada sale si el peso va subiendo.

### Medidas

```markdown
| Fecha | Cintura (cm) | Cadera (cm) | Pecho (cm) | Brazo (cm) | Muslo (cm) | Grasa (%) | Notas |
| :---- | -----------: | ----------: | ---------: | ---------: | ---------: | --------: | :---- |
| 01/10/2026 | 98 | 104 | | | | | |
```

Mídete una vez al mes, en ayunas, en los mismos puntos. Desde ⌘K también vale `cintura 98`.

### Plan nutricional

- **Encabezado:** `kcal_objetivo`, `proteina_g`, `carbohidratos_g` y `grasas_g`.
- **Tabla:** una sección `## Reparto del día` con las columnas `Comida | kcal | Proteína (g)`.

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

Columnas de **Medicamentos**:

| Columna | Qué poner |
|---|---|
| Cada | Días entre tomas: `1` es cada día y `7`, cada semana. También `diaria`, `semanal`, `cada 2 semanas` o `Si hace falta`. |
| Horas | Opcional. Con dos horas son dos tomas al día, cada una con su casilla y su aviso. Sin horas, una toma al día, avisada a la hora de Avisos. |
| Desde, Hasta | Fuera de esas fechas, el medicamento no sale en «Hoy» ni avisa. |
| Forma | Si contiene «Inyección», la toma lleva zona y la app sugiere el lado contrario al del último pinchazo. |

En el día a día:
- **Hoy:** cada toma diaria tiene una casilla en la pantalla, en Inicio y en la barra de menús. Marcarla la apunta en el registro; desmarcarla quita la última de hoy.
- **Lo periódico:** avisa dos días antes y cuando va tarde, con el botón «Me pinché hoy» o «Tomada hoy». Si va tarde, sale hoy en el Calendario, Mi día y el panel Hoy («Toca pinchazo… · 3 días tarde»), y los siguientes se cuentan desde hoy.
- **Cumplimiento:** el de lo diario sale como días completos de los últimos 30, sin contar hoy.

Una nota con una sola tabla `Fecha | Dosis | Zona | Notas` (y `nombre` y `cada_dias` en el encabezado) se lee como un único medicamento inyectable. Al añadir otro desde la app, la nota pasa sola al formato de dos tablas, y se puede deshacer.

### Salud y médicos

Tiene tres secciones:
- **`## Próximas citas`:** una tarea con fecha por cita, y la hora si la sabes: `- [ ] Dentista 📅 2026-11-02 ⏰ 17:30`. Las citas avisan el día anterior y, con hora, también una hora antes (en Calendar y en las notificaciones).
- **`## Tratamientos`:** una lista con `- `.
- **`## Análisis`:** una tabla `Fecha | Prueba | Resultado | Notas`.

Las notas de cada visita se crean desde la pantalla, con «Nueva nota de visita»; en su encabezado, `fecha:` y `hora:` (`17:30`) las ponen en el Calendario. Los PDF o imágenes de análisis se copian a la carpeta `Análisis`; si ya hay un archivo con el mismo nombre que es otro distinto, el nuevo se numera («análisis 2.pdf») y nunca se pisa nada.

### Finanzas y gastos

Gastos crea sola una nota por mes en `Finanzas/Gastos/AAAA-MM.md`, con tres secciones:

| Sección | Columnas |
|---|---|
| `## Ingresos` | Lo que entra en el mes. |
| `## Partidas` | `Partida \| Previsto \| Tipo \| Pagado \| Día \| Cada \| Desde`. El tipo puede ser Fijo, Variable o Ahorro. |
| `## Movimientos` | `Fecha \| Importe \| Partida \| Nota`. |

El mes nuevo copia las partidas del anterior.

`Finanzas/Finanzas.md` guarda los objetivos de ahorro y los pagos sueltos, como tareas en `## Objetivos de ahorro y pagos`.

### Suscripciones

```markdown
## Servicios

| Servicio | Importe | Cada | Próximo cobro | Partida | Estado | Notas |
| :------- | ------: | :--- | :------------ | :------ | :----- | :---- |
| Netflix | 12,99 € | Mensual | 2026-10-15 | Suscripciones | Activa | |
| Cloud | 99 € | Anual | 2026-12-01 | | Activa | |
| Curso | 29 € | Mensual | 2026-11-01 | | Prueba | |
```

| Columna | Qué poner |
|---|---|
| Cada | `Semanal`, `Quincenal`, `Mensual`, `Bimestral`, `Trimestral`, `Semestral`, `Anual`, «cada 2 semanas», «cada 2 años» o un número de meses. Vacío es mensual. |
| Próximo cobro | Un cobro cualquiera de la serie, el último o el próximo: la app calcula los siguientes aunque la fecha sea antigua. En una prueba, el día que acaba y empieza a cobrar. |
| Estado | `Activa`, `Prueba` o `Cancelada`. La cancelada no cuenta ni avisa, y la pantalla dice cuánto ahorras al año. |
| Partida | La partida de Gastos a la que va el cobro. Opcional: sin ella, la app adivina la partida por el nombre. |

- Avisa 7 días antes de cada renovación (14 si es anual) y cuando una prueba está a punto de acabar. En Calendar sale el día antes.
- «Apuntar en Gastos» añade el cobro de hoy al mes, en la partida de la fila, y se deshace con ⌥⌘Z.
- Los totales al mes y al año cuentan solo las activas.

### Préstamos y deudas

```markdown
## Lo que debo

| Préstamo | Pendiente | Cuota | Día | Hasta | Partida | Notas |
| :------- | --------: | ----: | :-: | :---- | :------ | :---- |
| Coche | 6.000 € | 500 € | 15 | | Préstamo personal | |
| Ana | 200 € | | | | | |

## Pagos

| Fecha | Préstamo | Importe | Notas |
| :---- | :------- | ------: | :---- |
| 2026-09-15 | Coche | 500 | |
```

- **Pendiente** es lo que debías al empezar a apuntar aquí. Lo que queda es Pendiente menos los pagos que tengan el mismo nombre en `Préstamo`.
- **Cuota** y **Día** (del mes) son opcionales. Sin ellos es una deuda que pagas cuando puedes, sin calendario ni avisos.
- **Hasta** corta la serie de cuotas en esa fecha.
- La app cuenta las cuotas que quedan y la fecha en que acabas. No calcula intereses: para ajustarlo a lo que dice el banco, cambia «Pendiente».
- Avisa 3 días antes de la cuota si no se apuntó este mes, y avisa sin urgencia si el día ya pasó sin apuntar. En Calendar salen las cuotas de los próximos 12 meses, con aviso el día antes.
- «Apuntar cuota» añade una fila a Pagos y, si quieres, el importe a Gastos (partida de la fila); se deshacen juntos.

### Casa

Cuatro secciones, cada una con su tabla:

| Sección | Columnas |
|---|---|
| `## Reformas` | `Qué \| Estancia \| Prioridad \| Coste estimado \| Cuándo \| Estado` |
| `## Compras` | `Qué \| Estancia \| Prioridad \| Precio estimado \| Dónde \| Estado` |
| `## Electrodomésticos`, `## Pequeños electrodomésticos` | `Aparato \| Marca \| Modelo \| Comprado \| Garantía hasta`. Sirven para sugerir el mantenimiento. |

### Lista de la compra

Una sección `## …` por pasillo (Fruta y verdura, Despensa, Limpieza y hogar…) con una casilla por artículo:

```markdown
## Lácteos y huevos

- [ ] Leche
- [x] Huevos
```

Desde ⌘K, `compra leche y pan` los añade. Si pegas una lista con un artículo por línea (con o sin viñetas), entra cada uno por separado. «Vaciar comprados» quita lo que ya está marcado.

#### Menú de la semana

La lista se completa con la nota **Menú y compra** (junto al plan nutricional; «Crear el menú» en Compra la crea si falta). Lee dos cosas:

```markdown
## Menú semanal
| Día | Comida | Cena |
| :-- | :----- | :--- |
| Lunes | Pollo + patata + pepino, tomate y maíz | Salmón fresco + cottage + verduras |
| Martes | Pavo o pollo + batata + ensalada | 2 huevos + 150 g de claras + tomate |

## Lista de la compra
- **Proteína:** pechuga de pollo y pavo, salmón fresco y ahumado, huevos.
- **Verdura y fruta:** tomate, pepino, ensalada.
```

- **El menú:** una fila por día y una columna por comida (las que quieras: Desayuno, Comida, Cena…). Cada plato se parte en ingredientes por «+», comas, «y», «con» y «o» (con «pollo o pavo» cuentan los dos). Se quitan las cantidades del principio («200 g de»), lo que va entre paréntesis y lo que va con «sin». Las celdas vacías, «—», «libre» o «comer fuera» no cuentan.
- **`## Lista de la compra`:** los básicos de cada semana, una línea `- **Sección:** artículo, artículo…` por sección.

En Compra, la tarjeta «Menú de la semana» enseña cada ingrediente con en cuántas comidas sale (×3) y si ya está en la lista (✓). «Completar la lista» añade los básicos que falten y después los ingredientes del menú que no estén ya, todo en un solo deshacer (⌥⌘Z). Un ingrediente ya está si un artículo lleva todas sus palabras, en singular o plural y aunque esté comprado: «Pechuga de pollo y pavo» cubre «Pavo», «Patatas» cubre «patata». Lo nuevo va a la sección de los básicos que comparta alguna palabra con él («YoPRO de fresa» a la de «YoPRO»); si no hay, al pasillo que le toca si tu lista va por pasillos, o a «Otros». «Ver la semana» enseña el menú en una rejilla y «Editar el menú» abre la nota.

### Ropa

- **`## Por comprar`:** una tabla `Prenda | Modelo | Prioridad | Precio | Fecha objetivo | Estado`. Lo que tiene el estado «Comprado» o «Descartado» deja de contar en el presupuesto.
- **`## Armario`:** una tabla libre.
- **`## Estrategia`** y **`## Calzado y accesorios`:** listas.

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

Con «Próxima», la app avisa cuando se acerca y cuando vence.

### Vehículo

```markdown
---
nombre: Coche
matricula: 1234 ABC
km: 114100
---

## Fechas

| Qué | Vence | Notas |
| :-- | :---- | :---- |
| ITV | 2027-03-15 | |
| Seguro | 01/06/2027 | Póliza 99 |

## Mantenimiento

| Fecha | Km | Qué | Taller | Coste | Cada (km) | Cada (meses) |
| :---- | -: | :-- | :----- | ----: | --------: | -----------: |
| 2026-01-10 | 100.000 | Aceite y filtros | Taller Pepe | 180 € | 15.000 | 12 |

## Repostajes

| Fecha | Km | Litros | Importe |
| :---- | -: | -----: | ------: |
| 2026-09-20 | 114.100 | 30 | 47,40 € |
```

| Tabla | Cómo se lee |
|---|---|
| Fechas | Cualquier tabla con una columna `Vence`. Avisa 30 días antes. |
| Mantenimiento | La tabla con columna `Taller` o bajo `## Mantenimiento`. Con `Cada (km)` o `Cada (meses)`, la app cuenta desde la última vez que se hizo lo mismo (misma columna `Qué`) y avisa cuando faltan menos de 1.000 km o 30 días. |
| Repostajes | La tabla con columna `Litros`. El consumo sale de depósito lleno a depósito lleno, así que llena el depósito cada vez. |

- Los km actuales son los más altos entre la ficha, el taller y los repostajes.
- Al apuntar desde la pantalla, «Apuntar también en Gastos» añade el importe al mes, en la partida de transporte si la hay.

### Viajes

```markdown
## Destinos

| Destino | Salida | Vuelta | Presupuesto | Estado | Notas |
| :------ | :----- | :----- | ----------: | :----- | :---- |
| Lisboa | 2026-11-13 | 2026-11-18 | 800 € | Reservado | |

## Gastos del viaje

| Fecha | Viaje | Concepto | Importe |
| :---- | :---- | :------- | ------: |
| 2026-10-24 | Lisboa | Vuelo | 120 € |

## Equipaje

- [ ] Cargador
- [x] DNI
```

- **Estado:** `Idea`, `Planeando`, `Reservado`, `Hecho` o `Cancelado`. Los dos últimos dejan de contar como viaje por venir.
- **Gastos del viaje:** en `Viaje`, el nombre exacto del destino. Suman contra el presupuesto, y la pantalla puede apuntarlos también en Gastos.
- **Equipaje:** una lista de siempre, que se reutiliza: marca al hacer la maleta y «Desmarcar todo» la deja lista para el próximo viaje. Estas casillas no cuentan como tareas.
- Avisa cuando el viaje está a menos de 30 días, si te pasas del presupuesto y si el pasaporte de Documentos caduca menos de 6 meses después de salir (solo en viajes de los próximos 6 meses). En Calendar sale 7 días antes.

### Lecturas

```markdown
---
objetivo_anual: 12
---

## Libros

| Título | Autor | Estado | Empezado | Terminado | Nota | Páginas |
| :----- | :---- | :----- | :------- | :-------- | :--- | ------: |
| Dune | Frank Herbert | Terminado | 2026-01-01 | 2026-01-20 | ⭐⭐⭐⭐ | 600 |
```

- **Estado:** `Pendiente`, `Leyendo`, `Terminado` o `Abandonado`. Si lo dejas vacío, manda la fecha: con `Terminado` es terminado, con solo `Empezado`, en marcha.
- **Nota:** de 1 a 5, o con ⭐.
- **objetivo_anual:** los libros que quieres terminar este año. Pasados 30 días del año, la pantalla dice cuántos saldrían a fin de año al ritmo de ahora.
- En la pantalla, «Empezar», «Terminar» (con nota) y «Abandonar» cambian el estado y ponen la fecha de hoy. Los terminados salen en el Calendario.

### Personas

Una tabla con una columna `Persona`, más `Relación`, `Cumpleaños` y `Última vez`. `Cumpleaños` admite `MM-DD` si no sabes el año. Quien nació un 29 de febrero sale el 28 los años que no son bisiestos; una fecha que no existe («02-30») no sale en el Calendario.

### Documentos

- Cualquier tabla con una columna que contenga «caduca», por ejemplo `Documento | Número o referencia | Caduca / renueva | Notas`.
- La app avisa 30 días antes de cada caducidad.
- Apunta solo la referencia, nunca el documento.

### Trámites y seguros

```markdown
## Impuestos y plazos

| Trámite | Plazo | Cada | Importe | Hecho | Notas |
| :------ | :---- | :--- | ------: | :---- | :---- |
| Declaración de la renta | 2027-06-30 | Anual | | 2026-05-10 | |
| IBI | 2026-11-05 | Anual | 420 € | | |
| Renovar el pasaporte | 2027-02-01 | | | | |

## Pólizas

| Seguro | Compañía | Póliza | Prima | Cada | Renovación | Teléfono | Partida | Notas |
| :----- | :------- | :----- | ----: | :--- | :--------- | :------- | :------ | :---- |
| Hogar | Mapfre | H-123 | 320 € | Anual | 2026-11-15 | 900 100 200 | | |
```

| Columna | Qué poner |
|---|---|
| Plazo | La próxima fecha límite. En los que se repiten, cualquier plazo de la serie. |
| Cada | `Anual`, `Semestral`, `Trimestral`, `Mensual`… Vacío o «una vez» si no se repite. |
| Hecho | La fecha en que lo hiciste; la pone «Hecho» en la pantalla. Cuenta para el plazo más cercano: la renta presentada en mayo cumple el plazo de junio, y un pago unos días tarde cumple el plazo que acaba de pasar. |
| Prima, Cada (seguros) | Lo que pagas y cada cuánto; vacío es anual. |
| Renovación | El día que se renueva y se cobra. |
| Partida | La de Gastos a la que va la prima al pulsar «Apuntar pago». Sin ella, la de seguros. |

- **Avisos:** 30 días antes de cada plazo (urgente si ya pasó sin marcarlo hecho) y 30 días antes de que se renueve un seguro, para comparar ofertas. En Calendar, 7 días antes de cada plazo y 30 antes de cada renovación, con el teléfono de asistencia.
- **Documentos** guarda la referencia y la caducidad de pólizas y contratos; aquí van los pagos, las renovaciones y los plazos.

### Objetivos

- **Objetivos:** una tabla con una columna `Objetivo`.
- **Revisión trimestral:** tres líneas que la pantalla rellena:

```markdown
- **Trimestre:** 
- **Qué ha avanzado:** 
- **Qué cambio o elimino:** 
```

## Tareas

Una tarea es cualquier línea `- [ ] …` de cualquier nota. Las que apuntas desde la app van a `Organización/Inbox.md`. Las casillas de la lista de la compra y del equipaje de Viajes no cuentan como tareas. Se escriben igual que en el plugin Tasks de Obsidian:

| Escribe | Significa |
|---|---|
| `📅 2026-11-02` | Fecha límite |
| `⏰ 17:30` | Hora, detrás de la fecha (opcional). Sin ella, la tarea es de todo el día. |
| `⏱ 1h30m` | Lo que calculas que dura (`45m`, `2h`, `1h30m`). Da la altura del bloque en Mi día y la duración del evento en Calendar (sin ella, 15 minutos). |
| `🔕` | Sin aviso: sigue en la app, pero no va a Calendar ni a las notificaciones de macOS. Se pone con «sin aviso» al escribirla o desde «Editar tarea». |
| `⏳ 2026-11-01` | Fecha en que piensas hacerla |
| `🔁 every week` | Se repite (`every day`, `every 2 weeks`, `every month`, `every week when done`…). `⏰`, `⏱` o `🔕` pueden ir antes o después. |
| `⏫`, `🔼`, `🔽` | Prioridad alta, media y baja |

En la captura rápida (⇧⌘N) puedes escribirlo en lenguaje natural: «llamar al dentista el viernes», «pagar el alquiler cada mes», «reunión mañana a las 17:30». También «el lunes 2 de noviembre», «el viernes que viene», «dentro de 3 días», «en una semana», «en enero» (el día 1), «reunión 9:00-10:30» (hora y duración) y «leer al día» (se repite cada día).

La hora se entiende escrita así: «a las 17:30», «a las 5 de la tarde», «a las 9 y media», «a las 11 menos cuarto», «sobre las 10», «a mediodía» o «17:30» suelto. «A las 1» a «a las 6» sin «de la mañana» se toman como de la tarde, que es como se suele decir una cita. Si solo dices la hora, sin día, es para hoy. Las tareas con hora salen con ella en el Calendario, en Hoy y en Tareas, ordenadas por hora; en Calendar son un evento a esa hora con aviso una hora antes.

La duración se entiende así: «de 10 a 11:30» (pone la hora y la duración), «durante 45 min», «durante 2 horas», «durante hora y media», «durante media hora» o `⏱ 1h30m` tal cual. Un tramo que pasa de medianoche («de 22 a 2») no se toma como duración, ni uno de cantidades («subir de 3 a 5 kg», «leer de 10 a 20 páginas»). Las órdenes de ⌘K («tarea …») entienden lo mismo: hora, duración, repetición, prioridad y «sin aviso».

## Mi día

El día por horas, de 0 a 24 h. No guarda nada aparte: todo va en la línea de cada tarea, con `⏰` y `⏱`.

- **Bloques.** Cada tarea con hora es un bloque tan alto como lo que dura (30 minutos si no tiene `⏱`). Las citas de Médico también se mueven, porque son tareas. Las citas de una nota de visita, las tomas de medicación con hora y lo que viene de otros módulos salen fijos; pulsarlos lleva a su pantalla. Lo de todo el día (cumpleaños, renovaciones…) va en fichas arriba.
- **Sin hora.** A la izquierda, las tareas del día que aún no tienen hora y, si es hoy, las vencidas. Arrástralas a una franja para ponerles hora (en pasos de 15 minutos). Arrastrar un bloque a otra hora lo mueve; tirar del borde de abajo cambia lo que dura. Para quitarle la hora a una tarea, arrástrala de vuelta a «Sin hora». Con el botón derecho sobre un bloque: completar, quitar la hora, cuánto dura, editar o abrir su nota.
- **Ficha.** Un clic en un bloque (o en una ficha de todo el día) lo selecciona y abre su ficha en el panel, en lugar de «Sin hora». El doble clic, además, pone el cursor en el texto. Una tarea se edita entera: texto, día, hora, duración, prioridad y sin aviso, con «Guardar» (Intro) o «Cancelar» (Esc); también se completa, se elimina o se abre su nota. De una cita guardada como nota de visita se cambian la fecha y la hora (su `fecha:` y `hora:`). Lo que viene de otros módulos (una toma de medicación, un cumpleaños, una renovación) solo se ve, con un botón que lleva a su pantalla, porque se cambia allí. Un clic en un hueco, la ✕ o Esc cierran la ficha.
- **Jornada.** Arriba, lo planificado frente a las horas que quieres dedicar al día (8 por defecto, se cambia en el menú «de 8 h»). Cuentan las tareas y citas pendientes con hora, y las tareas sin hora que tienen duración; la medicación y lo hecho no. Si te pasas, la barra se pone roja.
- **Repartir.** Coloca las tareas sin hora en los huecos libres, por orden (primero las vencidas y las de más prioridad), entre las 9:00 y las 20:00, o desde ahora si es hoy. Las que no caben se quedan sin hora. ⌥⌘Z lo deshace de una vez.
- **Empezar el día.** Desde el panel Hoy, Mi día, la barra de menús o ⌘K. Repasa en tres pasos lo que quedó pendiente (a hoy, a mañana o hecha), lo de hoy (con cuánto dura cada cosa) y lo de los próximos tres días (adelantar a hoy), y termina en Mi día para repartirlo.
- **Leyenda.** Encima del mes salen solo los tipos que hay ese mes; los que comparten color van juntos («medicación / suscripción»).
- **Semana por horas.** En Calendario, «Semana» enseña de lunes a domingo con las mismas columnas de horas. Soltar una tarea en una columna le pone ese día y esa hora; en la cabecera de un día, solo el día. «Por horas», en el panel de un día, lo abre en Mi día. Igual que en Mi día, un clic en un bloque, en una ficha de la cabecera o en una fila del panel (también en la vista de mes) abre su ficha arriba del panel derecho. El botón junto a «Mes / Semana» pliega ese panel para que la rejilla gane anchura (se recuerda); al abrir la ficha de un evento, vuelve a salir. Pasar el ratón por un título cortado lo enseña entero.

## La ventana

- **Barra de arriba.** Atrás y adelante (⌘[ y ⌘]) recorren las pantallas que has visitado. Bajo el título sale la sección (Dinero, Cuerpo…). A la derecha: buscar (⌘K), añadir (⇧⌘N) y el panel Hoy (⌥⌘0). Con un enfoque en marcha, su cuenta atrás.
- **Agenda.** Mi día, Planificar semana y Tareas son una sola entrada de la barra lateral, con «Día · Semana · Lista» arriba. Al volver a la Agenda sale el último modo que usaste. Cambiar de modo no llena el historial de Atrás.
- **Panel Hoy.** A la derecha de todas las pantallas salvo Calendario, que tiene el suyo. Arriba, el mes con un punto por tipo de evento (los colores del Calendario); un clic en un día enseña lo de ese día y el campo de abajo añade a ese día. Si es hoy, también lo vencido. Las tareas se marcan con un clic; con el botón derecho, enfoque, pasar a mañana o ver su nota. Abajo: la nota de hoy, Empezar el día y Cerrar el día. Si la ventana es estrecha se esconde solo; ⌥⌘0 lo oculta del todo, y entonces Inicio vuelve a enseñar su tarjeta «Hoy». Con la app abierta pasada la medianoche (o al despertar el Mac), el panel, Mi día y el Calendario pasan solos al día nuevo si enseñaban hoy. Lo mismo la fecha de los formularios (Peso, Medicación, Mascota, Vehículo, Suscripciones, Préstamos, medidas y fotos): lo que apuntes por la mañana va al día nuevo, no al de ayer.
- **Notas al lado.** Con el panel visible, un enlace `[[nota]]` pulsado fuera de Notas abre la nota en la pestaña «Nota» del panel: se pueden marcar casillas y cambiar propiedades, y «Editar en Notas» la abre en el editor. «Otra ventana» la deja en una ventana aparte. De una nota muy larga se enseñan las primeras 250 líneas, con un enlace para seguir en Notas. Las notas con pantalla propia (Vehículo, Peso…) siguen abriendo su pantalla.
- **Fijadas y recientes.** Con el botón derecho en una pantalla de la barra lateral, «Fijar arriba». Las fijadas son también ⌘2…⌘9, en su orden (⌘1 es Inicio), así que no cambian al ocultar un módulo. Debajo, las tres últimas notas abiertas. Al principio están fijadas la Agenda, Calendario y Notas.
- **Otra ventana.** Botón derecho en una pantalla → «Abrir en otra ventana», por ejemplo para tener Gastos y Notas a la vez.
- **Enfoque.** Botón derecho en una tarea (en Tareas, Mi día o el panel) → «Empezar enfoque»: dura lo que la tarea (`⏱`) o 25 minutos. Suena al acabar y lo dice arriba. Un clic en la cuenta atrás lo para. No se guarda nada en las notas.
- **Campos de añadir.** Los de Inicio, Tareas, Mi día, el panel, Cerrar el día y la barra de menús entienden lo mismo que una tarea escrita a mano (fecha, hora, duración, repetición, prioridad, 🔕) y, mientras escribes, enseñan en etiquetas lo que van a guardar y en qué nota. En Mi día y en el panel, sin fecha en la frase, va al día que estás viendo.

## Órdenes rápidas (⌘K)

En el buscador, una frase corta que empieza por una palabra clave hace una acción. Antes de ejecutarla, la app enseña lo que va a hacer.

| Escribe | Hace |
|---|---|
| `peso 105,5` | Apunta el peso (también «ayer» o una fecha detrás). |
| `dormí 7,5` | Apunta las horas de sueño del día (también «ayer» o una fecha detrás). |
| `pinchazo hoy` | Apunta la toma del medicamento principal. |
| `tarea llamar al dentista el viernes` | Crea una tarea con fecha, prioridad o repetición. |
| `cita dentista el 29/10 a las 17:30` | Añade una cita a Salud, con hora si la dices. |
| `gasto 22 cena con Ana` | Apunta un gasto en la partida que adivina la app. |
| `compra leche y pan` | Añade a la lista de la compra. |
| `cintura 98` | Apunta una medida corporal. |
| `idea …`, `nota …` | Guarda una idea o añade a la nota de hoy. |
| `libro Dune - Frank Herbert` | Añade un libro pendiente a Lecturas (el autor es opcional). |
| `terminé Dune` | Termina hoy un libro que lees o tienes pendiente (basta parte del título). |
| `cuota Coche` | Apunta la cuota de un préstamo, en la nota y en Gastos. |

La **captura rápida** (⇧⌘N), en «Libre», entiende estas mismas órdenes sin abrir el buscador, y además un importe en euros como gasto («22 € cena con Ana», «gasolina 48 euros») y cualquier otra frase como tarea. Antes de guardar enseña lo que ha entendido y la nota donde irá. Ojo: como en ⌘K, «compra …» va a la lista de la compra; para una tarea que empieza así, usa la pestaña «Tarea». «Comprar …» con una fecha («comprar regalo el 15 de noviembre») sí es una tarea.

## Notas que crea la app

| Nota | Dónde | Qué guarda |
|---|---|---|
| Revisión semanal | `Revisiones/AAAA-Wnn.md` | Los hábitos de la semana, logros y objetivos. |
| Nota del día | `Diario/AAAA-MM-DD.md` | Las horas de sueño (`sueno_h:`) y lo que escribas. |
| Gastos del mes | `Finanzas/Gastos/AAAA-MM.md` | El presupuesto y los movimientos del mes. |
| Plantillas | `Plantillas/` | Las 10 de ejemplo, si las pides en el asistente o en «Nueva nota». |
| Lienzos | `Lienzos/Nombre.canvas` | Los lienzos nuevos (ver [Lienzos](#lienzos)). Los que ya tengas en otra carpeta también salen. |

Una plantilla puede hacer preguntas al crear la nota (`{{?Pregunta}}` o `{{?Pregunta|valor por defecto}}`) y sugerir carpeta con `plantilla_carpeta:` en el encabezado.

## Gráficas en una nota

Un bloque de código `grafica` dibuja una tabla de la misma nota. En Obsidian se sigue viendo como código.

````markdown
```grafica
tabla: Sueño
x: Fecha
y: Horas, Ánimo
tipo: linea
titulo: Cómo duermo
```
````

Todas las líneas son opcionales:

| Línea | Qué hace |
|---|---|
| `tipo` | `linea` (por defecto), `barras`, `area`, `puntos` o `tarta`. |
| `tabla` | Título de la sección donde está la tabla. Sin él, la primera tabla de la nota. |
| `x` | Columna del eje horizontal. Sin ella, la primera. Si son fechas (`01/10/2026` o `2026-10-01`), el eje es de tiempo y se ordena. |
| `y` | Columnas que se dibujan, separadas por comas. Sin ellas, todas las que tienen números (hasta 8). |
| `titulo` | Título encima de la gráfica. |

- La app entiende números como «7,5», «1.234,5» y unidades detrás («12,50 €», «7,5 h»), y muestra la unidad en la gráfica.
- En barras y tartas por categoría, las filas con la misma categoría se suman (por ejemplo, varios gastos de «Comida»).
- La tarta usa una sola columna y junta en «Otros» lo que pase de 7 porciones.
- Si falta la tabla o una columna, la nota lo dice en lugar de la gráfica.

## Lienzos

Un lienzo es una pizarra libre: tarjetas de texto, notas, enlaces y grupos donde quieras, unidos con flechas. Se guarda como archivo `.canvas` ([JSON Canvas](https://jsoncanvas.org), el formato abierto de Obsidian): los lienzos que hagas en Obsidian se abren aquí y al revés. La lista de la izquierda enseña todos los `.canvas` de tu carpeta; «+» crea uno nuevo en `Lienzos/`.

- **Añadir.** «Tarjeta» (o doble clic en el fondo) crea una tarjeta de texto; «Nota» pone una de tus notas, con su resumen; «Grupo» dibuja un marco (si hay algo elegido, lo rodea).
- **Mover y ver.** Arrastra un nodo para moverlo; un grupo se lleva lo que tiene dentro. Arrastra el fondo para desplazarte; pellizca en el trackpad o usa la lupa para el zoom; «Ajustar» enseña todo.
- **Unir.** Elige un nodo, pulsa «Unir» y luego el de destino (o clic derecho → «Unir desde aquí»).
- **Editar.** Doble clic en una tarjeta la edita (Markdown sencillo: `# título`, `**negrita**`, `- viñetas`, `- [ ] casillas`); en un grupo, cambia su nombre; en una nota, la abre. «Color» usa los seis colores de Obsidian. «Borrar» (o la tecla ⌫) quita el nodo y sus flechas.
- Cada cambio se guarda al momento y se deshace con ⌥⌘Z. Los datos que la app no conoce (de Obsidian o de un plugin) se conservan; al guardar, el archivo se reescribe con las claves ordenadas, sin cambiar lo que dice. Si el archivo no es JSON válido, la app lo dice y no lo toca.

## Calendar y avisos

Los avisos (citas, pagos, caducidades, cuotas, renovaciones, viajes…) se pueden recibir de tres formas en **Avisos → Cómo recibirlos**, y se pueden combinar:

- **Calendario «VOTsidian» (opcional).** Al activarlo, macOS pide permiso para usar Calendarios y la app crea un calendario propio con ese nombre, en la cuenta de tu calendario por defecto (normalmente iCloud, así sale también en el iPhone) o, si esa cuenta no lo permite, en tu Mac. Lo mantiene al día sola: lo crea al abrir la app y cuando cambian tus notas, actualiza lo que cambia y quita lo que ya no toca, sin duplicados. Solo lee y cambia ese calendario, nunca los demás. Un evento que cambies a mano se queda como lo dejaste hasta que cambie el aviso en la app; uno que borres a mano, la app lo vuelve a crear. Si apagas el interruptor, deja de sincronizar pero los eventos se quedan; «Borrar el calendario…» los quita todos.
- **Archivo `.ics`.** «Añadir a Calendar» importa los avisos una sola vez, sin permisos. Si vuelves a importar, Calendar actualiza en vez de duplicar.
- **Notificaciones de macOS.** Para los próximos 30 días, hasta 60 avisos.

La sincronización con Calendar y las notificaciones solo funcionan en la app empaquetada (`build-app.sh`), no con `swift run`. Lo que avisa cada módulo está en su sección de «Formato de cada nota».

Si algo no llega (Calendar no se actualiza, una copia falla, iCloud no baja un archivo), la app lo apunta en el registro del sistema. Ábrelo en Consola.app y filtra por el subsistema `com.votsidian.app`, o en Terminal: `log stream --predicate 'subsystem == "com.votsidian.app"' --level info`. Nunca se apunta el contenido de las notas, y las rutas salen ocultas salvo que macOS muestre los datos privados.

## Siri y Atajos

Con la app empaquetada (`build-app.sh`) y copiada en Aplicaciones, Siri entiende estas frases sin configurar nada. Si la abres desde otra carpeta (por ejemplo `build/`), Siri no puede abrirla y contesta que la función «está restringida». Todas llevan el nombre de la app; lo que falte, Siri lo pregunta.

| Di | Hace |
|---|---|
| «Añade una tarea en VOTsidian», «Nueva tarea en VOTsidian» | Pregunta la tarea y la guarda con lo que entienda: «llamar al taller el lunes a las 10». Siempre es una tarea, aunque empiece por «compra». |
| «Apunta en VOTsidian», «Anota en VOTsidian» | Como la captura rápida: «peso 101,2», «22 € cena con Ana», «compra leche y huevos», «dentista el viernes a las 17:30». Dice lo que ha hecho. |
| «Qué tengo hoy en VOTsidian», «Qué tengo el miércoles en VOTsidian» | Lee lo de ese día en la agenda (primero lo de todo el día, luego lo que tiene hora). Sin día, hoy, y entonces también cuántas tareas están vencidas. |
| «Avisos de VOTsidian» | Lee los cinco avisos más urgentes. |
| «Abre Gastos en VOTsidian» | Abre la app en esa pantalla (cualquiera de la barra lateral). |

Las mismas acciones están en la app Atajos, en la sección de VOTsidian, para usarlas en tus propios atajos: «Qué tengo» y «Avisos pendientes» devuelven el texto, por ejemplo para mandarlo en un mensaje. Siri escribe en las mismas notas que la app y cada cambio se deshace igual, con ⌥⌘Z. Con `swift run` no hay Siri: macOS solo ve las acciones de la app empaquetada.

## Copias y deshacer

- La app copia toda la carpeta antes del primer cambio de cada día y guarda las últimas 14 copias automáticas. Con la app abierta, la copia del día nuevo se hace sola a medianoche o al despertar el Mac. Se pueden cifrar con contraseña en Ajustes.
- Cada cambio hecho desde la app se deshace con ⌥⌘Z.
- Para recuperar una versión antigua de una nota: Notas → ⋯ → Historial.
- Para volver a una copia entera: Ajustes → Copias de seguridad. Antes de restaurar, la app guarda el estado actual.
- Para sacar tus datos: Ajustes → Exportar escribe un CSV por cada cosa que lleves (peso, medicación, gastos, vehículo, suscripciones, préstamos, viajes, lecturas…) y un resumen.
