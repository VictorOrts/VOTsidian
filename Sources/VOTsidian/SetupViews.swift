import AppKit
import SwiftUI

// MARK: - Nota de un módulo que aún no existe

/// Arriba de la pantalla de un módulo cuya nota no existe: dice dónde irá y deja crearla ya o cambiar la ruta.
struct MissingNoteBanner: View {
    @Environment(Store.self) private var store
    let module: Module

    var body: some View {
        let missing = store.missingFiles(module)
        if !missing.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.badge.plus").font(.title3).foregroundStyle(Brand.info)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Esta pantalla guarda sus datos en \(missing.map { "«\($0)»" }.joined(separator: " y ")), que aún no existe.").fontWeight(.medium)
                    Text("Se crea sola al apuntar lo primero, o créala ya para rellenarla a mano. Si tus notas están en otro sitio, cambia la ruta en Ajustes → Módulos.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Crear la nota") { store.createStarterNotes([module]) }.buttonStyle(.borderedProminent)
                        Button("Cambiar la ruta…") { store.screen = .ajustes }
                    }.controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Brand.info.opacity(0.1), in: RoundedRectangle(cornerRadius: Brand.radius))
        }
    }
}

// MARK: - Asistente del principio

/// Primera vez con una carpeta vacía o sin ninguna nota de los módulos: elegir carpeta y qué se quiere llevar.
struct WelcomeView: View {
    @Environment(Store.self) private var store
    @State private var chosen = Module.suggested
    @State private var pet = ""
    @State private var medication = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Empecemos").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("VOTsidian guarda todo en notas Markdown dentro de una carpeta: puedes abrirlas también con Obsidian o con cualquier editor. Elige la carpeta y lo que quieres llevar, y la app crea las notas con el formato que sabe leer.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Card(title: "Carpeta", icon: "folder") {
                    Text(store.root.path).font(.callout.monospaced()).textSelection(.enabled)
                    Text(store.notes.isEmpty
                         ? "Está vacía o aún no existe: se creará."
                         : "Ya tiene \(plural(store.notes.count, "nota", "notas")). No se cambia ninguna: solo se crean las que falten.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Elegir otra carpeta…") { store.chooseFolder() }
                }
                Card(title: "Qué quieres llevar", icon: "square.grid.2x2",
                     info: "Tareas, calendario, revisiones, proyectos y notas van siempre. Se cambia cuando quieras en Ajustes → Módulos.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                        ForEach(Module.allCases) { tile($0) }
                    }
                    if chosen.contains(.mascota) || chosen.contains(.medicacion) {
                        HStack(spacing: 16) {
                            if chosen.contains(.mascota) { TextField("Nombre de tu mascota", text: $pet).frame(width: 240) }
                            if chosen.contains(.medicacion) { TextField("Medicamento (p. ej. Ozempic)", text: $medication).frame(width: 240) }
                        }
                    }
                }
                HStack {
                    Text("\(plural(chosen.count, "módulo", "módulos")) · \(plural(store.notes.isEmpty ? chosen.count + 1 : chosen.reduce(0) { $0 + store.missingFiles($1).count }, "nota nueva", "notas nuevas"))")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Crear notas y empezar") {
                        store.setUp(modules: chosen, petName: pet, medication: medication)
                        store.screen = .inicio
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .task(id: store.root) {
            // Si la carpeta ya tiene notas de algún módulo, ese módulo sale marcado.
            chosen = Module.suggested.union(Module.allCases.filter { $0.files.contains { store.exists(VaultPath.path($0)) } })
        }
    }

    private func tile(_ m: Module) -> some View {
        let on = chosen.contains(m)
        return Button {
            if on { chosen.remove(m) } else { chosen.insert(m) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? Brand.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Label(m.title, systemImage: m.icon).fontWeight(.semibold)
                    Text(m.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Brand.accent.opacity(0.1) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Brand.radius))
            .overlay(RoundedRectangle(cornerRadius: Brand.radius).stroke(on ? Brand.accent.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Ajustes → Módulos

struct ModulesCard: View {
    @Environment(Store.self) private var store
    @State private var paths: [String: String] = [:]
    @State private var pathMessage = ""

    var body: some View {
        Card(title: "Módulos", icon: "square.grid.2x2",
             info: "Un módulo oculto quita sus pantallas, sus tarjetas de Inicio y sus avisos. Sus notas no se tocan.") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                ForEach(Module.allCases) { m in
                    GridRow {
                        Toggle(isOn: Binding(get: { !store.hiddenModules.contains(m) },
                                             set: { if $0 { store.hiddenModules.remove(m) } else { store.hiddenModules.insert(m) } })) {
                            Label(label(m), systemImage: m.icon)
                        }
                        let missing = store.missingFiles(m)
                        // Un módulo oculto no necesita su nota: no se avisa de que falta.
                        if missing.isEmpty || store.hiddenModules.contains(m) {
                            Text(m.files.map(VaultPath.path).joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            HStack(spacing: 8) {
                                Text("falta \(missing.joined(separator: ", "))").font(.caption).foregroundStyle(Brand.warn).lineLimit(1)
                                Button("Crear") { store.createStarterNotes([m]) }.controlSize(.small)
                            }
                        }
                    }
                }
            }
            DisclosureGroup("Rutas de las notas") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Si tus notas tienen otros nombres o están en otras carpetas, escribe aquí su ruta dentro de la carpeta de notas. Vacío = la de siempre. Intro para guardar.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(VaultPath.defaults.keys.sorted { (Starter.labels[$0] ?? $0) < (Starter.labels[$1] ?? $1) }, id: \.self) { key in
                            GridRow {
                                Text(Starter.labels[key] ?? key).font(.callout)
                                TextField(VaultPath.defaults[key] ?? "", text: Binding(get: { paths[key] ?? "" }, set: { paths[key] = $0 }))
                                    .font(.callout.monospaced()).frame(minWidth: 280)
                                    .onSubmit { save(key) }
                                Image(systemName: store.exists(VaultPath.path(key)) ? "checkmark.circle" : "questionmark.circle")
                                    .foregroundStyle(store.exists(VaultPath.path(key)) ? Brand.accent : .secondary)
                                    .help(store.exists(VaultPath.path(key)) ? "Existe" : "No existe todavía")
                            }
                        }
                    }
                    if !pathMessage.isEmpty { Text(pathMessage).font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 6)
            }
        }
        .onAppear { paths = VaultPath.overrides }
    }

    /// «Medicación (Ozempic)», «Mascota (Luna)»; sin repetir si la nota aún no tiene nombre.
    private func label(_ m: Module) -> String {
        let name = m == .medicacion ? store.medicacion.name : m == .mascota ? store.mascota.name : nil
        return name.map { $0 == "Medicación" || $0 == "Mascota" ? m.title : "\(m.title) (\($0))" } ?? m.title
    }

    private func save(_ key: String) {
        let value = (paths[key] ?? "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isFolder = key == "gastos" || key == "revisiones"
        if !value.isEmpty, !isFolder, !value.hasSuffix(".md") { pathMessage = "«\(value)» debe acabar en .md."; return }
        VaultPath.setOverride(key, value.isEmpty ? nil : value)
        paths[key] = value
        pathMessage = value.isEmpty ? "\(Starter.labels[key] ?? key): vuelve a \(VaultPath.defaults[key] ?? "")." : "\(Starter.labels[key] ?? key): \(value)."
        store.reload()
    }
}
