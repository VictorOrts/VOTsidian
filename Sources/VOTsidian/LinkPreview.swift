import SwiftUI

enum LinkContext {
    /// Primera línea del cuerpo (sin cabecera) que enlaza a `name` con `[[name]]`, `[[name#…]]` o `[[name|…]]`, limpia de marcas de lista y enlaces.
    static func line(in text: String, linkingTo name: String) -> String? {
        let key = MD.fold(name)
        var lines = MD.lines(text)
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { lines.removeSubrange(0...end) }
        let fence = MD.fenced(lines)
        for (i, raw) in lines.enumerated() where !fence.contains(i) && raw.contains("[[") {
            let hit = raw.matches(of: /\[\[([^\]]+)\]\]/).contains { m in
                let target = String(m.1).split(whereSeparator: { "#|\\".contains($0) }).first.map(String.init) ?? ""
                return MD.fold((target as NSString).lastPathComponent.trimmingCharacters(in: .whitespaces)) == key
            }
            if hit { return clean(raw) }
        }
        return nil
    }

    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        s = s.replacing(/^(?:#{1,6}\s+|>\s*|(?:[-*]|\d+\.)\s+(?:\[[ xX]\]\s+)?)/, with: "")
        s = s.replacing(/!?\[\[([^\]|]*)(?:\\?\|([^\]]*))?\]\]/) { m in m.2.map(String.init) ?? String(m.1) }
        return s
    }
}

/// Contenido de una nota resumido para ver al pasar el ratón por un enlace.
struct NotePreview: View {
    @Environment(Store.self) private var store
    let path: String

    var body: some View {
        let text = Embed.body(of: store.noteTexts[path] ?? store.read(path), heading: nil)
        VStack(alignment: .leading, spacing: 8) {
            Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension).font(.headline)
            if text.isEmpty { EmptyNote("Nota vacía.", icon: "doc") }
            else {
                NoteBody(text: String(text.prefix(900)), actions: NoteActions(toggle: { _, _ in }, editRow: { _ in }, addRow: { _ in }, setProperty: { _, _ in }), depth: 2)
                    .frame(maxHeight: 240, alignment: .top).clipped()
            }
        }
        .padding(14).frame(width: 380, alignment: .leading)
    }
}

extension View {
    /// Muestra una vista previa de la nota tras un instante con el ratón encima.
    func notePreview(_ path: String) -> some View { modifier(HoverPreview(path: path)) }
}

private struct HoverPreview: ViewModifier {
    let path: String
    @State private var show = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                pending?.cancel()
                if inside {
                    pending = Task { try? await Task.sleep(for: .milliseconds(600)); if !Task.isCancelled { show = true } }
                } else { show = false }
            }
            .popover(isPresented: $show, arrowEdge: .bottom) { NotePreview(path: path) }
    }
}
