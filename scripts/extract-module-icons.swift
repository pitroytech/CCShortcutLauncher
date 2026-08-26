#!/usr/bin/swift

import AppKit
import CoreGraphics
import Foundation

private let iconNames = [
    "sparkles", "bookmark", "phone", "camera", "chat", "chats", "message", "crown",
    "trash", "compass", "note", "diamond", "edit", "wallet", "document", "flag",
    "photo", "gift", "help", "home", "translate", "heart", "lock", "unlock",
    "mail", "megaphone", "microphone", "music", "location", "play", "briefcase", "book",
    "trash-slash", "search", "send", "settings", "star", "tag", "shirt", "fire",
    "video", "video-slash", "eye", "hourglass",
]

private let columns = 8
private let rows = 6
private let occupiedColumns = [8, 8, 8, 8, 8, 4]
private let outputSide = 128
private let glyphSide = 92.0

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: extract-module-icons.swift <contact-sheet.png> [output-directory]\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputDirectory = CommandLine.arguments.count >= 3
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : projectDirectory.appendingPathComponent("ModuleIcons")

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(
        domain: "CCShortcutLauncherIconExtraction",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Cannot read \(sourceURL.path)"]
    )
}

var proposedRect = NSRect(origin: .zero, size: sourceImage.size)
guard let sourceCGImage = sourceImage.cgImage(
    forProposedRect: &proposedRect,
    context: nil,
    hints: nil
) else {
    throw NSError(domain: "CCShortcutLauncherIconExtraction", code: 2)
}

let sourceWidth = sourceCGImage.width
let sourceHeight = sourceCGImage.height
let sourceBytesPerRow = sourceWidth * 4
let sourceStorage = UnsafeMutableRawPointer.allocate(
    byteCount: sourceBytesPerRow * sourceHeight,
    alignment: MemoryLayout<UInt8>.alignment
)
defer { sourceStorage.deallocate() }

guard let sourceContext = CGContext(
    data: sourceStorage,
    width: sourceWidth,
    height: sourceHeight,
    bitsPerComponent: 8,
    bytesPerRow: sourceBytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    throw NSError(domain: "CCShortcutLauncherIconExtraction", code: 3)
}

// CGBitmapContext exposes the first memory row in the same top-to-bottom order
// as this PNG once the CGImage is drawn without an additional transform.
sourceContext.draw(
    sourceCGImage,
    in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
)

let sourcePixels = sourceStorage.bindMemory(
    to: UInt8.self,
    capacity: sourceBytesPerRow * sourceHeight
)

func luminanceAt(x: Int, y: Int) -> Int {
    let offset = y * sourceBytesPerRow + x * 4
    let red = Int(sourcePixels[offset])
    let green = Int(sourcePixels[offset + 1])
    let blue = Int(sourcePixels[offset + 2])
    return (77 * red + 150 * green + 29 * blue) >> 8
}

func maskAlpha(luminance: Int) -> UInt8 {
    // The sheet background is about 248/255. Values at or above 230 are
    // background; darker antialiased edge pixels become proportional alpha.
    guard luminance < 230 else { return 0 }
    return UInt8(max(0, min(255, (230 - luminance) * 255 / 230)))
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CCShortcutLauncherIconExtraction", code: 4)
    }
    try data.write(to: url, options: .atomic)
}

var iconIndex = 0
for row in 0..<rows {
    for column in 0..<occupiedColumns[row] {
        let cellMinX = column * sourceWidth / columns
        let cellMaxX = (column + 1) * sourceWidth / columns
        let cellMinY = row * sourceHeight / rows
        let cellMaxY = (row + 1) * sourceHeight / rows

        var minX = cellMaxX
        var minY = cellMaxY
        var maxX = cellMinX
        var maxY = cellMinY
        for y in cellMinY..<cellMaxY {
            for x in cellMinX..<cellMaxX where luminanceAt(x: x, y: y) < 225 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX, minY <= maxY, iconIndex < iconNames.count else {
            throw NSError(
                domain: "CCShortcutLauncherIconExtraction",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Missing glyph at row \(row), column \(column)"]
            )
        }

        // Keep a tiny source margin so antialiased edge pixels are not clipped.
        minX = max(cellMinX, minX - 2)
        minY = max(cellMinY, minY - 2)
        maxX = min(cellMaxX - 1, maxX + 2)
        maxY = min(cellMaxY - 1, maxY + 2)
        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1
        let cropBytesPerRow = cropWidth * 4
        var cropPixels = [UInt8](repeating: 0, count: cropBytesPerRow * cropHeight)

        for y in 0..<cropHeight {
            for x in 0..<cropWidth {
                let alpha = maskAlpha(luminance: luminanceAt(x: minX + x, y: minY + y))
                let offset = y * cropBytesPerRow + x * 4
                cropPixels[offset] = 0
                cropPixels[offset + 1] = 0
                cropPixels[offset + 2] = 0
                cropPixels[offset + 3] = alpha
            }
        }

        let cropImage: CGImage = try cropPixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: cropWidth,
                height: cropHeight,
                bitsPerComponent: 8,
                bytesPerRow: cropBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let image = context.makeImage() else {
                throw NSError(domain: "CCShortcutLauncherIconExtraction", code: 6)
            }
            return image
        }

        let outputBytesPerRow = outputSide * 4
        var outputPixels = [UInt8](repeating: 0, count: outputBytesPerRow * outputSide)
        let outputImage: CGImage = try outputPixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: outputSide,
                height: outputSide,
                bitsPerComponent: 8,
                bytesPerRow: outputBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw NSError(domain: "CCShortcutLauncherIconExtraction", code: 7)
            }
            context.interpolationQuality = .high
            let scale = min(glyphSide / Double(cropWidth), glyphSide / Double(cropHeight))
            let drawWidth = Double(cropWidth) * scale
            let drawHeight = Double(cropHeight) * scale
            let drawRect = CGRect(
                x: (Double(outputSide) - drawWidth) / 2.0,
                y: (Double(outputSide) - drawHeight) / 2.0,
                width: drawWidth,
                height: drawHeight
            )
            context.draw(cropImage, in: drawRect)
            guard let image = context.makeImage() else {
                throw NSError(domain: "CCShortcutLauncherIconExtraction", code: 8)
            }
            return image
        }

        let name = iconNames[iconIndex]
        let destination = outputDirectory
            .appendingPathComponent("CSLModuleIcon.\(name).png")
        try writePNG(outputImage, to: destination)
        print("\(name)\trow=\(row) column=\(column) source=\(cropWidth)x\(cropHeight)")
        iconIndex += 1
    }
}

guard iconIndex == iconNames.count else {
    throw NSError(
        domain: "CCShortcutLauncherIconExtraction",
        code: 9,
        userInfo: [NSLocalizedDescriptionKey: "Expected \(iconNames.count) icons, wrote \(iconIndex)"]
    )
}

print("Wrote \(iconIndex) icons to \(outputDirectory.path)")
