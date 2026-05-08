#!/usr/bin/env swift
// Pomodoro app ikonu üretir: gradient yuvarlatılmış kare + 🍅 emoji
// Çıktı: AppIcon.icns (CFBundleIconFile için)
//
// Kullanım: swift icon-gen.swift

import AppKit
import Foundation

// MARK: - Çizim

func renderPNG(size: CGFloat) -> Data? {
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225 // macOS Big Sur+ ikon köşe yarıçapı oranı
    let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    clip.addClip()

    // Gradient — domates kırmızısı (modern minimal, açık üst → koyu alt)
    let topColor = NSColor(srgbRed: 1.00, green: 0.45, blue: 0.40, alpha: 1)
    let bottomColor = NSColor(srgbRed: 0.79, green: 0.27, blue: 0.20, alpha: 1)
    let gradient = NSGradient(colors: [topColor, bottomColor])
    gradient?.draw(in: rect, angle: -90)

    // İç parlama
    let highlight = NSColor(white: 1.0, alpha: 0.18)
    let highlightPath = NSBezierPath(
        roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04),
        xRadius: radius * 0.85,
        yRadius: radius * 0.85
    )
    highlight.setStroke()
    highlightPath.lineWidth = max(1, size * 0.008)
    highlightPath.stroke()

    // 🍅 emoji ortada
    let emoji = "🍅"
    let fontSize = size * 0.62
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize),
        .paragraphStyle: style,
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let textSize = str.size()
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.03,
        width: textSize.width,
        height: textSize.height
    )
    str.draw(in: textRect)

    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

// MARK: - .iconset üret

let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let iconsetURL = URL(fileURLWithPath: cwd).appendingPathComponent("AppIcon.iconset")

if fm.fileExists(atPath: iconsetURL.path) {
    try? fm.removeItem(at: iconsetURL)
}
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// macOS .iconset zorunlu boyutlar
let sizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

print("==> İkon boyutları üretiliyor…")
for (name, pixels) in sizes {
    guard let png = renderPNG(size: pixels) else {
        FileHandle.standardError.write("Render hatası: \(name)\n".data(using: .utf8) ?? Data())
        exit(1)
    }
    let dest = iconsetURL.appendingPathComponent(name)
    try png.write(to: dest)
    print("    \(name) (\(Int(pixels))px)")
}

// MARK: - iconutil ile .icns'e çevir

let icnsURL = URL(fileURLWithPath: cwd).appendingPathComponent("AppIcon.icns")
if fm.fileExists(atPath: icnsURL.path) {
    try? fm.removeItem(at: icnsURL)
}

print("==> iconutil ile AppIcon.icns oluşturuluyor…")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("==> Tamam: \(icnsURL.path)")
} else {
    FileHandle.standardError.write("iconutil hatası (status: \(process.terminationStatus))\n".data(using: .utf8) ?? Data())
    exit(1)
}
