import AppKit
import Foundation

// Pasos de deshacer: cada cambio hecho desde la app se puede revertir.
extension Store {
    /// `quiet` es el autoguardado: no muestra aviso y junta varios guardados seguidos del mismo archivo en un solo paso de deshacer.
    func record(_ rel: String, previous: String?, written: String? = nil, quiet: Bool = false) {
        if collectingUndo == nil, quiet, let q = lastQuietWrite, q.rel == rel, Date().timeIntervalSince(q.at) < 120, case .write(let last, let first, _)? = undoStack.last, last == rel {
            lastQuietWrite = (rel, Date())
            undoStack[undoStack.count - 1] = .write(rel: rel, previous: first, written: written)
            return
        }
        push(.write(rel: rel, previous: previous, written: written))
        lastQuietWrite = quiet ? (rel, Date()) : nil
        if !quiet { lastChange = Change(file: rel, undoable: true) }
    }

    func push(_ step: UndoStep) {
        if collectingUndo != nil { collectingUndo?.append(step); return }
        undoStack.append(step)
        if undoStack.count > 40 { undoStack.removeFirst() }
    }

    /// Junta en un solo paso de deshacer todo lo que `body` escriba (un cambio que toca varios archivos).
    func grouped(_ body: () -> Void) {
        let outer = collectingUndo
        collectingUndo = []
        body()
        let steps = collectingUndo ?? []
        collectingUndo = outer
        if steps.count == 1 { push(steps[0]) } else if !steps.isEmpty { push(.batch(steps)) }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Deshace el último cambio hecho desde la app (restaura el archivo tal como estaba).
    func undo() {
        guard let last = undoStack.popLast() else { return }
        // Si un archivo ya no es lo que escribió la app, otro programa (o iCloud) lo cambió después: no se pisa nada.
        if let rel = changedOutside(last) {
            message = "«\(rel)» cambió fuera de la app después de ese cambio. No se deshizo para no perder lo nuevo."
            reload()
            return
        }
        var failed: [String] = []
        var touched: [String] = []
        let label = revert(last, failed: &failed, touched: &touched)
        // Solo se vuelven a leer los archivos tocados; el resto sigue en la caché.
        for rel in touched { fileCache[rel] = nil }
        if failed.isEmpty { lastChange = Change(file: "Deshecho: " + label, undoable: false); message = nil }
        else { message = "No se pudo deshacer del todo: \(failed.joined(separator: ", "))." }
        reload()
    }

    /// Primer archivo escrito por `step` que ya no tiene lo que escribió la app.
    private func changedOutside(_ step: UndoStep) -> String? {
        switch step {
        case let .write(rel, _, written):
            if let written, let current = readOptional(rel), current != written { return rel }
            return nil
        case .batch(let steps):
            // Un archivo escrito varias veces en el mismo grupo (crear la nota del mes y apuntar en ella) solo tiene que
            // seguir como lo dejó la última escritura; comparar con las anteriores lo daba por cambiado fuera.
            func flat(_ s: UndoStep) -> [UndoStep] { if case .batch(let inner) = s { inner.flatMap(flat) } else { [s] } }
            var seen = Set<String>()
            for s in steps.flatMap(flat).reversed() {
                if case let .write(rel, _, _) = s, !seen.insert(rel).inserted { continue }
                if let rel = changedOutside(s) { return rel }
            }
            return nil
        case .trash, .rename: return nil
        }
    }

    /// Revierte `step` y devuelve su nombre para el aviso. Los pasos de un grupo se deshacen del último al primero.
    private func revert(_ step: UndoStep, failed: inout [String], touched: inout [String]) -> String {
        let fm = FileManager.default
        func restore(_ rel: String, _ text: String) -> String? {
            do { try text.write(to: url(rel), atomically: true, encoding: .utf8); return nil } catch { return rel }
        }
        switch step {
        case let .write(rel, previous, _):
            touched.append(rel)
            if let previous { if let f = restore(rel, previous) { failed.append(f) } }
            else { do { try fm.trashItem(at: url(rel), resultingItemURL: nil) } catch { failed.append(rel) } }
            return rel
        case let .trash(rel, trashed, links):
            touched.append(rel)
            do {
                try fm.createDirectory(at: url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: trashed, to: url(rel))
            } catch { failed.append(rel) }
            for l in links { touched.append(l.rel); if let f = restore(l.rel, l.previous) { failed.append(f) } }
            return rel
        case let .rename(old, new, links):
            touched += [old, new]
            do { try fm.moveItem(at: url(new), to: url(old)) } catch { failed.append(old) }
            for l in links { touched.append(l.rel); if let f = restore(l.rel, l.previous) { failed.append(f) } }
            pinned = pinned.map { $0 == new ? old : $0 }
            return old
        case .batch(let steps):
            var label = ""
            for s in steps.reversed() { label = revert(s, failed: &failed, touched: &touched) }
            return label
        }
    }
}
