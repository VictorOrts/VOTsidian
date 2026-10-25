import AppKit
import Foundation

/// Un rato de enfoque en una tarea: termina sola a la hora `end`.
struct FocusSession: Equatable {
    var title: String
    var start: Date
    var end: Date
    var minutes: Int { max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }
}

// Navegación: historial de pantallas y temporizador de enfoque.
extension Store {
    func syncHistoryFlags() {
        if canGoBack == backStack.isEmpty { canGoBack = !backStack.isEmpty }
        if canGoForward == forwardStack.isEmpty { canGoForward = !forwardStack.isEmpty }
    }

    /// Va a una pantalla de la barra lateral. La Agenda vuelve a su último modo (Día, Semana o Lista), o se queda si ya está en ella.
    func go(_ s: Screen) {
        guard s == .dia else { screen = s; return }
        if let cur = screen, Screen.agendaModes.contains(cur) { return }
        let last = Screen(rawValue: UserDefaults.standard.string(forKey: "agendaMode") ?? "")
        screen = last.flatMap { Screen.agendaModes.contains($0) ? $0 : nil } ?? .dia
    }

    /// Las pantallas de un módulo que se ha ocultado después se saltan.
    func goBack() {
        while let target = backStack.popLast() {
            guard isVisible(target), target != screen else { continue }
            if let cur = screen { forwardStack.append(cur) }
            walk(to: target)
            return
        }
        syncHistoryFlags()
    }

    func goForward() {
        while let target = forwardStack.popLast() {
            guard isVisible(target), target != screen else { continue }
            if let cur = screen { backStack.append(cur) }
            walk(to: target)
            return
        }
        syncHistoryFlags()
    }

    private func walk(to target: Screen) {
        walkingHistory = true
        screen = target
        walkingHistory = false
        syncHistoryFlags()
    }

    /// Empieza un bloque de enfoque de `minutes` minutos. Al acabar suena y lo dice arriba; uno nuevo sustituye al anterior.
    /// Los minutos se limitan a un día: un `⏱` disparatado en la nota no debe desbordar el temporizador.
    func startFocus(_ title: String, minutes: Int = 25, now: Date = Date()) {
        let session = FocusSession(title: title, start: now, end: now.addingTimeInterval(Double(min(max(1, minutes), 24 * 60)) * 60))
        focus = session
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, session.end.timeIntervalSince(Date()))))
            guard !Task.isCancelled, let self, self.focus == session else { return }
            self.focus = nil
            self.message = "Enfoque terminado: \(session.title) (\(session.minutes) min)."
            NSSound(named: "Glass")?.play()
        }
    }

    func stopFocus() {
        focusTask?.cancel()
        focusTask = nil
        focus = nil
    }
}
