// Genera el icono de la app (1024 px) y lo guarda como PNG: swift make-icon.swift salida.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Fondo: cuadrado redondeado con degradado verde azulado
let rect = NSRect(x: 40, y: 40, width: size - 80, height: size - 80)
let bg = NSBezierPath(roundedRect: rect, xRadius: 228, yRadius: 228)
NSGradient(colors: [NSColor(red: 0.05, green: 0.27, blue: 0.27, alpha: 1), NSColor(red: 0.13, green: 0.58, blue: 0.47, alpha: 1)])!.draw(in: bg, angle: 300)

// Brillo suave arriba
NSGraphicsContext.saveGraphicsState()
bg.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!.draw(in: NSRect(x: 0, y: size * 0.55, width: size, height: size * 0.45), angle: 270)
NSGraphicsContext.restoreGraphicsState()

// Grafo de notas, muy tenue, de fondo
let nodes: [(CGFloat, CGFloat, CGFloat)] = [(190, 800, 22), (330, 880, 16), (800, 820, 24), (860, 700, 14), (170, 250, 18), (860, 270, 20), (700, 170, 14)]
NSColor.white.withAlphaComponent(0.13).setStroke()
for (a, b) in [(0, 1), (2, 3), (5, 6), (2, 1)] {
    let l = NSBezierPath(); l.lineWidth = 6
    l.move(to: NSPoint(x: nodes[a].0, y: nodes[a].1)); l.line(to: NSPoint(x: nodes[b].0, y: nodes[b].1)); l.stroke()
}
NSColor.white.withAlphaComponent(0.2).setFill()
for n in nodes { NSBezierPath(ovalIn: NSRect(x: n.0 - n.2, y: n.1 - n.2, width: n.2 * 2, height: n.2 * 2)).fill() }

// «VOT» grande, en redondeada y muy gruesa
let base = NSFont.systemFont(ofSize: 360, weight: .black)
let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 360) } ?? base
let para = NSMutableParagraphStyle(); para.alignment = .center
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -10)
let title = NSAttributedString(string: "VOT", attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: para, .kern: 6, .shadow: shadow])
title.draw(in: NSRect(x: 0, y: 410, width: size, height: 420))

// Línea con nodos (enlaces) y «sidian» debajo
let y: CGFloat = 400
NSColor.white.withAlphaComponent(0.85).setStroke()
let line = NSBezierPath(); line.lineWidth = 12; line.lineCapStyle = .round
line.move(to: NSPoint(x: 300, y: y)); line.line(to: NSPoint(x: 724, y: y)); line.stroke()
NSColor.white.setFill()
for x in [300, 512, 724] as [CGFloat] { NSBezierPath(ovalIn: NSRect(x: x - 22, y: y - 22, width: 44, height: 44)).fill() }
let sub = NSAttributedString(string: "sidian", attributes: [
    .font: (NSFont.systemFont(ofSize: 150, weight: .semibold).fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 150) } ?? NSFont.systemFont(ofSize: 150, weight: .semibold)),
    .foregroundColor: NSColor.white.withAlphaComponent(0.92), .paragraphStyle: para, .kern: 10,
])
sub.draw(in: NSRect(x: 0, y: 150, width: size, height: 200))

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
