#!/usr/bin/swift

import AppKit
import Foundation

let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resourceDirectory = projectDirectory.appendingPathComponent("Resources")

func makeIcon(pixelSize: Int, outputName: String) throws {
    let size = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSColor(calibratedRed: 88.0 / 255.0,
            green: 86.0 / 255.0,
            blue: 214.0 / 255.0,
            alpha: 1.0).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    NSColor.white.setFill()
    let tileSize = size * 43.0 / 180.0
    let firstOrigin = size * 39.0 / 180.0
    let secondOrigin = size * 98.0 / 180.0
    let radius = size * 10.0 / 180.0
    for x in [firstOrigin, secondOrigin] {
        for y in [firstOrigin, secondOrigin] {
            NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: tileSize, height: tileSize),
                xRadius: radius,
                yRadius: radius
            ).fill()
        }
    }

    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CCShortcutLauncherIcon", code: 1)
    }
    try png.write(to: resourceDirectory.appendingPathComponent(outputName))
}

try makeIcon(pixelSize: 60, outputName: "CCShortcutLauncherIcon.png")
try makeIcon(pixelSize: 120, outputName: "CCShortcutLauncherIcon@2x.png")
try makeIcon(pixelSize: 180, outputName: "CCShortcutLauncherIcon@3x.png")
