#!/usr/bin/env swift
// Generates the app icon (Assets/AppIcon.iconset/*.png + icon-1024.png) and
// the README banner (Assets/banner.png) programmatically, so the artwork is
// reproducible from source. Run: swift Scripts/make-assets.swift
// Then:  iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
//
// Same Liquid Glass icon language as its siblings Oriel, Coffer, and Pharos:
// the macOS squircle, frosted-glass forms (real gaussian-blurred backdrop via
// CoreImage), specular rim highlights, and soft layered shadows. Keystone's
// glyph is its namesake: a glass arch of even voussoirs on terracotta — the
// fired brick of the Roman arches that gave the keystone its job — with the
// keystone itself, the brightest pane, dropping into the gap at the apex and
// locking the whole thing together.

import AppKit
import CoreImage
import SwiftUI

// MARK: - Helpers

let ciContext = CIContext()

func makeBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func withContext(_ rep: NSBitmapImageRep, _ draw: (CGContext) -> Void) {
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.current = nil
}

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let rgb = CGColorSpaceCreateDeviceRGB()

func linearGradient(_ cg: CGContext, in path: CGPath, colors: [CGColor], from: CGPoint, to: CGPoint) {
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let grad = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: nil)!
    cg.drawLinearGradient(grad, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()
}

/// The macOS app-icon silhouette: a continuous-corner rounded rect (straight
/// edges, Apple's smooth corner curve) — not a superellipse, whose sides
/// bulge. Radius fitted against the system's live icon mask (measured from
/// Calculator/Notes/Finder at 1024px: 214.5px on the 824px shape, ~0.16px RMS).
func squircle(in rect: CGRect) -> CGPath {
    Path(roundedRect: rect, cornerRadius: rect.width * (214.5 / 824), style: .continuous).cgPath
}

func gaussianBlur(_ image: CGImage, radius: CGFloat) -> CGImage {
    let ci = CIImage(cgImage: image)
    let blurred = ci.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        .cropped(to: ci.extent)
    return ciContext.createCGImage(blurred, from: ci.extent)!
}

// MARK: - Icon (designed in a 1024x1024 space, bottom-left origin)

let designRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824) // standard macOS icon grid

/// Background layer: squircle, terracotta gradient, top sheen, outer shadow.
func drawIconBackground(_ cg: CGContext) {
    let shape = squircle(in: bgRect)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: color(0x000000, 0.28))
    cg.addPath(shape)
    cg.setFillColor(color(0xD4501E))
    cg.fillPath()
    cg.restoreGState()

    // A single restrained terracotta gradient, in the language of macOS
    // system icons: the background recedes, the glyph is the hero.
    linearGradient(
        cg, in: shape,
        colors: [color(0xF98A5F), color(0xB93412)],
        from: CGPoint(x: 512, y: bgRect.maxY), to: CGPoint(x: 512, y: bgRect.minY)
    )
    // Barely-there top light for depth
    linearGradient(
        cg, in: shape,
        colors: [color(0xFFFFFF, 0.12), color(0xFFFFFF, 0)],
        from: CGPoint(x: 512, y: bgRect.maxY), to: CGPoint(x: 512, y: bgRect.maxY - 320)
    )
}

/// Specular rim: a stroke around `path` that is bright on top, fading below.
func glassRim(_ cg: CGContext, around path: CGPath, width: CGFloat, bounds: CGRect, top: CGFloat, bottom: CGFloat) {
    let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    linearGradient(
        cg, in: stroked,
        colors: [color(0xFFFFFF, top), color(0xFFFFFF, bottom)],
        from: CGPoint(x: bounds.midX, y: bounds.maxY), to: CGPoint(x: bounds.midX, y: bounds.minY)
    )
}

/// One frosted-glass pane: blurred backdrop, milky tint, specular rim.
func drawGlassPane(
    _ cg: CGContext, path: CGPath, bounds: CGRect, backdrop: CGImage,
    tintTop: CGFloat, tintBottom: CGFloat,
    rimWidth: CGFloat, rimTop: CGFloat, rimBottom: CGFloat,
    shadowBlur: CGFloat, shadowAlpha: CGFloat
) {
    // Drop shadow (opaque fill, replaced by the glass interior right after)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -shadowBlur * 0.4), blur: shadowBlur, color: color(0x571708, shadowAlpha))
    cg.addPath(path)
    cg.setFillColor(color(0xF6CBB4))
    cg.fillPath()
    cg.restoreGState()

    // Blurred backdrop + milky tint
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    cg.draw(backdrop, in: designRect)
    linearGradient(
        cg, in: path,
        colors: [color(0xFFFFFF, tintTop), color(0xFFFFFF, tintBottom)],
        from: CGPoint(x: bounds.midX, y: bounds.maxY), to: CGPoint(x: bounds.midX, y: bounds.minY)
    )
    cg.restoreGState()

    glassRim(cg, around: path, width: rimWidth, bounds: bounds, top: rimTop, bottom: rimBottom)
}

// The glyph: a glass arch with a gap at the apex, and the keystone — the
// bright hero pane — set into it, protruding a little past both faces the
// way a real keystone does.
/* Center height chosen so the glyph's vertical span (leg bottoms to the
   keystone's top) sits 4px above true center — a slight optical lift, since
   the bright keystone up top is where the eye lands. */
let archCenter = CGPoint(x: 512, y: 444)
let outerR: CGFloat = 258
let innerR: CGFloat = 158
let legDrop: CGFloat = 140
/// Half-angle of the apex gap the keystone occupies.
let gapHalf: CGFloat = 15 * .pi / 180

/// Both flanks of the arch (outer arc, inner arc, straight legs), minus the
/// keystone gap, as one path.
func archPath() -> CGPath {
    let p = CGMutablePath()
    let cy = archCenter.y

    // Left flank: leg up, outer arc to the gap, inner arc back, leg down.
    p.move(to: CGPoint(x: archCenter.x - outerR, y: cy - legDrop))
    p.addLine(to: CGPoint(x: archCenter.x - outerR, y: cy))
    p.addArc(center: archCenter, radius: outerR,
             startAngle: .pi, endAngle: .pi / 2 + gapHalf, clockwise: true)
    p.addLine(to: CGPoint(
        x: archCenter.x + cos(.pi / 2 + gapHalf) * innerR,
        y: cy + sin(.pi / 2 + gapHalf) * innerR))
    p.addArc(center: archCenter, radius: innerR,
             startAngle: .pi / 2 + gapHalf, endAngle: .pi, clockwise: false)
    p.addLine(to: CGPoint(x: archCenter.x - innerR, y: cy - legDrop))
    p.closeSubpath()

    // Right flank, mirrored.
    p.move(to: CGPoint(x: archCenter.x + outerR, y: cy - legDrop))
    p.addLine(to: CGPoint(x: archCenter.x + outerR, y: cy))
    p.addArc(center: archCenter, radius: outerR,
             startAngle: 0, endAngle: .pi / 2 - gapHalf, clockwise: false)
    p.addLine(to: CGPoint(
        x: archCenter.x + cos(.pi / 2 - gapHalf) * innerR,
        y: cy + sin(.pi / 2 - gapHalf) * innerR))
    p.addArc(center: archCenter, radius: innerR,
             startAngle: .pi / 2 - gapHalf, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: archCenter.x + innerR, y: cy - legDrop))
    p.closeSubpath()

    return p
}

/// The keystone wedge: a trapezoid at the apex, wider at the top, sticking
/// out past the arch's outer and inner faces.
func keystonePath() -> CGPath {
    let topY = archCenter.y + outerR + 26
    let bottomY = archCenter.y + innerR - 20
    let topHalf: CGFloat = 82
    let bottomHalf: CGFloat = 50
    let p = CGMutablePath()
    p.move(to: CGPoint(x: archCenter.x - topHalf, y: topY))
    p.addLine(to: CGPoint(x: archCenter.x + topHalf, y: topY))
    p.addLine(to: CGPoint(x: archCenter.x + bottomHalf, y: bottomY))
    p.addLine(to: CGPoint(x: archCenter.x - bottomHalf, y: bottomY))
    p.closeSubpath()
    return p
}

var archBounds: CGRect { archPath().boundingBox }
var keystoneBounds: CGRect { keystonePath().boundingBox }

/// Voussoir joints: faint radial seams that make the flanks read as fitted
/// stones rather than solid tubes. Each flank spans 75° (springing line to
/// the keystone gap), so seams every 25° cut it into three equal stones;
/// the 0°/180° seams are the impost lines, where the arc meets the legs.
/// Shared between the rendered icon and the flat Icon Composer layers.
func drawArchJoints(_ cg: CGContext, alpha: CGFloat) {
    cg.saveGState()
    cg.setStrokeColor(color(0x8F2F10, alpha))
    cg.setLineWidth(7)
    cg.setLineCap(.round)
    for degrees: CGFloat in [0, 25, 50, 130, 155, 180] {
        let angle = degrees * .pi / 180
        cg.move(to: CGPoint(
            x: archCenter.x + cos(angle) * (innerR + 10),
            y: archCenter.y + sin(angle) * (innerR + 10)))
        cg.addLine(to: CGPoint(
            x: archCenter.x + cos(angle) * (outerR - 10),
            y: archCenter.y + sin(angle) * (outerR - 10)))
    }
    cg.strokePath()
    cg.restoreGState()
}

func drawArch(_ cg: CGContext, backdrop: CGImage, boost: Bool) {
    let path = archPath()
    drawGlassPane(
        cg, path: path, bounds: archBounds, backdrop: backdrop,
        tintTop: boost ? 0.8 : 0.66, tintBottom: boost ? 0.64 : 0.48,
        rimWidth: 5, rimTop: 0.95, rimBottom: 0.25,
        shadowBlur: 44, shadowAlpha: 0.3
    )
    drawArchJoints(cg, alpha: 0.22)
}

func drawKeystone(_ cg: CGContext, backdrop: CGImage, boost: Bool) {
    drawGlassPane(
        cg, path: keystonePath(), bounds: keystoneBounds, backdrop: backdrop,
        tintTop: boost ? 0.98 : 0.95, tintBottom: boost ? 0.92 : 0.84,
        rimWidth: 5, rimTop: 1.0, rimBottom: 0.35,
        shadowBlur: 38, shadowAlpha: 0.34
    )
}

/// Renders the complete icon at `px` and returns the bitmap.
func makeIcon(px: Int) -> NSBitmapImageRep {
    let scale = CGFloat(px) / 1024
    let blurRadius = max(36 * scale, 1)
    // Small sizes: more opaque forms keep the glyph legible in the menu bar /
    // Dock, where the frosted subtlety would just vanish.
    let boost = px <= 64

    let bgRep = makeBitmap(px, px)
    withContext(bgRep) { cg in
        cg.scaleBy(x: scale, y: scale)
        drawIconBackground(cg)
    }
    let backdrop = gaussianBlur(bgRep.cgImage!, radius: blurRadius)

    let shape = squircle(in: bgRect)

    /* Clip the glyph to the squircle, and at small sizes optically enlarge
       it (like Apple's small-size icon variants) so it stays prominent in
       the menu bar / Dock. */
    func drawGlyph(_ cg: CGContext, _ body: (CGContext) -> Void) {
        cg.saveGState()
        cg.addPath(shape)
        cg.clip()
        if boost {
            cg.translateBy(x: 512, y: 512)
            cg.scaleBy(x: 1.14, y: 1.14)
            cg.translateBy(x: -512, y: -512)
        }
        body(cg)
        cg.restoreGState()
    }

    // Intermediate scene (background + arch), so the keystone's backdrop
    // blur includes the arch it is settling into.
    let midRep = makeBitmap(px, px)
    withContext(midRep) { cg in
        cg.scaleBy(x: scale, y: scale)
        cg.draw(bgRep.cgImage!, in: designRect)
        drawGlyph(cg) { drawArch($0, backdrop: backdrop, boost: boost) }
    }
    let midBackdrop = gaussianBlur(midRep.cgImage!, radius: blurRadius)

    let rep = makeBitmap(px, px)
    withContext(rep) { cg in
        cg.scaleBy(x: scale, y: scale)
        cg.draw(midRep.cgImage!, in: designRect)
        drawGlyph(cg) { drawKeystone($0, backdrop: midBackdrop, boost: boost) }
    }
    return rep
}

// MARK: - Icon Composer layers (macOS 26+ .icon document)

/* The .icon format gets dark/clear/tinted appearances for free: we ship flat
   transparent layers plus a background fill, and the system renders the
   Liquid Glass treatment (and the dark background) at runtime. In a .icon
   document the 1024pt canvas IS the icon shape — the system adds its own
   margins — whereas our design space puts the squircle at 100..924, so the
   glyph is remapped to land at the same visual position. */
func makeIconLayer(_ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = makeBitmap(1024, 1024)
    withContext(rep) { cg in
        cg.scaleBy(x: 1024 / 824, y: 1024 / 824)
        cg.translateBy(x: -100, y: -100)
        draw(cg)
    }
    return rep
}

func drawFlatArch(_ cg: CGContext) {
    // Semi-transparent so the system's glass treatment lets the background
    // glow through the flanks; the keystone in front stays the bright one.
    cg.addPath(archPath())
    cg.setFillColor(color(0xFFFFFF, 0.76))
    cg.fillPath()
    drawArchJoints(cg, alpha: 0.2)
}

func drawFlatKeystone(_ cg: CGContext) {
    cg.addPath(keystonePath())
    cg.setFillColor(color(0xFFFFFF))
    cg.fillPath()
}

// MARK: - Banner (1800 x 600)

func drawBanner(_ cg: CGContext, icon: CGImage) {
    let canvas = CGRect(x: 0, y: 0, width: 1800, height: 600)
    let frame = CGPath(roundedRect: canvas, cornerWidth: 40, cornerHeight: 40, transform: nil)
    linearGradient(
        cg, in: frame,
        colors: [color(0x30130A), color(0x170703)],
        from: CGPoint(x: canvas.midX, y: canvas.maxY), to: CGPoint(x: canvas.midX, y: canvas.minY)
    )

    // Faint decorative keycap outlines on the right
    cg.saveGState()
    cg.addPath(frame)
    cg.clip()
    cg.setStrokeColor(color(0xFFFFFF, 0.07))
    cg.setLineWidth(3)
    for (x, y, s) in [(1400.0, 280.0, 220.0), (1560.0, 60.0, 260.0), (1250.0, -60.0, 190.0)] {
        cg.addPath(CGPath(
            roundedRect: CGRect(x: x, y: y, width: s, height: s),
            cornerWidth: 34, cornerHeight: 34, transform: nil
        ))
        cg.strokePath()
    }
    cg.restoreGState()

    // App icon on the left
    cg.draw(icon, in: CGRect(x: 100, y: 118, width: 364, height: 364))

    // Wordmark + tagline
    let title = NSAttributedString(string: "Keystone", attributes: [
        .font: NSFont.systemFont(ofSize: 130, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    title.draw(at: NSPoint(x: 520, y: 268))

    let tagline = NSAttributedString(string: "Input switching, without the delay", attributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.47, alpha: 1),
    ])
    tagline.draw(at: NSPoint(x: 528, y: 186))
}

// MARK: - GitHub social preview (1280 x 640 design space, rendered @2x)

func drawSocialPreview(_ cg: CGContext, icon: CGImage) {
    let canvas = CGRect(x: 0, y: 0, width: 1280, height: 640)
    // Full bleed — GitHub renders the preview edge to edge and rounds the
    // corners itself, so transparent corners would show through as white.
    linearGradient(
        cg, in: CGPath(rect: canvas, transform: nil),
        colors: [color(0x371509), color(0x170703)],
        from: CGPoint(x: canvas.midX, y: canvas.maxY), to: CGPoint(x: canvas.midX, y: canvas.minY)
    )

    // Faint decorative keycap outlines drifting off the corners
    cg.saveGState()
    cg.setStrokeColor(color(0xFFFFFF, 0.06))
    cg.setLineWidth(2.5)
    for (x, y, s) in [
        (-70.0, 450.0, 200.0), (90.0, 530.0, 170.0),
        (1060.0, -50.0, 220.0), (1160.0, 110.0, 180.0),
    ] {
        cg.addPath(CGPath(
            roundedRect: CGRect(x: x, y: y, width: s, height: s),
            cornerWidth: 28, cornerHeight: 28, transform: nil
        ))
        cg.strokePath()
    }
    cg.restoreGState()

    func drawCentered(_ text: NSAttributedString, y: CGFloat) {
        text.draw(at: NSPoint(x: canvas.midX - text.size().width / 2, y: y))
    }

    // Centered stack: icon, wordmark, tagline — sized up so the keystone
    // stays legible at the small sizes link previews render at.
    cg.draw(icon, in: CGRect(x: canvas.midX - 125, y: 300, width: 250, height: 250))

    drawCentered(
        NSAttributedString(string: "Keystone", attributes: [
            .font: NSFont.systemFont(ofSize: 100, weight: .bold),
            .foregroundColor: NSColor.white,
        ]), y: 180)

    drawCentered(
        NSAttributedString(string: "Input switching, without the delay", attributes: [
            .font: NSFont.systemFont(ofSize: 38, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.47, alpha: 1),
        ]), y: 118)
}

// MARK: - Main

let fm = FileManager.default
try? fm.createDirectory(atPath: "Assets/AppIcon.iconset", withIntermediateDirectories: true)

// Iconset: render each size directly from vectors (crisper than downscaling)
let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in iconSizes {
    savePNG(makeIcon(px: px), "Assets/AppIcon.iconset/\(name).png")
}

let master = makeIcon(px: 1024)
savePNG(master, "Assets/icon-1024.png")

// Icon Composer layers for the macOS 26+ .icon document
try? fm.createDirectory(atPath: "Assets/AppIcon.icon/Assets", withIntermediateDirectories: true)
savePNG(makeIconLayer(drawFlatArch), "Assets/AppIcon.icon/Assets/arch.png")
savePNG(makeIconLayer(drawFlatKeystone), "Assets/AppIcon.icon/Assets/keystone.png")

let bannerIcon = makeIcon(px: 728).cgImage!
let banner = makeBitmap(1800, 600)
withContext(banner) { drawBanner($0, icon: bannerIcon) }
savePNG(banner, "Assets/banner.png")

// GitHub social preview: exactly 1280x640, GitHub's recommended size.
let og = makeBitmap(1280, 640)
withContext(og) { cg in
    drawSocialPreview(cg, icon: bannerIcon)
}
savePNG(og, "Assets/og-image.png")
