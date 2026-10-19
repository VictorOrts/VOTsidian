import AppKit
import Foundation

// Pasos de deshacer: cada cambio hecho desde la app se puede revertir.
extension Store {
    /// `quiet` es el autoguardado: no muestra aviso y junta varios guardados seguidos del mismo archivo en un solo paso de deshacer.
    func record(_ rel: String, previous: String?, written: String? = nil, quiet: Bool = false) {
        if quiet, let q = lastQuietWrite, q.rel == rel, Date().timeIntervalSince(q.at) < 120, case .write(let last, let first, _)? = undoStack.last, last == rel {
            lastQuietWrite = (rel, Date())
            undoStack[undoStack.count - 1] = .write(rel: rel, previous: first, written: written)
            return
        }
        push(.write(rel: rel, previous: previous, written: written))
        lastQuietWrite = quiet ? (rel, Date()) : nil
        if !quiet { lastChange = Change(file: rel, undoable: true) }
    }

    func push(_ step: UndoStep) {
        undoStack.append(step)
        if undoStack.count > 40 { undoStack.removeFirst() }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Deshace el último cambio hecho desde la app (restaura el archivo tal como estaba).
    func undo() {
        guard let last = undoStack.popLast() else { return }
        fileCache.removeAll()
        let fm = FileManager.default
        var failed: [String] = []
        func restore(_ rel: String, _ text: String) {
            do { try text.write(to: url(rel), atomically: true, encoding: .utf8) } catch { failed.append(rel) }
        }
        let label: String
        switch last {
        case let .write(rel, previous, written):
            label = rel
            // Si el archivo ya no es lo que escribió la app, otro programa (o iCloud) lo cambió después: no se pisa.
            if let written, let current = readOptional(rel), current != written {
                message = "«\(rel)» cambió fuera de la app después de ese cambio. No se deshizo para no perder lo nuevo."
                reload()
                return
            }
            if let previous { restore(rel, previous) }
            else { do { try fm.trashItem(at: url(rel), resultingItemURL: nil) } catch { failed.append(rel) } }
        case let .trash(rel, trashed, links):
            label = rel
            do {
                try fm.createDirectory(at: url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: trashed, to: url(rel))
            } catch { failed.append(rel) }
            for l in links { restore(l.rel, l.previous) }
        case let .rename(old, new, links):
            label = old
            do { try fm.moveItem(at: url(new), to: url(old)) } catch { failed.append(old) }
            for l in links { restore(l.rel, l.previous) }
            pinned = pinned.map { $0 == new ? old : $0 }
        }
        if failed.isEmpty { lastChange = Change(file: "Deshecho: " + label, undoable: false); message = nil }
        else { message = "No se pudo deshacer del todo: \(failed.joined(separator: ", "))." }
        reload()
    }
}
