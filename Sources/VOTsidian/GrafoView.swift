import SwiftUI

struct GraphNode: Identifiable {
    var id: Int
    var path: String
    var name: String
    var folder: String
    var degree: Int
    var folded: String
}

struct GrafoView: View {
    @Environment(Store.self) private var store
    @State private var nodes: [GraphNode] = []
    @State private var edges: [(Int, Int)] = []
    @State private var pos: [CGPoint] = []
    @State private var colors: [String: Color] = [:]
    @State private var size: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var hover: Int?
    @State private var dragging: Int?
    @State private var panning = false
    @State private var search = ""
    @State private var onlyConnected = false
    @State private var layoutGeneration = 0

    private let palette = Brand.series

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                Canvas { ctx, sz in draw(&ctx, sz) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): let h = node(at: p, in: geo.size); if h != hover { hover = h }
                        case .ended: if hover != nil { hover = nil }
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if dragging == nil && !panning {
                                if let n = node(at: v.startLocation, in: geo.size) { dragging = n } else { panning = true; baseOffset = offset }
                            }
                            if let d = dragging { pos[d] = unproject(v.location, in: geo.size) }
                            else if panning { offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height) }
                        }
                        .onEnded { v in
                            if let d = dragging, hypot(v.translation.width, v.translation.height) < 4 { store.pendingNote = nodes[d].path }
                            dragging = nil; panning = false
                        })
                    .gesture(MagnifyGesture()
                        .onChanged { scale = min(4, max(0.4, baseScale * $0.magnification)) }
                        .onEnded { _ in baseScale = scale })
                    .onAppear { size = geo.size }
                    .onChange(of: geo.size) { size = geo.size }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Buscar nota", text: $search).frame(width: 200)
                    Toggle("Solo con enlaces", isOn: $onlyConnected).toggleStyle(.checkbox)
                        .onChange(of: onlyConnected) { rebuild() }
                    Button { zoom(1.25) } label: { Image(systemName: "plus.magnifyingglass").accessibilityLabel("Acercar") }
                    Button { zoom(0.8) } label: { Image(systemName: "minus.magnifyingglass").accessibilityLabel("Alejar") }
                    Button("Ajustar") { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
                    Button("Reordenar") { rebuild() }
                }
                legend
            }
            .padding(14)

            if let h = hover ?? nil, nodes.indices.contains(h) { info(nodes[h]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(14) }
        }
        .navigationTitle("Grafo")
        .onAppear { if nodes.isEmpty { rebuild() } }
        .onChange(of: store.notes) { rebuild() }
        .onChange(of: store.outLinks) { rebuild() }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(colors.keys.sorted(), id: \.self) { f in
                HStack(spacing: 6) { Circle().fill(colors[f] ?? .gray).frame(width: 9, height: 9); Text(f).font(.caption) }
            }
        }
        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.radius))
    }

    private func info(_ n: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(n.name).font(.headline)
            Text(n.folder).font(.caption).foregroundStyle(.secondary)
            Text("\((store.outLinks[n.path] ?? []).count) enlaces salientes · \((store.backLinks[n.path] ?? []).count) entrantes").font(.caption)
            Text("Pulsa para abrir la nota").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Brand.radius))
    }

    // MARK: Datos

    private func rebuild() {
        let all = store.notes
        var indexOf: [String: Int] = [:]
        for (i, n) in all.enumerated() { indexOf[n.path] = i }
        var e: [(Int, Int)] = []
        for (src, targets) in store.outLinks {
            guard let a = indexOf[src] else { continue }
            for t in targets { if let b = indexOf[t] { e.append((a, b)) } }
        }
        var deg = [Int](repeating: 0, count: all.count)
        for (a, b) in e { deg[a] += 1; deg[b] += 1 }
        let keep = all.indices.filter { !onlyConnected || deg[$0] > 0 }
        var remap: [Int: Int] = [:]
        for (new, old) in keep.enumerated() { remap[old] = new }
        nodes = keep.map { i in
            let top = all[i].folder.split(separator: "/").first.map(String.init) ?? "Raíz"
            return GraphNode(id: remap[i]!, path: all[i].path, name: all[i].name, folder: top, degree: deg[i], folded: MD.fold(all[i].name))
        }
        edges = e.compactMap { a, b in remap[a].flatMap { na in remap[b].map { (na, $0) } } }
        let folders = Array(Set(nodes.map(\.folder))).sorted()
        colors = Dictionary(uniqueKeysWithValues: folders.filter { $0 != "Raíz" }.enumerated().map { ($1, palette[$0 % palette.count]) })
        if folders.contains("Raíz") { colors["Raíz"] = .gray }
        // La disposición es pesada con muchas notas: se calcula fuera del hilo principal y se pinta al terminar.
        layoutGeneration += 1
        let (gen, count, links) = (layoutGeneration, nodes.count, edges)
        if count <= 150 { pos = GraphLayout.compute(count: count, edges: links); return }
        Task.detached(priority: .userInitiated) {
            let result = GraphLayout.compute(count: count, edges: links)
            await MainActor.run { if gen == layoutGeneration { pos = result } }
        }
    }

    private func zoom(_ f: CGFloat) { scale = min(4, max(0.4, scale * f)); baseScale = scale }

    // MARK: Coordenadas

    private func project(_ p: CGPoint, in s: CGSize) -> CGPoint {
        CGPoint(x: (p.x - 0.5) * s.width * 0.9 * scale + s.width / 2 + offset.width,
                y: (p.y - 0.5) * s.height * 0.9 * scale + s.height / 2 + offset.height)
    }

    private func unproject(_ q: CGPoint, in s: CGSize) -> CGPoint {
        CGPoint(x: (q.x - s.width / 2 - offset.width) / (s.width * 0.9 * scale) + 0.5,
                y: (q.y - s.height / 2 - offset.height) / (s.height * 0.9 * scale) + 0.5)
    }

    private func radius(_ n: GraphNode) -> CGFloat { 5 + 2.2 * CGFloat(n.degree).squareRoot() }

    private func node(at q: CGPoint, in s: CGSize) -> Int? {
        var best: (Int, CGFloat)?
        for (i, n) in nodes.enumerated() where pos.indices.contains(i) {
            let p = project(pos[i], in: s)
            let d = hypot(p.x - q.x, p.y - q.y)
            if d <= radius(n) + 6, best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    // MARK: Dibujo

    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        guard pos.count == nodes.count else { return }
        let focus = hover ?? dragging
        let q = MD.fold(search)
        func matches(_ i: Int) -> Bool { q.isEmpty || nodes[i].folded.contains(q) }
        var neighbors = Set<Int>()
        if let f = focus { for (a, b) in edges { if a == f { neighbors.insert(b) } else if b == f { neighbors.insert(a) } } }

        // Aristas normales en un solo trazo; solo las del nodo enfocado se pintan aparte.
        var normal = Path(), hotPath = Path()
        for (a, b) in edges {
            if focus != nil && (a == focus || b == focus) {
                hotPath.move(to: project(pos[a], in: sz)); hotPath.addLine(to: project(pos[b], in: sz))
            } else {
                normal.move(to: project(pos[a], in: sz)); normal.addLine(to: project(pos[b], in: sz))
            }
        }
        ctx.stroke(normal, with: .color(Color.secondary.opacity(focus == nil ? 0.35 : 0.12)), lineWidth: 1)
        ctx.stroke(hotPath, with: .color(Brand.accent), lineWidth: 2)
        for (i, n) in nodes.enumerated() {
            let p = project(pos[i], in: sz)
            let r = radius(n)
            let dim = (focus != nil && i != focus && !neighbors.contains(i)) || !matches(i)
            let color = (colors[n.folder] ?? .gray).opacity(dim ? 0.22 : 1)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
            if i == focus { ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r - 3, y: p.y - r - 3, width: r * 2 + 6, height: r * 2 + 6)), with: .color(.primary), lineWidth: 1.5) }
            if !dim && (scale > 0.7 || i == focus || neighbors.contains(i)) {
                let label = Text(n.name).font(.system(size: 11, weight: i == focus ? .bold : .regular))
                    .foregroundColor(dim ? .secondary.opacity(0.5) : .primary)
                ctx.draw(label, at: CGPoint(x: p.x, y: p.y + r + 9), anchor: .center)
            }
        }
    }
}
