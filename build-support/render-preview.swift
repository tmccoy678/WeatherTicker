#!/usr/bin/env swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

let canvasSize = NSSize(width: 1260, height: 180)
let frameCount = 54
let frameDelay = 0.065
let outputPath = CommandLine.arguments.dropFirst().first ?? "docs/weather-ticker-preview.gif"
let outputURL = URL(fileURLWithPath: outputPath)

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    frameCount,
    nil
) else {
    fatalError("Could not create the animated preview destination.")
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0
    ]
] as CFDictionary)

let tickerText = "BASSFIELD, MS 39421   •   NOAA 78°F   •   Dew point 68°F   •   RH 71%   •   Wind S 8 mph   •   Forecast: scattered thunderstorms, then clearing   •   NWS: no active alerts   •   Weather Underground and AccuWeather: open official source"
let tickerFont = NSFont.systemFont(ofSize: 22, weight: .semibold)
let tickerAttributes: [NSAttributedString.Key: Any] = [
    .font: tickerFont,
    .foregroundColor: NSColor(calibratedRed: 98 / 255, green: 210 / 255, blue: 1, alpha: 1)
]
let tickerWidth = (tickerText as NSString).size(withAttributes: tickerAttributes).width
let cycleWidth = tickerWidth + 180

func fill(_ rect: NSRect, color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    if radius > 0 {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    } else {
        NSBezierPath(rect: rect).fill()
    }
}

func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    let point = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + 1)
    (text as NSString).draw(at: point, withAttributes: attributes)
}

func drawButton(_ title: String, x: CGFloat, width: CGFloat) {
    let rect = NSRect(x: x, y: 45, width: width, height: 31)
    fill(rect, color: NSColor(calibratedRed: 28 / 255, green: 50 / 255, blue: 71 / 255, alpha: 1), radius: 5)
    NSColor(calibratedRed: 78 / 255, green: 110 / 255, blue: 140 / 255, alpha: 1).setStroke()
    let outline = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
    outline.lineWidth = 1
    outline.stroke()
    drawCentered(title, in: rect, font: .systemFont(ofSize: 12, weight: .medium), color: .white)
}

for frame in 0..<frameCount {
    let image = NSImage(size: canvasSize)
    image.lockFocus()

    fill(NSRect(origin: .zero, size: canvasSize), color: NSColor(calibratedRed: 12 / 255, green: 23 / 255, blue: 38 / 255, alpha: 1), radius: 12)
    fill(NSRect(x: 0, y: 106, width: 1260, height: 74), color: NSColor(calibratedRed: 8 / 255, green: 17 / 255, blue: 30 / 255, alpha: 1), radius: 12)
    fill(NSRect(x: 0, y: 36, width: 1260, height: 48), color: NSColor(calibratedRed: 20 / 255, green: 35 / 255, blue: 52 / 255, alpha: 1))

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 14, y: 112, width: 1232, height: 60)).addClip()
    let offset = CGFloat(frame) / CGFloat(frameCount) * cycleWidth
    let firstX = 30 - offset
    (tickerText as NSString).draw(at: NSPoint(x: firstX, y: 127), withAttributes: tickerAttributes)
    (tickerText as NSString).draw(at: NSPoint(x: firstX + cycleWidth, y: 127), withAttributes: tickerAttributes)
    NSGraphicsContext.restoreGraphicsState()

    var x: CGFloat = 10
    drawButton("Refresh", x: x, width: 74); x += 82
    let picker = NSRect(x: x, y: 45, width: 210, height: 31)
    fill(picker, color: NSColor(calibratedWhite: 0.96, alpha: 1), radius: 5)
    drawCentered("Bassfield, MS 39421   ▾", in: picker, font: .systemFont(ofSize: 12), color: NSColor(calibratedWhite: 0.12, alpha: 1)); x += 218
    drawButton("NOAA", x: x, width: 62); x += 70
    drawButton("WU", x: x, width: 52); x += 60
    drawButton("AccuWeather", x: x, width: 94); x += 102
    drawButton("My locations", x: x, width: 98); x += 106
    drawButton("Reload list", x: x, width: 80); x += 88
    drawButton("Save to Excel", x: x, width: 102); x += 110
    drawButton("Setup", x: x, width: 66); x += 74
    drawButton("On top: yes", x: x, width: 100); x += 108
    drawButton("Exit", x: x, width: 52)

    let dotColor = frame % 18 < 13
        ? NSColor(calibratedRed: 58 / 255, green: 214 / 255, blue: 126 / 255, alpha: 1)
        : NSColor(calibratedRed: 58 / 255, green: 214 / 255, blue: 126 / 255, alpha: 0.38)
    fill(NSRect(x: 12, y: 15, width: 9, height: 9), color: dotColor, radius: 4.5)
    let status = "Live NOAA data • Updated just now • Next automatic refresh in 10 minutes"
    (status as NSString).draw(
        at: NSPoint(x: 29, y: 10),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(calibratedRed: 182 / 255, green: 197 / 255, blue: 211 / 255, alpha: 1)
        ]
    )

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let cgImage = bitmap.cgImage
    else {
        fatalError("Could not render preview frame \(frame).")
    }

    CGImageDestinationAddImage(destination, cgImage, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDelay,
            kCGImagePropertyGIFUnclampedDelayTime: frameDelay
        ]
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not finalize the animated preview.")
}

print("Rendered \(outputPath)")
