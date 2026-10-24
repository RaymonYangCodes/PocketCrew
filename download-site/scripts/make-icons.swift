import AppKit
import Foundation
let output = CommandLine.arguments[1]
let source = URL(fileURLWithPath: output).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ios/PocketCrewIOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
guard let logo = NSImage(contentsOf: source) else { fatalError("PocketCrew logo asset missing") }
for size in [180, 192, 512] {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  NSColor(srgbRed: 31/255, green: 106/255, blue: 74/255, alpha: 1).setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()
  logo.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("icon-\(size).png"))
}
