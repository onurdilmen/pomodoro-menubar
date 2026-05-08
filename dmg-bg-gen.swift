#!/usr/bin/env swift
// DMG arka plan görseli üretir (540x380, @2x = 1080x760).
// Çıktı: dmg-background.png (normal) ve dmg-background@2x.png (HiDPI).
//
// Kullanım: swift dmg-bg-gen.swift

import AppKit
import Foundation

// İkon yerleşim koordinatları (DMG layout ile eşleşmeli)
let CANVAS = NSSize(width: 540, height: 380)
let APP_ICON_CENTER = NSPoint(x: 140, y: 200)
let APPS_ICON_CENTER = NSPoint(x: 400, y: 200)

func render(at scale: CGFloat) -> Data? {
    let pixelSize = NSSize(width: CANVAS.width * scale, height: CANVAS.height * scale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize.width),
        pixelsHigh: Int(pixelSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)

    // Arka plan — minimal sıcak tonda, app ikonu ile uyumlu (domates kırmızısı + krem)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.99, green: 0.96, blue: 0.93, alpha: 1),  // krem üst
        NSColor(srgbRed: 0.96, green: 0.90, blue: 0.86, alpha: 1),  // hafif pembe alt
    ])
    gradient?.draw(in: NSRect(origin: .zero, size: CANVAS), angle: -90)

    // Başlık — "🍅 Pomodoro"
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.30, green: 0.18, blue: 0.15, alpha: 1),
        .paragraphStyle: titleStyle,
    ]
    let title = NSAttributedString(string: "🍅 Pomodoro", attributes: titleAttrs)
    title.draw(in: NSRect(x: 0, y: CANVAS.height - 65, width: CANVAS.width, height: 40))

    // Alt başlık
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.40, green: 0.30, blue: 0.27, alpha: 1),
        .paragraphStyle: titleStyle,
    ]
    let sub = NSAttributedString(
        string: "Mac menü çubuğunda yaşayan zamanlayıcı",
        attributes: subAttrs
    )
    sub.draw(in: NSRect(x: 0, y: CANVAS.height - 90, width: CANVAS.width, height: 20))

    // Ortadaki yönerge oku
    let arrowY: CGFloat = 200
    let arrowStart: CGFloat = APP_ICON_CENTER.x + 60
    let arrowEnd: CGFloat = APPS_ICON_CENTER.x - 60
    let arrowColor = NSColor(srgbRed: 0.79, green: 0.27, blue: 0.20, alpha: 0.85)
    arrowColor.setStroke()
    arrowColor.setFill()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: arrowStart, y: arrowY))
    arrow.line(to: NSPoint(x: arrowEnd - 12, y: arrowY))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.stroke()

    // Ok başı (üçgen)
    let head = NSBezierPath()
    head.move(to: NSPoint(x: arrowEnd, y: arrowY))
    head.line(to: NSPoint(x: arrowEnd - 14, y: arrowY - 7))
    head.line(to: NSPoint(x: arrowEnd - 14, y: arrowY + 7))
    head.close()
    head.fill()

    // Alt yönerge metni
    let instrAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.30, green: 0.18, blue: 0.15, alpha: 1),
        .paragraphStyle: titleStyle,
    ]
    let instr = NSAttributedString(
        string: "Pomodoro'yu kurmak için Applications'a sürükle",
        attributes: instrAttrs
    )
    instr.draw(in: NSRect(x: 0, y: 100, width: CANVAS.width, height: 20))

    // Çok küçük not
    let noteAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.55, green: 0.45, blue: 0.42, alpha: 1),
        .paragraphStyle: titleStyle,
    ]
    let note = NSAttributedString(
        string: "İlk açılışta: Sistem Ayarları → Gizlilik & Güvenlik → \"Yine de Aç\"",
        attributes: noteAttrs
    )
    note.draw(in: NSRect(x: 0, y: 50, width: CANVAS.width, height: 16))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

// 1x ve 2x PNG'leri yaz
let cwd = FileManager.default.currentDirectoryPath
guard let png1x = render(at: 1.0) else {
    FileHandle.standardError.write("1x render fail\n".data(using: .utf8) ?? Data())
    exit(1)
}
try png1x.write(to: URL(fileURLWithPath: cwd).appendingPathComponent("dmg-background.png"))
print("Yazıldı: dmg-background.png (\(Int(CANVAS.width))x\(Int(CANVAS.height)))")

guard let png2x = render(at: 2.0) else {
    FileHandle.standardError.write("2x render fail\n".data(using: .utf8) ?? Data())
    exit(1)
}
try png2x.write(to: URL(fileURLWithPath: cwd).appendingPathComponent("dmg-background@2x.png"))
print("Yazıldı: dmg-background@2x.png (\(Int(CANVAS.width * 2))x\(Int(CANVAS.height * 2)))")
