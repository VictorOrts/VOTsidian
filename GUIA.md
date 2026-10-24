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
  - [Personas](#personas) · [Documentos](#documentos) · [Objetivos](#objetivos)
- [Tareas](#tareas) · [Órdenes rápidas](#órdenes-rápidas-k)
- [Notas que crea la app](#notas-que-crea-la-app)
- [Gráficas en una nota](#gráficas-en-una-nota)
- [Calendar y avisos](#calendar-y-avisos)
- [Copias y deshacer](#copias-y-deshacer)

## Empezar

1. Crea la app con `./scripts/build-app.sh` y ábrela (`build/VOTsidian.app`).
2. La primera vez sale **Empecemos**:
   - **Carpeta.** Por defecto, `iCloud Drive/VOTsidian`, para tenerla en todos tus dispositivos. Con «Elegir otra carpeta…» puedes usar una que ya tengas (por ejemplo, tu vault de Obsidian) o crear una nueva.
   - **Qué quieres llevar.** Marca los módulos que te interesan. Si eliges Mascota, escribe también su nombre. Los medicamentos se añaden después, en su pantalla.
3. Pulsa **Crear notas y empezar**. La app crea una nota por módulo, con el formato que sabe leer, y oculta los módulos que no marcaste.

Si la carpeta ya tiene notas, no se cambia ninguna: solo se crean las que faltan.

Siempre están **Tareas, Calendario, Planificar semana, Revisión semanal y mensual, Proyectos, Notas, Bases, Grafo, Enlaces rotos y Avisos**. Todo lo demás se cambia en **Ajustes → Módulos**: mostrar u ocultar módulos, crear la nota que falte o cambiar dónde está cada nota. Los módulos que lleguen en una actualización quedan ocultos en una carpeta ya configurada (la app avisa), salvo que ya tengas su nota: los activas cuando quieras.

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
| Documentos, Vehículo, Suscripciones, Préstamos, Viajes, Lecturas | cualquiera |

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
- **Lo periódico:** avisa dos días antes y cuando va tarde, con el botón «Me pinché hoy» o «Tomada hoy».
- **Cumplimiento:** el de lo diario sale como días completos de los últimos 30, sin contar hoy.

Una nota con una sola tabla `Fecha | Dosis | Zona | Notas` (y `nombre` y `cada_dias` en el encabezado) se lee como un único medicamento inyectable. Al añadir otro desde la app, la nota pasa sola al formato de dos tablas, y se puede deshacer.

### Salud y médicos

Tiene tres secciones:
- **`## Próximas citas`:** una tarea con fecha por cita, por ejemplo `- [ ] Dentista 📅 2026-11-02`.
- **`## Tratamientos`:** una lista con `- `.
- **`## Análisis`:** una tabla `Fecha | Prueba | Resultado | Notas`.

Las notas de cada visita se crean desde la pantalla, con «Nueva nota de visita». Los PDF o imágenes de análisis se copian a la carpeta `Análisis`; si ya hay un archivo con el mismo nombre que es otro distinto, el nuevo se numera («análisis 2.pdf») y nunca se pisa nada.

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

Desde ⌘K, `compra leche y pan` los añade. «Vaciar comprados» quita lo que ya está marcado.

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

Una tabla con una columna `Persona`, más `Relación`, `Cumpleaños` y `Última vez`. `Cumpleaños` admite `MM-DD` si no sabes el año.

### Documentos

- Cualquier tabla con una columna que contenga «caduca», por ejemplo `Documento | Número o referencia | Caduca / renueva | Notas`.
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

## Tareas

Una tarea es cualquier línea `- [ ] …` de cualquier nota. Las que apuntas desde la app van a `Organización/Inbox.md`. Las casillas de la lista de la compra y del equipaje de Viajes no cuentan como tareas. Se escriben igual que en el plugin Tasks de Obsidian:

| Escribe | Significa |
|---|---|
| `📅 2026-11-02` | Fecha límite |
| `⏳ 2026-11-01` | Fecha en que piensas hacerla |
| `🔁 every week` | Se repite (`every day`, `every 2 weeks`, `every month`, `every week when done`…) |
| `⏫`, `🔼`, `🔽` | Prioridad alta, media y baja |

En la captura rápida (⇧⌘N) puedes escribirlo en lenguaje natural: «llamar al dentista el viernes», «pagar el alquiler cada mes».

## Órdenes rápidas (⌘K)

En el buscador, una frase corta que empieza por una palabra clave hace una acción. Antes de ejecutarla, la app enseña lo que va a hacer.

| Escribe | Hace |
|---|---|
| `peso 105,5` | Apunta el peso (también «ayer» o una fecha detrás). |
| `ánimo 4`, `dormí 7,5` | Apunta el ánimo (1 a 5) o las horas de sueño del día. |
| `pinchazo hoy` | Apunta la toma del medicamento principal. |
| `tarea llamar al dentista el viernes` | Crea una tarea con fecha, prioridad o repetición. |
| `cita dentista el 29/10` | Añade una cita a Salud. |
| `gasto 22 cena con Ana` | Apunta un gasto en la partida que adivina la app. |
| `compra leche y pan` | Añade a la lista de la compra. |
| `cintura 98` | Apunta una medida corporal. |
| `idea …`, `nota …` | Guarda una idea o añade a la nota de hoy. |
| `libro Dune - Frank Herbert` | Añade un libro pendiente a Lecturas (el autor es opcional). |
| `terminé Dune` | Termina hoy un libro que lees o tienes pendiente (basta parte del título). |
| `cuota Coche` | Apunta la cuota de un préstamo, en la nota y en Gastos. |

## Notas que crea la app

| Nota | Dónde | Qué guarda |
|---|---|---|
| Revisión semanal | `Revisiones/AAAA-Wnn.md` | Los hábitos de la semana, logros y objetivos. |
| Nota del día | `Diario/AAAA-MM-DD.md` | El ánimo, el sueño y lo que escribas. |
| Gastos del mes | `Finanzas/Gastos/AAAA-MM.md` | El presupuesto y los movimientos del mes. |
| Plantillas | `Plantillas/` | Las 10 de ejemplo, si las pides en el asistente o en «Nueva nota». |

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

## Calendar y avisos

Los avisos (citas, pagos, caducidades, cuotas, renovaciones, viajes…) se pueden recibir de tres formas en **Avisos → Cómo recibirlos**, y se pueden combinar:

- **Calendario «VOTsidian» (opcional).** Al activarlo, macOS pide permiso para usar Calendarios y la app crea un calendario propio con ese nombre, en la cuenta de tu calendario por defecto (normalmente iCloud, así sale también en el iPhone) o, si esa cuenta no lo permite, en tu Mac. Lo mantiene al día sola: lo crea al abrir la app y cuando cambian tus notas, actualiza lo que cambia y quita lo que ya no toca, sin duplicados. Solo lee y cambia ese calendario, nunca los demás. Un evento que cambies a mano se queda como lo dejaste hasta que cambie el aviso en la app; uno que borres a mano, la app lo vuelve a crear. Si apagas el interruptor, deja de sincronizar pero los eventos se quedan; «Borrar el calendario…» los quita todos.
- **Archivo `.ics`.** «Añadir a Calendar» importa los avisos una sola vez, sin permisos. Si vuelves a importar, Calendar actualiza en vez de duplicar.
- **Notificaciones de macOS.** Para los próximos 30 días, hasta 60 avisos.

La sincronización con Calendar y las notificaciones solo funcionan en la app empaquetada (`build-app.sh`), no con `swift run`. Lo que avisa cada módulo está en su sección de «Formato de cada nota».

## Copias y deshacer

- La app copia toda la carpeta antes del primer cambio de cada día y guarda las últimas 14 copias automáticas. Se pueden cifrar con contraseña en Ajustes.
- Cada cambio hecho desde la app se deshace con ⌥⌘Z.
- Para recuperar una versión antigua de una nota: Notas → ⋯ → Historial.
- Para volver a una copia entera: Ajustes → Copias de seguridad. Antes de restaurar, la app guarda el estado actual.
- Para sacar tus datos: Ajustes → Exportar escribe un CSV por cada cosa que lleves (peso, medicación, gastos, vehículo, suscripciones, préstamos, viajes, lecturas…) y un resumen.
