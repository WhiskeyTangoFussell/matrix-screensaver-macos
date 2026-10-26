// Renders a fixed set of settings combinations at a fixed seed and prints one
// hash per checkpoint frame. Run before and after a refactor: identical output
// means nothing visible changed. See `make render-baseline` / `make render-check`.
//
// Hashes depend on the installed fonts and macOS's text rasterizer, so only
// compare runs from the same machine and OS version.

import CoreGraphics
import Foundation

/// FNV-1a over the raw pixels.
func fingerprint(_ bytes: UnsafeRawBufferPointer) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
    return String(hash, radix: 16)
}

let cases: [(name: String, configure: (inout MatrixSettings) -> Void)] = [
    ("defaults", { _ in }),
    ("stepped", { $0.glidingMotion = false }),
    ("no bright heads", { $0.brightHeads = false }),
    ("stepped, no bright heads", { $0.glidingMotion = false; $0.brightHeads = false }),
    ("no fade", { $0.fadeTrails = false }),
    ("no glow, no blend", { $0.glow = false; $0.blendColors = false }),
    ("rainbow spectrum", { $0.color = .rainbowSpectrum }),
    ("rainbow", { $0.color = .rainbow }),
    ("matrix green, stepped", { $0.color = .matrixGreen; $0.glidingMotion = false }),
    ("katakana, fallback fonts", { $0.glyphStyle = .katakana; $0.fontName = "Menlo-Regular" }),
    ("katakana enhanced, mirrored", { $0.glyphStyle = .katakanaEnhanced }),
    ("unicode, mixed fallbacks", { $0.glyphStyle = .unicode }),
]
let size = CGSize(width: 1000, height: 640)
let scale = 2
let checkpoints = [90, 300, 600]   // frames

for testCase in cases {
    var settings = MatrixSettings()
    testCase.configure(&settings)
    let scene = MatrixScene(settings: settings, seed: 1234)
    scene.simulation(for: size)
    let width = Int(size.width) * scale, height = Int(size.height) * scale
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("could not create bitmap context") }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    var frame = 0
    var hashes: [String] = []
    for checkpoint in checkpoints {
        while frame < checkpoint {
            scene.advance(by: MatrixScene.frameInterval)
            frame += 1
        }
        scene.draw(in: context, size: size)
        hashes.append(fingerprint(UnsafeRawBufferPointer(start: context.data, count: width * height * 4)))
    }
    print(testCase.name.padding(toLength: 28, withPad: " ", startingAt: 0), hashes.joined(separator: " "))
}
