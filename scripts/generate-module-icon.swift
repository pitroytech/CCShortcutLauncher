#!/usr/bin/swift

import AppKit
import Foundation

let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resourceDirectory = projectDirectory.appendingPathComponent("Resources")
let preferenceResourceDirectory = projectDirectory
    .appendingPathComponent("CCShortcutLauncherPrefs")
    .appendingPathComponent("Resources")
let sourceURL = projectDirectory
    .appendingPathComponent("artwork")
    .appendingPathComponent("CCShortcutLauncherIcon-1024.png")

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "CCShortcutLauncherIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Cannot read \(sourceURL.path)"]
    )
}

func makeIcon(pixelSize: Int, outputName: String, directory: URL) throws {
    let size = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1.0
    )
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CCShortcutLauncherIcon", code: 2)
    }
    try png.write(to: directory.appendingPathComponent(outputName))
}

try makeIcon(pixelSize: 60, outputName: "CCShortcutLauncherIcon.png", directory: resourceDirectory)
try makeIcon(pixelSize: 120, outputName: "CCShortcutLauncherIcon@2x.png", directory: resourceDirectory)
try makeIcon(pixelSize: 180, outputName: "CCShortcutLauncherIcon@3x.png", directory: resourceDirectory)

try makeIcon(pixelSize: 29, outputName: "icon.png", directory: preferenceResourceDirectory)
try makeIcon(pixelSize: 58, outputName: "icon@2x.png", directory: preferenceResourceDirectory)
try makeIcon(pixelSize: 87, outputName: "icon@3x.png", directory: preferenceResourceDirectory)
