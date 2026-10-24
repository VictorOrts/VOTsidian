import AppKit
import SwiftUI

/// Diferencias línea a línea entre dos textos, en orden de lectura.
enum LineDiff {
    enum Kind { case same, added, removed }
    struct Line: Identifiable { let id: Int; let kind: Kind; let text: String }

    /// `added`: está en `new` y no en `old`; `removed`: al revés.
    static func lines(from old: String, to new: String) -> [Line] {
        let a = MD.lines(old), b = MD.lines(new)
        let diff = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var out: [Line] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) { out.append(Line(id: out.count, kind: .removed, text: a[i])); i += 1 }
            else if j < b.count, inserted.contains(j) { out.append(Line(id: out.count, kind: .added, text: b[j])); j += 1 }
            else if j < b.count { out.append(Line(id: out.count, kind: .same, text: b[j])); i += 1; j += 1 }
            else { break }
        }
        return out
    }

    static func counts(_ lines: [Line]) -> (added: Int, removed: Int) {
        (lines.filter { $0.kind == .added }.count, lines.filter { $0.kind == .removed }.count)
    }
}

/// Versiones de una nota en las copias de seguridad, comparadas con la actual, con opción de restaurar una.
struct NoteHistorySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let path: String
    let onRestore: (String) -> Void
    @State private var versions: [Store.NoteVersion]?
    @State private var locked = 0
    @State private var selected: String?
    @State private var confirmRestore = false

    private var current: String { store.read(path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Historial de «\(((path as NSString).lastPathComponent as NSString).deletingPathExtension)»").font(.title3.bold())
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let versions {
                if versions.isEmpty {
                    ContentUnavailableView("Sin versiones anteriores", systemImage: "clock.arrow.circlepath",
                                           description: Text("Esta nota aún no está en ninguna copia de seguridad."))
                } else {
                    HSplitView {
                        List(versions, selection: $selected) { v in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(v.backup.label, systemImage: v.backup.encrypted ? "lock" : "clock")
                                Text(summary(v)).font(.caption).foregroundStyle(.secondary)
                            }.tag(v.id)
                        }
                        .frame(minWidth: 230, maxWidth: 300)
                        if let v = versions.first(where: { $0.id == selected }) { detail(v) }
                        else { Text("Elige una versión").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                }
                if locked > 0 {
                    Text("\(locked) \(locked == 1 ? "copia cifrada no se pudo abrir" : "copias cifradas no se pudieron abrir") con la contraseña actual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Buscando en las copias…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(width: 880, height: 600)
        .task { await load() }
    }

    private func load() async {
        let (rel, backups, password) = (path, store.backupEntries(), store.backupPassword)
        let r = await Task.detached(priority: .userInitiated) { Store.noteHistory(rel, in: backups, password: password) }.value
        versions = r.versions
        locked = r.locked
        selected = r.versions.first { $0.text != current }?.id ?? r.versions.first?.id
    }

    private func summary(_ v: Store.NoteVersion) -> String {
        guard v.text != current else { return "Igual que ahora" }
        let c = LineDiff.counts(LineDiff.lines(from: v.text, to: current))
        return "\(c.removed) líneas que ya no están · \(c.added) añadidas después"
    }

    private func detail(_ v: Store.NoteVersion) -> some View {
        let lines = LineDiff.lines(from: v.text, to: current)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Estaba en esta versión", systemImage: "minus").foregroundStyle(Brand.bad)
                Label("Añadido después", systemImage: "plus").foregroundStyle(Brand.accent)
                Spacer()
                Button("Copiar texto") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(v.text, forType: .string) }
                Button("Restaurar esta versión…") { confirmRestore = true }.disabled(v.text == current)
            }.font(.callout)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { l in
                        Text(l.text.isEmpty ? " " : l.text)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(l.kind == .removed ? Brand.bad.opacity(0.15) : l.kind == .added ? Brand.accent.opacity(0.15) : .clear)
                            .foregroundStyle(l.kind == .same ? .secondary : .primary)
                    }
                }.textSelection(.enabled)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: Brand.radius))
        }
        .padding(.leading, 8)
        .confirmationDialog("¿Restaurar la versión de \(v.backup.label.lowercased())?", isPresented: $confirmRestore) {
            Button("Restaurar") {
                if store.writeNote(path, text: v.text) { onRestore(v.text); dismiss() }
            }
        } message: { Text("La nota actual se sustituye. Se puede deshacer con ⌥⌘Z.") }
    }
}

/// Lista de copias de Ajustes: abrir en Finder o restaurar toda la carpeta.
struct BackupsList: View {
    @Environment(Store.self) private var store
    @State private var entries: [BackupEntry] = []
    @State private var restoring: BackupEntry?
    @State private var working = false
    @State private var result = ""
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(showAll ? entries : Array(entries.prefix(5))) { b in
                HStack {
                    Image(systemName: b.encrypted ? "lock.fill" : "folder").foregroundStyle(.secondary).frame(width: 18)
                    Text(b.label)
                    Spacer()
                    Button("Abrir") { NSWorkspace.shared.open(b.url) }
                        .help(b.encrypted ? "Finder pide la contraseña y monta la copia" : "Abre la carpeta en Finder")
                    Button("Restaurar…") { restoring = b }.disabled(working)
                }
            }
            if entries.count > 5 { Button(showAll ? "Ver menos" : "Ver las \(entries.count)") { showAll.toggle() }.buttonStyle(.accentLink) }
            if working { ProgressView("Restaurando…").controlSize(.small) }
            if !result.isEmpty { Text(result).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .task(id: store.backupsStamp) { entries = store.backupEntries() }
        .confirmationDialog("¿Restaurar la copia «\(restoring?.label ?? "")»?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restaurar", role: .destructive) {
                guard let b = restoring else { return }
                working = true
                result = ""
                Task {
                    result = await store.restoreBackup(b)
                    working = false
                    entries = store.backupEntries()
                }
            }
        } message: {
            Text("Las notas que estaban en la copia vuelven a su contenido de entonces. Las creadas después se conservan. Antes se guarda una copia «antes de restaurar» del estado actual, para poder volver atrás.")
        }
    }
}
