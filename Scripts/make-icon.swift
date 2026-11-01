// 앱 아이콘 생성 스크립트
//   swift Scripts/make-icon.swift Resources/AppIcon.iconset
//
// 기존 아이콘(파란 배경 + 흰 별표)을 유지하면서 클립보드 모양을 더한 디자인.
// 크기별로 벡터에서 직접 그려 작은 크기에서도 선명하다.
// macOS 아이콘 그리드: 1024 캔버스 안에 824 크기 둥근 사각형 + 아래쪽 그림자.

import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillLinearGradient(_ ctx: CGContext, path: CGPath, top: CGColor, bottom: CGColor) {
    let box = path.boundingBox
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()
}

/// 1024x1024 좌표계 기준으로 그린다 (CoreGraphics: 왼쪽 아래 원점)
func drawIcon(in ctx: CGContext) {
    // 배경: 기존 아이콘의 하늘색 계열 그라데이션
    let body = roundedRect(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, alpha: 0.30))
    ctx.addPath(body)
    ctx.setFillColor(color(0x03A9F4))
    ctx.fillPath()
    ctx.restoreGState()
    fillLinearGradient(ctx, path: body, top: color(0x4FC3F7), bottom: color(0x0288D1))

    // 클립보드 판
    let board = roundedRect(CGRect(x: 262, y: 168, width: 500, height: 600), radius: 60)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x01579B, alpha: 0.45))
    ctx.addPath(board)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // 상단 집게
    let clip = CGMutablePath()
    clip.addPath(roundedRect(CGRect(x: 382, y: 712, width: 260, height: 112), radius: 34))
    clip.addPath(roundedRect(CGRect(x: 447, y: 790, width: 130, height: 86), radius: 40))
    let hole = CGPath(ellipseIn: CGRect(x: 487, y: 812, width: 50, height: 40), transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x000000, alpha: 0.25))
    ctx.addPath(clip)
    ctx.setFillColor(color(0x0D47A1))
    ctx.fillPath()
    ctx.restoreGState()
    fillLinearGradient(ctx, path: clip, top: color(0x1E63C4), bottom: color(0x0B3D8C))
    // 집게 구멍은 배경색 그라데이션이 비쳐 보이도록 같은 색으로
    fillLinearGradient(ctx, path: hole, top: color(0x48BFF5), bottom: color(0x45BDF4))

    // 기존 아이콘의 별표(8갈래)를 판 위에
    let center = CGPoint(x: 512, y: 446)
    let armLength: CGFloat = 168
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(62)
    ctx.setStrokeColor(color(0x039BE5))
    for step in 0..<4 {
        let angle = CGFloat(step) * .pi / 4
        let dx = cos(angle) * armLength
        let dy = sin(angle) * armLength
        ctx.move(to: CGPoint(x: center.x - dx, y: center.y - dy))
        ctx.addLine(to: CGPoint(x: center.x + dx, y: center.y + dy))
    }
    ctx.strokePath()
    ctx.restoreGState()
}

func renderPNG(pixels: Int, to url: URL) throws {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: ctx)

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// iconutil이 요구하는 파일 이름 규칙
for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points, to: outputDirectory.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2, to: outputDirectory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("✅ \(outputDirectory.path)")
