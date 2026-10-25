// Renders the effect off-screen to a PNG, for checking visuals without
// installing the screen saver.
//
// Usage: snapshot <out.png> [width] [height] [color] [glyphStyle] [seconds]

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: snapshot <out.png> [width] [height] [color] [glyphStyle] [seconds]")
    print("colors: \(MatrixColor.allCases.map(\.rawValue).joined(separator: ", "))")
    print("styles: \(GlyphStyle.allCases.map(\.rawValue).joined(separator: ", "))")
    exit(1)
}

let width = args.count > 2 ? Int(args[2]) ?? 1440 : 1440
let height = args.count > 3 ? Int(args[3]) ?? 900 : 900
var settings = MatrixSettings()
if args.count > 4, let color = MatrixColor(rawValue: args[4]) { settings.color = color }
if args.count > 5, let style = GlyphStyle(rawValue: args[5]) { settings.glyphStyle = style }
let seconds = args.count > 6 ? Double(args[6]) ?? 6 : 6

let scale: CGFloat = 2
let size = CGSize(width: width, height: height)
let scene = MatrixScene(settings: settings, seed: 42)
scene.simulation(for: size)

let frame = MatrixScene.frameInterval
for _ in 0..<Int(seconds / frame) { scene.advance(by: frame) }

guard let context = CGContext(
    data: nil,
    width: Int(CGFloat(width) * scale),
    height: Int(CGFloat(height) * scale),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create bitmap context") }
context.scaleBy(x: scale, y: scale)

// The first draw pays for font loading and glyph caching; report the
// steady-state cost, which is what the screen saver sees every frame.
scene.draw(in: context, size: size)
let timedFrames = 20
let start = Date()
for _ in 0..<timedFrames {
    scene.advance(by: frame)
    scene.draw(in: context, size: size)
}
let drawTime = Date().timeIntervalSince(start) / Double(timedFrames)

let url = URL(fileURLWithPath: args[1])
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not create image") }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(String(format: "wrote %@ (steady-state frame: %.1f ms)", url.path, drawTime * 1000))
