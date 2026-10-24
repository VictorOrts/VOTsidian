import Foundation

/// Cuántas veces se calcula el cuerpo de cada pantalla. Solo en depuración: lo usa el test que mide qué se repinta con cada
/// cambio (`FluidezTests`). En la app compilada en release, `hit` no hace nada.
@MainActor
enum BodyCounter {
    static var counts: [String: Int] = [:]

    static func hit(_ name: String) {
        #if DEBUG
        counts[name, default: 0] += 1
        #endif
    }

    static func reset() { counts = [:] }
}
