import Cocoa
import CoreGraphics

// 生成 1024x1024 主图标并通过 iconutil 打包 AppIcon.icns
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let previewOut = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

func renderIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // 统一在 1024x1024 逻辑坐标系下绘制，保证任意尺寸比例完全一致
    let scale = CGFloat(size) / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185.0
    let squircle = CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // 1. 底部柔和外投影
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -20),
        blur: 36,
        color: CGColor(red: 0.01, green: 0.18, blue: 0.22, alpha: 0.38)
    )
    ctx.setFillColor(CGColor(red: 0.05, green: 0.55, blue: 0.50, alpha: 1.0))
    ctx.addPath(squircle)
    ctx.fillPath()
    ctx.restoreGState()

    // 2. 裁剪至圆角底板内部绘制渐变与光晕
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // 2.1 对角主渐变：鲜翠绿 -> 祖母青 -> 深海蓝青
    let bgColors: [CGColor] = [
        CGColor(red: 0.13, green: 0.85, blue: 0.62, alpha: 1.0),
        CGColor(red: 0.04, green: 0.63, blue: 0.56, alpha: 1.0),
        CGColor(red: 0.02, green: 0.33, blue: 0.47, alpha: 1.0)
    ]
    let bgLocations: [CGFloat] = [0.0, 0.52, 1.0]
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: bgLocations)!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: 120, y: 904),
        end: CGPoint(x: 904, y: 120),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // 2.2 中心径向呼吸能量光晕
    let glowColors: [CGColor] = [
        CGColor(red: 0.42, green: 1.00, blue: 0.82, alpha: 0.30),
        CGColor(red: 0.10, green: 0.82, blue: 0.70, alpha: 0.00)
    ]
    let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(
        glowGrad,
        startCenter: CGPoint(x: 495, y: 535),
        startRadius: 10,
        endCenter: CGPoint(x: 512, y: 512),
        endRadius: 430,
        options: []
    )

    // 2.3 同心脉冲波纹暗纹（大尺寸保留细节，极小尺寸自动弱化保持干净）
    if size >= 64 {
        for (radius, alpha, width) in [(CGFloat(240), CGFloat(0.10), CGFloat(3.5)),
                                       (CGFloat(340), CGFloat(0.06), CGFloat(2.5))] {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            ctx.setLineWidth(width)
            ctx.strokeEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
        }
    }

    // 3. 核心图形：心电脉冲折线 + 右端在线呼吸圆点
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: 225, y: 500))
    pulse.addLine(to: CGPoint(x: 350, y: 500))
    pulse.addLine(to: CGPoint(x: 400, y: 425))
    pulse.addLine(to: CGPoint(x: 476, y: 710))
    pulse.addLine(to: CGPoint(x: 556, y: 320))
    pulse.addLine(to: CGPoint(x: 620, y: 550))
    pulse.addLine(to: CGPoint(x: 662, y: 500))
    pulse.addLine(to: CGPoint(x: 765, y: 500))

    let dotCenter = CGPoint(x: 765, y: 500)

    // 3.1 青白荧光外发光层
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: 0),
        blur: 38,
        color: CGColor(red: 0.55, green: 1.00, blue: 0.88, alpha: 0.60)
    )
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(48)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(pulse)
    ctx.strokePath()
    ctx.restoreGState()

    // 3.2 右端在线呼吸外光环
    let haloRadius: CGFloat = 56
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24))
    ctx.fillEllipse(in: CGRect(
        x: dotCenter.x - haloRadius,
        y: dotCenter.y - haloRadius,
        width: haloRadius * 2,
        height: haloRadius * 2
    ))

    // 3.3 主体纯白波形与圆点（透明图层合并后统一投射立体底阴影，消除交界重影）
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 18,
        color: CGColor(red: 0.01, green: 0.20, blue: 0.26, alpha: 0.34)
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.setLineWidth(48)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(pulse)
    ctx.strokePath()

    let dotRadius: CGFloat = 34
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    ))

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 4. 顶部玻璃质感高光内描边
    let insetRect = bodyRect.insetBy(dx: 2.0, dy: 2.0)
    let innerBorder = CGPath(roundedRect: insetRect, cornerWidth: cornerRadius - 2, cornerHeight: cornerRadius - 2, transform: nil)
    ctx.saveGState()
    ctx.addPath(innerBorder)
    ctx.setLineWidth(4.0)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let rimColors: [CGColor] = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.48),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.12)
    ]
    let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors as CFArray, locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(
        rimGrad,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )
    ctx.restoreGState()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconsetPath = "/tmp/PulseAwake_AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

var cache: [Int: NSBitmapImageRep] = [:]
for (filename, px) in specs {
    let rep = cache[px] ?? {
        let r = renderIcon(size: px)
        cache[px] = r
        return r
    }()
    try writePNG(rep, to: "\(iconsetPath)/\(filename)")
}

if let previewPath = previewOut, let rep1024 = cache[1024] {
    try writePNG(rep1024, to: previewPath)
}

let icnsPath = "\(outDir)/AppIcon.icns"
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try proc.run()
proc.waitUntilExit()
try? fm.removeItem(atPath: iconsetPath)

guard proc.terminationStatus == 0 else {
    fputs("iconutil 打包失败\n", stderr)
    exit(1)
}
print("已生成图标: \(icnsPath)")
