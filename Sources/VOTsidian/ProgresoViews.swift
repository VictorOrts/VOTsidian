import Charts
import ImageIO
import SwiftUI

// MARK: - Medidas

struct MedidasCard: View {
    @Environment(Store.self) private var store
    @State private var metric = "Cintura"
    @State private var date = Date()
    @State private var inputs: [String: String] = [:]
    @State private var note = ""
    @State private var spec: RowSpec?

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: store.url(Measures.file).path)
        let (table, records) = Measures.parse(store.read(Measures.file))
        Card(title: "Medidas corporales", icon: "ruler") {
            if !exists {
                Text("Registra cintura, cadera, pecho, brazo, muslo y % de grasa una vez al mes para ver el cambio más allá del peso.").foregroundStyle(.secondary)
                Button("Activar seguimiento de medidas") { store.writeNote(Measures.file, text: Measures.template) }.buttonStyle(.borderedProminent)
            } else {
                latest(records)
                if records.filter({ $0.values[metric] != nil }).count > 1 { chart(records) }
                form(table)
                if !records.isEmpty {
                    DisclosureGroup("Historial (\(records.count))") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                            GridRow { Text("Fecha"); ForEach(Measures.fields, id: \.self) { Text($0) }; Text("") }.font(.caption).foregroundStyle(.secondary)
                            ForEach(records.reversed()) { r in
                                GridRow {
                                    Text(DayKey.dmy(r.date)).monospacedDigit()
                                    ForEach(Measures.fields, id: \.self) { Text(r.values[$0].map { fmt($0) } ?? "–").monospacedDigit() }
                                    EditButton { spec = RowSpec(file: Measures.file, mode: .edit(line: r.line), title: "medida") }
                                }
                            }
                        }.padding(.top, 6)
                    }
                }
            }
        }
        .sheet(item: $spec) { RowSheet(spec: $0) }
    }

    private func latest(_ records: [MeasureRecord]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
            ForEach(Measures.fields, id: \.self) { f in
                let series = records.filter { $0.values[f] != nil }
                let last = series.last?.values[f], prev = series.dropLast().last?.values[f]
                Button { metric = f } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(f.uppercased()).font(.caption2).foregroundStyle(.secondary)
                        Text(last.map { fmt($0, unit: " " + (Measures.units[f] ?? "")) } ?? "–").font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                        if let l = last, let p = prev { Text(fmtDelta(l - p, unit: " " + (Measures.units[f] ?? ""))).font(.caption).foregroundStyle(l < p ? Brand.accent : .secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(f == metric ? Brand.accent.opacity(0.15) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Brand.radius))
                }.buttonStyle(.plain)
            }
        }
    }

    private func chart(_ records: [MeasureRecord]) -> some View {
        let pts = records.compactMap { r in r.values[metric].map { (r.date, $0) } }
        return Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Día", p.0), y: .value(metric, p.1)).foregroundStyle(Brand.accent).interpolationMethod(.monotone)
                PointMark(x: .value("Día", p.0), y: .value(metric, p.1)).foregroundStyle(Brand.accent)
            }
        }
        .chartYScale(domain: ((pts.map(\.1).min() ?? 0) - 2)...((pts.map(\.1).max() ?? 0) + 2))
        .frame(height: 140)
    }

    private func form(_ table: NamedTable?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nueva medición").font(.subheadline.weight(.semibold))
            HStack {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden().frame(width: 120)
                ForEach(Measures.fields, id: \.self) { f in
                    TextField(f, text: Binding(get: { inputs[f] ?? "" }, set: { inputs[f] = $0 })).frame(width: 78)
                }
            }
            HStack {
                TextField("Notas", text: $note)
                Button("Guardar") { save(table) }.buttonStyle(.borderedProminent).disabled(inputs.values.allSatisfy { MD.number($0) == nil })
            }
        }
    }

    private func save(_ table: NamedTable?) {
        guard let t = table else { return }
        var cells = [String](repeating: "", count: t.header.count)
        cells[0] = DayKey.dmy(DayKey.calendar().startOfDay(for: date))
        for f in Measures.fields { if let i = t.col(f), let v = MD.number(inputs[f] ?? "") { cells[i] = MD.formatNumber(v) } }
        if let i = t.col("notas") { cells[i] = note }
        store.insertRow(file: Measures.file, afterLine: t.lastLine, cells: cells)
        inputs = [:]; note = ""
    }
}

// MARK: - Fotos de progreso

enum Thumbnail {
    static func load(_ url: URL, maxSize: Int) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxSize]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }.value
    }
}

struct ThumbView: View {
    let url: URL
    var size = 360
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(Color.primary.opacity(0.08)).overlay(ProgressView().controlSize(.small)) }
        }
        .task(id: url) { image = await Thumbnail.load(url, maxSize: size) }
    }
}

struct FotosCard: View {
    @Environment(Store.self) private var store
    @State private var date = Date()
    @State private var a = 0
    @State private var b = -1

    private var folder: URL { store.url("Cambio físico/Fotos") }

    private var photos: [(url: URL, date: Date?)] {
        _ = store.revision
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .map { ($0, DayKey.date(String($0.lastPathComponent.prefix(10)))) }
            .sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }
    }

    var body: some View {
        let list = photos
        Card(title: "Fotos de progreso", icon: "camera", info: "Se copian a Cambio físico/Fotos con la fecha en el nombre.") {
            HStack {
                DatePicker("Día", selection: $date, in: ...Date(), displayedComponents: .date).frame(width: 200)
                Button { add() } label: { Label("Añadir fotos…", systemImage: "plus") }
            }
            if list.isEmpty { Text("Todavía no hay fotos. Hazlas siempre con la misma luz, ropa y postura.").foregroundStyle(.secondary) }
            if list.count > 1 { compare(list) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(list, id: \.url) { p in
                    VStack(spacing: 3) {
                        ThumbView(url: p.url, size: 300).frame(width: 110, height: 140).clipShape(RoundedRectangle(cornerRadius: Brand.radius))
                            .onTapGesture { NSWorkspace.shared.open(p.url) }
                            .contextMenu {
                                Button("Abrir") { NSWorkspace.shared.open(p.url) }
                                Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([p.url]) }
                                Divider()
                                Button("Mover a la papelera", role: .destructive) { try? FileManager.default.trashItem(at: p.url, resultingItemURL: nil); store.reload() }
                            }
                        Text(p.date.map { DayKey.dmy($0) } ?? "–").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func compare(_ list: [(url: URL, date: Date?)]) -> some View {
        let ia = min(max(a, 0), list.count - 1)
        let ib = b < 0 ? list.count - 1 : min(b, list.count - 1)
        let labels = list.enumerated().map { i, p in p.date.map { DayKey.dmy($0) } ?? "foto \(i + 1)" }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Comparar").font(.subheadline.weight(.semibold))
            HStack(spacing: 14) {
                VStack(spacing: 4) {
                    ThumbView(url: list[ia].url, size: 700).frame(width: 220, height: 290).clipShape(RoundedRectangle(cornerRadius: Brand.radius))
                    ChoiceMenu(options: labels, current: labels[ia], width: 140) { v in a = labels.firstIndex(of: v) ?? 0 }
                }
                VStack(spacing: 4) {
                    ThumbView(url: list[ib].url, size: 700).frame(width: 220, height: 290).clipShape(RoundedRectangle(cornerRadius: Brand.radius))
                    ChoiceMenu(options: labels, current: labels[ib], width: 140) { v in b = labels.firstIndex(of: v) ?? list.count - 1 }
                }
                if let da = list[ia].date, let db = list[ib].date, let w = Optional(store.weight) {
                    let wa = w.records.last(where: { $0.date <= da })?.kg, wb = w.records.last(where: { $0.date <= db })?.kg
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(max(DayKey.days(from: da, to: db), 0)) días entre fotos").font(.callout)
                        if let wa, let wb { Text("Peso: \(fmt(wa)) → \(fmt(wb)) kg (\(fmtDelta(wb - wa)))").font(.callout).foregroundStyle(Brand.accent) }
                    }
                }
            }
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Elige las fotos de progreso"
        guard panel.runModal() == .OK else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let day = DayKey.string(DayKey.calendar().startOfDay(for: date))
        for u in panel.urls {
            let name = u.lastPathComponent
            let dest = folder.appendingPathComponent(name.hasPrefix(day) ? name : "\(day)-\(name)")
            if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: u, to: dest) }
        }
        store.reload()
    }
}
