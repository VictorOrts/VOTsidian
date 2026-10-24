import SwiftUI
import AppKit

/// Lienzo libre (archivos `.canvas`): tarjetas, notas, enlaces y grupos colocados a mano y unidos con flechas.
/// Arrastrar un nodo lo mueve (un grupo, con lo que tiene dentro); arrastrar el fondo desplaza; pellizcar o los botones, zoom.
/// Doble clic en el fondo crea una tarjeta; en una tarjeta, la edita; en una nota, la abre.
struct LienzoView: View {
    @Environment(Store.self) private var store
    /// Lienzo abierto. Se recuerda.
    @AppStorage("lienzoActual") private var current = ""
    @State private var files: [String] = []
    @State private var doc = CanvasDoc()
    @State private var broken = false
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat?
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize?
    @State private var viewSize: CGSize = .zero
    @State private var fitted = ""
    @State private var selected: String?
    /// Nodos que se están arrastrando y cuánto, en coordenadas del lienzo. Se escribe al soltar.
    @State private var drag: (ids: Set<String>, by: CGSize)?
    /// Con «Unir», el nodo de origen: el siguiente clic en otro nodo crea la flecha.
    @State private var linkingFrom: String?
    @State private var editing: CanvasNode?
    @State private var draft = ""
    @State private var pickingNote = false
    @State private var naming = false
    @State private var newName = ""
    @FocusState private var boardFocused: Bool

    var body: some View {
        let _ = BodyCounter.hit("LienzoView")
        HStack(spacing: 0) {
            fileList.frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                toolbar.padding(.horizontal, 14).padding(.vertical, 8)
                Divider()
                if current.isEmpty { emptyState } else if broken { brokenState } else { board }
            }
        }
        .navigationTitle(current.isEmpty ? "Lienzo" : ((current as NSString).lastPathComponent as NSString).deletingPathExtension)
        .task(id: store.canvasStamp) {
            files = store.canvasFiles()
            if !files.contains(current) { current = files.first ?? "" }
            load()
        }
        .onChange(of: current) { selected = nil; linkingFrom = nil; fitted = ""; load() }
        .sheet(item: $editing) { n in editor(n) }
        .sheet(isPresented: $pickingNote) { NotePickerSheet { add(file: $0) } }
        .alert("Nuevo lienzo", isPresented: $naming) {
            TextField("Nombre", text: $newName)
            Button("Crear") { if let rel = store.createCanvas(named: newName) { current = rel } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Se guarda en la carpeta Lienzos como archivo .canvas, que Obsidian también abre.") }
    }

    // MARK: Lista de lienzos

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Lienzos").font(.headline)
                Spacer()
                Button { newName = ""; naming = true } label: { Image(systemName: "plus").accessibilityLabel("Nuevo lienzo") }
                    .buttonStyle(.borderless).help("Nuevo lienzo")
            }.padding(12)
            List(files, id: \.self, selection: Binding(get: { current.isEmpty ? nil : current }, set: { if let v = $0 { current = v } })) { f in
                VStack(alignment: .leading, spacing: 1) {
                    Text(((f as NSString).lastPathComponent as NSString).deletingPathExtension).lineLimit(1)
                    Text((f as NSString).deletingLastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Todavía no hay lienzos").font(.headline)
            Text("Un lienzo es una pizarra libre: tarjetas, notas y flechas donde quieras. Se guarda como .canvas, compatible con Obsidian.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            Button("Crear un lienzo") { newName = ""; naming = true }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var brokenState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(Brand.warn)
            Text("Este lienzo no se puede leer").font(.headline)
            Text("El archivo no es JSON válido: puede que se esté sincronizando o que se haya editado a mano. No se toca hasta que se arregle.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(current)]) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Barra

    private var toolbar: some View {
        let sel = doc.nodes.first { $0.id == selected }
        return HStack(spacing: 8) {
            Button { addText(at: center) } label: { Label("Tarjeta", systemImage: "note.text") }.help("Tarjeta de texto (o doble clic en el fondo)")
            Button { pickingNote = true } label: { Label("Nota", systemImage: "doc.text") }.help("Poner una nota en el lienzo")
            Button { addGroup() } label: { Label("Grupo", systemImage: "rectangle.dashed") }.help("Marco para agrupar: al moverlo se mueve lo que tiene dentro")
            Divider().frame(height: 18)
            Button { linkingFrom = linkingFrom == nil ? selected : nil } label: { Label("Unir", systemImage: "arrow.right") }
                .disabled(sel == nil)
                .background(linkingFrom != nil ? Brand.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .help("Elige un nodo, pulsa Unir y luego el nodo de destino")
            Menu {
                Button("Sin color") { setColor("") }
                ForEach(Array(["Rojo", "Naranja", "Amarillo", "Verde", "Cian", "Morado"].enumerated()), id: \.offset) { i, name in
                    Button(name) { setColor("\(i + 1)") }
                }
            } label: { Label("Color", systemImage: "paintpalette") }
                .fixedSize().disabled(sel == nil)
            Button(role: .destructive) { deleteSelected() } label: { Label("Borrar", systemImage: "trash") }.disabled(sel == nil)
            if linkingFrom != nil { Text("Pulsa el nodo de destino…").font(.caption).foregroundStyle(Brand.accent) }
            Spacer()
            Button { zoom(by: 1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass").accessibilityLabel("Alejar") }
            Text("\(Int((scale * 100).rounded())) %").font(.caption).monospacedDigit().frame(width: 44)
            Button { zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass").accessibilityLabel("Acercar") }
            Button("Ajustar") { fit() }.help("Que se vea todo el lienzo")
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .disabled(current.isEmpty || broken)
    }

    // MARK: Pizarra

    private var board: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in drawGrid(&ctx, size) }
                Canvas { ctx, _ in drawEdges(&ctx) }.allowsHitTesting(false)
                ZStack(alignment: .topLeading) {
                    ForEach(doc.nodes.filter { $0.type == "group" } + doc.nodes.filter { $0.type != "group" }) { n in
                        let d = drag.map { $0.ids.contains(n.id) ? $0.by : .zero } ?? .zero
                        nodeView(n)
                            .frame(width: n.width, height: n.height)
                            .offset(x: n.x + d.width, y: n.y + d.height)
                    }
                }
                .frame(width: 1, height: 1, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(offset)
                if doc.nodes.isEmpty {
                    Text("Doble clic para crear una tarjeta").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .coordinateSpace(.named("lienzo"))
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { v in
                    let base = baseOffset ?? offset
                    baseOffset = base
                    offset = CGSize(width: base.width + v.translation.width, height: base.height + v.translation.height)
                }
                .onEnded { _ in baseOffset = nil })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { v in
                    let base = baseScale ?? scale
                    baseScale = base
                    setScale(base * v.magnification, around: v.startLocation)
                }
                .onEnded { _ in baseScale = nil })
            .onTapGesture(count: 2) { p in addText(at: world(p)) }
            .onTapGesture { selected = nil; linkingFrom = nil; boardFocused = true }
            .focusable()
            .focusEffectDisabled()
            .focused($boardFocused)
            .onDeleteCommand { deleteSelected() }
            .onAppear { viewSize = geo.size; if fitted != current { fit() } }
            .onChange(of: geo.size) { viewSize = geo.size; if fitted != current { fit() } }
        }
        .background(Color.primary.opacity(0.025))
    }

    @ViewBuilder private func nodeView(_ n: CanvasNode) -> some View {
        let tint = JSONCanvas.color(n.color)
        let isSel = selected == n.id || linkingFrom == n.id
        Group {
            if n.type == "group" {
                RoundedRectangle(cornerRadius: 14).fill((tint ?? .secondary).opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSel ? Brand.accent : (tint ?? .secondary).opacity(0.5), lineWidth: isSel ? 2.5 : 1.5))
                    .overlay(alignment: .topLeading) {
                        Text(n.label.isEmpty ? "Grupo" : n.label).font(.title3.weight(.semibold)).foregroundStyle(tint ?? .secondary)
                            .fixedSize().offset(x: 4, y: -30)
                    }
            } else {
                card(n).padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .background((tint ?? .clear).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).fill((tint ?? .clear).opacity(0.08)).allowsHitTesting(false))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSel ? Brand.accent : (tint ?? Color.primary.opacity(0.18)), lineWidth: isSel ? 2.5 : 1.2))
                    .shadow(color: .black.opacity(0.07), radius: 5, y: 2)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("lienzo"))
            .onChanged { v in
                if drag == nil { drag = (doc.moving(n.id), .zero); selected = n.id }
                drag?.by = CGSize(width: v.translation.width / scale, height: v.translation.height / scale)
            }
            .onEnded { _ in commitDrag() })
        .onTapGesture(count: 2) { open(n) }
        .onTapGesture { tap(n) }
        .contextMenu {
            Button("Unir desde aquí") { selected = n.id; linkingFrom = n.id }
            if n.type == "text" || n.type == "group" { Button(n.type == "group" ? "Cambiar nombre" : "Editar") { open(n) } }
            if n.type == "file" { Button("Abrir la nota") { open(n) } }
            Divider()
            Button("Borrar", role: .destructive) { selected = n.id; deleteSelected() }
        }
        .help(n.type == "file" ? n.file : n.type == "link" ? n.url : "")
    }

    @ViewBuilder private func card(_ n: CanvasNode) -> some View {
        switch n.type {
        case "file":
            let ext = (n.file as NSString).pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext), let img = NSImage(contentsOf: store.url(n.file)) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(((n.file as NSString).lastPathComponent as NSString).deletingPathExtension, systemImage: "doc.text")
                        .font(.headline).foregroundStyle(Brand.accent).lineLimit(2)
                    if let s = store.snippets[n.file], !s.isEmpty { Text(s).font(.callout).foregroundStyle(.secondary) }
                    else if !store.exists(n.file) { Text("La nota ya no está en la carpeta.").font(.caption).foregroundStyle(Brand.warn) }
                }
            }
        case "link":
            VStack(alignment: .leading, spacing: 4) {
                Label(URL(string: n.url)?.host() ?? n.url, systemImage: "link").font(.headline).lineLimit(1)
                Text(n.url).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                if n.text.isEmpty { Text("Tarjeta vacía").foregroundStyle(.tertiary) }
                ForEach(Array(n.text.components(separatedBy: "\n").prefix(60).enumerated()), id: \.offset) { _, line in markdownLine(line) }
            }
        }
    }

    /// Markdown sencillo de una línea de tarjeta: encabezados, viñetas, casillas y formato en línea.
    @ViewBuilder private func markdownLine(_ line: String) -> some View {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") {
            let level = t.prefix { $0 == "#" }.count
            Text(MDParser.inline(String(t.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
                .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
        } else if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") {
            Label { Text(MDParser.inline(String(t.dropFirst(6)))) } icon: { Image(systemName: t.hasPrefix("- [x]") ? "checkmark.square" : "square") }
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            Text("•  ") + Text(MDParser.inline(String(t.dropFirst(2))))
        } else if t.isEmpty {
            Spacer().frame(height: 4)
        } else {
            Text(MDParser.inline(line))
        }
    }

    // MARK: Dibujo

    private func drawGrid(_ ctx: inout GraphicsContext, _ size: CGSize) {
        var step = 24 * scale
        while step < 12 { step *= 2 }
        let ox = offset.width.truncatingRemainder(dividingBy: step), oy = offset.height.truncatingRemainder(dividingBy: step)
        var dots = Path()
        var x = ox
        while x < size.width {
            var y = oy
            while y < size.height { dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)); y += step }
            x += step
        }
        ctx.fill(dots, with: .color(.primary.opacity(0.12)))
    }

    private func drawEdges(_ ctx: inout GraphicsContext) {
        let frames = Dictionary(doc.nodes.map { ($0.id, screenRect($0)) }, uniquingKeysWith: { a, _ in a })
        for e in doc.edges {
            guard let a = frames[e.fromNode], let b = frames[e.toNode] else { continue }
            let (sa, sb) = JSONCanvas.sides(e, from: a, to: b)
            let p0 = JSONCanvas.anchor(a, side: sa), p3 = JSONCanvas.anchor(b, side: sb)
            let reach = max(30 * scale, hypot(p3.x - p0.x, p3.y - p0.y) * 0.35)
            let n0 = JSONCanvas.normal(sa), n3 = JSONCanvas.normal(sb)
            let c1 = CGPoint(x: p0.x + n0.dx * reach, y: p0.y + n0.dy * reach)
            let c2 = CGPoint(x: p3.x + n3.dx * reach, y: p3.y + n3.dy * reach)
            var path = Path()
            path.move(to: p0)
            path.addCurve(to: p3, control1: c1, control2: c2)
            let color = JSONCanvas.color(e.color) ?? Color.secondary
            let width = max(1.2, 2 * min(scale, 1.5))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            if e.toArrow { ctx.fill(arrow(at: p3, from: c2, size: 10 * max(scale, 0.6)), with: .color(color)) }
            if e.fromArrow { ctx.fill(arrow(at: p0, from: c1, size: 10 * max(scale, 0.6)), with: .color(color)) }
            if !e.label.isEmpty {
                let m = bezier(0.5, p0, c1, c2, p3)
                let text = ctx.resolve(Text(e.label).font(.caption).foregroundStyle(.secondary))
                let s = text.measure(in: CGSize(width: 220, height: 60))
                ctx.fill(Path(roundedRect: CGRect(x: m.x - s.width / 2 - 5, y: m.y - s.height / 2 - 2, width: s.width + 10, height: s.height + 4), cornerRadius: 4),
                         with: .color(Color(nsColor: .windowBackgroundColor)))
                ctx.draw(text, at: m)
            }
        }
    }

    private func arrow(at tip: CGPoint, from control: CGPoint, size: CGFloat) -> Path {
        var angle = atan2(tip.y - control.y, tip.x - control.x)
        if tip == control { angle = 0 }
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - size * cos(angle - 0.45), y: tip.y - size * sin(angle - 0.45)))
        p.addLine(to: CGPoint(x: tip.x - size * cos(angle + 0.45), y: tip.y - size * sin(angle + 0.45)))
        p.closeSubpath()
        return p
    }

    private func bezier(_ t: CGFloat, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
                       y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y)
    }

    // MARK: Coordenadas

    private func screenRect(_ n: CanvasNode) -> CGRect {
        let d = drag.map { $0.ids.contains(n.id) ? $0.by : .zero } ?? .zero
        return CGRect(x: (n.x + d.width) * scale + offset.width, y: (n.y + d.height) * scale + offset.height,
                      width: n.width * scale, height: n.height * scale)
    }

    private func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale) }

    private var center: CGPoint { world(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)) }

    private func setScale(_ s: CGFloat, around p: CGPoint) {
        let w = world(p)
        scale = min(max(s, 0.1), 3)
        offset = CGSize(width: p.x - w.x * scale, height: p.y - w.y * scale)
    }

    private func zoom(by f: CGFloat) { setScale(scale * f, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)) }

    /// Encaja todo el lienzo en la vista. Hasta que la vista tiene tamaño no se da por encajado: al abrir, se vuelve a intentar.
    private func fit() {
        guard viewSize.width > 240, viewSize.height > 200 else { return }
        fitted = current
        guard let b = doc.bounds else { scale = 1; offset = CGSize(width: viewSize.width / 2, height: viewSize.height / 2); return }
        let pad: CGFloat = 70
        scale = min(max(min((viewSize.width - 2 * pad) / max(b.width, 1), (viewSize.height - 2 * pad) / max(b.height, 1)), 0.1), 1.2)
        offset = CGSize(width: (viewSize.width - b.width * scale) / 2 - b.minX * scale, height: (viewSize.height - b.height * scale) / 2 - b.minY * scale)
    }

    // MARK: Acciones

    private func load() {
        guard !current.isEmpty, let text = store.readOptional(current) else { doc = CanvasDoc(); broken = false; return }
        if let d = JSONCanvas.parse(text) { doc = d; broken = false } else { broken = true }
        if fitted != current { fit() }
    }

    private func change(_ transform: (String) -> String?) {
        guard !current.isEmpty else { return }
        store.edit(current, transform)
        load()
    }

    private func tap(_ n: CanvasNode) {
        if let from = linkingFrom, from != n.id {
            let id = JSONCanvas.newID()
            change { JSONCanvas.connect($0, id: id, from: from, to: n.id) }
            linkingFrom = nil
        }
        selected = n.id
        boardFocused = true
    }

    private func open(_ n: CanvasNode) {
        switch n.type {
        case "file": store.pendingNote = n.file
        case "link": if let u = URL(string: n.url) { NSWorkspace.shared.open(u) }
        default: draft = n.type == "group" ? n.label : n.text; editing = n
        }
    }

    private func commitDrag() {
        guard let d = drag else { return }
        drag = nil
        guard abs(d.by.width) > 0.5 || abs(d.by.height) > 0.5 else { return }
        var to: [String: CGPoint] = [:]
        for n in doc.nodes where d.ids.contains(n.id) { to[n.id] = CGPoint(x: n.x + d.by.width, y: n.y + d.by.height) }
        // Se pinta ya en su sitio; el archivo se escribe a la vez.
        for i in doc.nodes.indices { if let p = to[doc.nodes[i].id] { doc.nodes[i].x = p.x; doc.nodes[i].y = p.y } }
        change { JSONCanvas.moveNodes($0, to: to) }
    }

    private func addText(at p: CGPoint) {
        let id = JSONCanvas.newID()
        change { JSONCanvas.addNode($0, id: id, type: "text", frame: CGRect(x: p.x - 125, y: p.y - 40, width: 250, height: 80), fields: ["text": ""]) }
        selected = id
        if let n = doc.nodes.first(where: { $0.id == id }) { draft = ""; editing = n }
    }

    private func add(file: String) {
        let id = JSONCanvas.newID(), p = center
        change { JSONCanvas.addNode($0, id: id, type: "file", frame: CGRect(x: p.x - 150, y: p.y - 60, width: 300, height: 120), fields: ["file": file]) }
        selected = id
    }

    private func addGroup() {
        let id = JSONCanvas.newID()
        // Si hay un nodo elegido, el grupo lo rodea; si no, va en el centro.
        let around = doc.nodes.first { $0.id == selected }?.frame.insetBy(dx: -40, dy: -40)
        let frame = around ?? CGRect(x: center.x - 200, y: center.y - 150, width: 400, height: 300)
        change { JSONCanvas.addNode($0, id: id, type: "group", frame: frame, fields: ["label": "Grupo"]) }
        selected = id
    }

    private func setColor(_ c: String) {
        guard let id = selected else { return }
        change { JSONCanvas.setColor($0, id: id, to: c) }
    }

    private func deleteSelected() {
        guard let id = selected else { return }
        change { JSONCanvas.remove($0, ids: [id]) }
        selected = nil; linkingFrom = nil
    }

    private func editor(_ n: CanvasNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(n.type == "group" ? "Nombre del grupo" : "Tarjeta").font(.headline)
            if n.type == "group" {
                TextField("Nombre", text: $draft).onSubmit { saveEdit(n) }
            } else {
                TextEditor(text: $draft).font(.body).frame(minHeight: 180)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Brand.radius))
                Text("Markdown: # título, **negrita**, *cursiva*, - viñetas, - [ ] casillas.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { editing = nil }.keyboardShortcut(.cancelAction)
                Button("Guardar") { saveEdit(n) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 460)
    }

    private func saveEdit(_ n: CanvasNode) {
        let key = n.type == "group" ? "label" : "text", value = draft
        editing = nil
        if value != (n.type == "group" ? n.label : n.text) { change { JSONCanvas.setField($0, id: n.id, key: key, to: value) } }
    }
}

/// Elegir una nota para ponerla en el lienzo.
private struct NotePickerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pick: (String) -> Void
    @State private var query = ""

    var body: some View {
        let q = MD.fold(query)
        let list = store.notes.filter { q.isEmpty || MD.fold($0.path).contains(q) }.prefix(80)
        VStack(alignment: .leading, spacing: 10) {
            Text("Poner una nota en el lienzo").font(.headline)
            TextField("Buscar nota", text: $query)
            List(Array(list)) { n in
                Button { pick(n.path); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.name)
                        Text(n.folder).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .frame(height: 320)
            HStack { Spacer(); Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 440)
    }
}
