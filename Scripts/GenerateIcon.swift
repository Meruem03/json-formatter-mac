import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect.insetBy(dx: size * 0.03, dy: size * 0.03), xRadius: size * 0.22, yRadius: size * 0.22)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.95, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.22, blue: 0.62, alpha: 1.0)
])
gradient?.draw(in: bgPath, angle: -90)

let text = "{ }" as NSString
let fontSize = size * 0.42
let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let textSize = text.size(withAttributes: attrs)
let textRect = NSRect(
    x: (size - textSize.width) / 2,
    y: (size - textSize.height) / 2 - size * 0.02,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try pngData.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
