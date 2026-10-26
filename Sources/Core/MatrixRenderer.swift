import CoreGraphics
import CoreText

/// Draws a `RainSimulation` into any `CGContext`.
///
/// Each stream is drawn as a few runs of consecutive same-shade glyphs, one
/// `CTFontDrawGlyphs` call per run. Batching by stream rather than by color
/// matters: Core Graphics composites a call through a bitmap covering all of
/// its glyphs, so a screen-wide batch costs a screen-sized copy. Some fonts
/// (e.g. CaskaydiaCove) made that 70+ ms per frame; per-stream runs stay small.
final class MatrixRenderer {
    let atlas: GlyphAtlas
    private let settings: MatrixSettings

    /// Trail brightness steps; palette index `levels` is the head.
    private static let levels = 10
    /// Hue bins used by rainbow mode and blended spectra.
    private static let rainbowBins = 24
    private static let spectrumBins = 24
    private static let background = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    /// How a stream's cells pick their color bin.
    private enum Coloring { case single, rainbow, perStream, spectrum }

    private let coloring: Coloring
    private let colorBins: Int
    private let palette: [[CGColor]]   // [colorBin][level]
    private let glowSprites: [CGImage] // [colorBin]; empty when glow is off

    // Scratch buffers for the run being built, reused across frames.
    private var runGlyphs: [CGGlyph] = []
    private var runPositions: [CGPoint] = []

    init(settings: MatrixSettings, scale: CGFloat) {
        self.settings = settings
        let fontSize = CGFloat(settings.fontSize) * scale
        atlas = GlyphAtlas(style: settings.glyphStyle, fontName: settings.fontName, size: max(fontSize, 3))

        // `bases` holds each bin's representative color (also used for its glow).
        let bases: [RGB]
        let head = settings.color.headColor
        switch settings.color.scheme {
        case .solid(let rgb):
            coloring = .single
            bases = [rgb]
            palette = [Self.shades(of: rgb, head: head)]
        case .rainbow:
            coloring = .rainbow
            bases = (0..<Self.rainbowBins).map { RGB.hue(CGFloat($0) / CGFloat(Self.rainbowBins)) }
            palette = bases.map { Self.shades(of: $0, head: head) }
        case .families(let families) where settings.blendColors:
            coloring = .spectrum
            let hues = (0..<Self.spectrumBins).map { CGFloat($0) / CGFloat(Self.spectrumBins - 1) }
            bases = hues.map { families.sample(hue: $0, shade: 0.5) }
            palette = hues.map { Self.spectrumShades(of: families, hue: $0, head: head) }
        case .families(let families):
            coloring = .perStream
            bases = families.flatMap { $0 }
            palette = bases.map { Self.shades(of: $0, head: head) }
        }
        colorBins = palette.count
        glowSprites = settings.glow ? bases.compactMap(Self.glowSprite) : []
    }

    /// Only whole cells fit, so no glyph is ever clipped at a screen edge; the
    /// leftover space is split evenly as margins (see `draw`).
    func gridSize(for size: CGSize) -> (columns: Int, rows: Int) {
        (max(1, Int(size.width / atlas.cellWidth)),
         max(1, Int(size.height / atlas.cellHeight)))
    }

    func draw(_ simulation: RainSimulation, in context: CGContext, size: CGSize, time: Double) {
        context.setFillColor(Self.background)
        context.fill(CGRect(origin: .zero, size: size))

        // Center the grid: x of column 0's left edge, y of row 0's top edge.
        let xOrigin = (size.width - CGFloat(simulation.columns) * atlas.cellWidth) / 2
        let top = size.height - (size.height - CGFloat(simulation.rows) * atlas.cellHeight) / 2
        // Halos go down in their own pass so no glyph is ever covered by one.
        if glowSprites.count == colorBins {
            drawGlows(simulation, in: context, xOrigin: xOrigin, top: top, time: time)
        }

        context.saveGState()
        context.textMatrix = .identity
        for (c, lane) in simulation.lanes.enumerated() {
            let x = xOrigin + CGFloat(c) * atlas.cellWidth
            for stream in lane.streams {
                drawStream(stream, column: c, x: x, simulation, in: context, top: top, time: time)
            }
        }
        context.restoreGState()
    }

    // MARK: - Private

    private func drawStream(_ stream: RainStream, column c: Int, x: CGFloat,
                            _ simulation: RainSimulation, in context: CGContext, top: CGFloat, time: Double) {
        var runLevel = -1
        var runFont = -1
        var runBin = -1

        func position(of entry: GlyphAtlas.Entry, row: Int) -> CGPoint {
            CGPoint(x: x + (atlas.cellWidth - entry.advance) / 2 + entry.xOffset,
                    y: top - CGFloat(row + 1) * atlas.cellHeight + atlas.baseline)
        }

        func emit(level: Int, bin: Int, row: Int) {
            let entry = atlas.entries[simulation.glyph(column: c, row: row)]
            if level != runLevel || entry.fontIndex != runFont || bin != runBin {
                flushRun(font: runFont, color: runLevel >= 0 ? palette[runBin][runLevel] : nil, in: context)
                runLevel = level
                runFont = entry.fontIndex
                runBin = bin
            }
            runGlyphs.append(entry.glyph)
            runPositions.append(position(of: entry, row: row))
        }

        func bin(_ distance: Int) -> Int {
            colorBin(column: c, of: simulation.columns, stream: stream, distance: distance, time: time)
        }

        /// One glyph drawn at partial opacity, for the gliding head's crossfade.
        func fade(row: Int, color: CGColor, alpha: CGFloat) {
            guard (0..<simulation.rows).contains(row), alpha > 0.01 else { return }
            let entry = atlas.entries[simulation.glyph(column: c, row: row)]
            var glyph = entry.glyph
            var point = position(of: entry, row: row)
            context.setAlpha(alpha)
            context.setFillColor(color)
            CTFontDrawGlyphs(atlas.fonts[entry.fontIndex], &glyph, &point, 1, context)
            context.setAlpha(1)
        }

        if settings.glidingMotion {
            // Characters stay in their cells; only the light moves. Trail
            // brightness follows the fractional head, and the head itself
            // crossfades from the cell it's leaving into the next one.
            let head = stream.head
            let headRow = Int(head.rounded(.down))
            let progress = CGFloat(head - Double(headRow))
            let lowest = min(headRow, simulation.rows - 1)
            let highest = max(0, headRow - stream.length + 1)
            if headRow >= 0 && lowest >= highest {
                for row in highest...lowest {
                    let distance = head - Double(row)
                    emit(level: trailLevel(distance: distance, length: stream.length), bin: bin(Int(distance)), row: row)
                }
            }
            if runLevel >= 0 {
                flushRun(font: runFont, color: palette[runBin][runLevel], in: context)
            }
            let headColor = palette[bin(0)][settings.brightHeads ? Self.levels : Self.levels - 1]
            if settings.brightHeads {
                fade(row: headRow, color: headColor, alpha: 1 - progress)
            }
            fade(row: headRow + 1, color: headColor, alpha: progress)
        } else {
            let head = stream.litHead
            let lowest = min(head, simulation.rows - 1)
            let highest = max(0, head - stream.length + 1)
            guard head >= 0, lowest >= highest else { return }
            for row in highest...lowest {
                let distance = head - row
                emit(level: level(distance: distance, length: stream.length), bin: bin(distance), row: row)
            }
            flushRun(font: runFont, color: palette[runBin][runLevel], in: context)
        }
    }

    private func flushRun(font: Int, color: CGColor?, in context: CGContext) {
        guard let color, !runGlyphs.isEmpty else { return }
        context.setFillColor(color)
        CTFontDrawGlyphs(atlas.fonts[font], runGlyphs, runPositions, runGlyphs.count, context)
        runGlyphs.removeAll(keepingCapacity: true)
        runPositions.removeAll(keepingCapacity: true)
    }

    private func drawGlows(_ simulation: RainSimulation, in context: CGContext,
                           xOrigin: CGFloat, top: CGFloat, time: Double) {
        let glowSize = CGSize(width: atlas.cellWidth * 1.6, height: atlas.cellHeight * 1.6)
        for (c, lane) in simulation.lanes.enumerated() {
            let centerX = xOrigin + (CGFloat(c) + 0.5) * atlas.cellWidth
            for stream in lane.streams {
                let headRow: Double
                if settings.glidingMotion {
                    // The crossfading head's center of mass is exactly `head`
                    // ((1 − p)·cell h + p·cell h+1), so the halo glides with it.
                    guard stream.head > -1 && stream.head < Double(simulation.rows) else { continue }
                    headRow = stream.head
                } else {
                    guard (0..<simulation.rows).contains(stream.litHead) else { continue }
                    headRow = Double(stream.litHead)
                }
                let centerY = top - (CGFloat(headRow) + 0.5) * atlas.cellHeight
                let colorBin = colorBin(column: c, of: simulation.columns, stream: stream, distance: 0, time: time)
                let rect = CGRect(x: centerX - glowSize.width / 2, y: centerY - glowSize.height / 2,
                                  width: glowSize.width, height: glowSize.height)
                context.draw(glowSprites[colorBin], in: rect)
            }
        }
    }

    /// Trail palette level for a (possibly fractional) distance behind the head.
    private func trailLevel(distance: Double, length: Int) -> Int {
        guard settings.fadeTrails else { return Self.levels - 1 }
        let brightness = 1 - distance / Double(length)
        return (Int((brightness * Double(Self.levels)).rounded(.up)) - 1).clamped(to: 0...(Self.levels - 1))
    }

    /// Stepped mode: the head cell gets the head color, the rest the trail.
    private func level(distance: Int, length: Int) -> Int {
        if distance == 0 && settings.brightHeads { return Self.levels }
        return trailLevel(distance: Double(distance), length: length)
    }

    private func colorBin(column: Int, of columns: Int, stream: RainStream, distance: Int, time: Double) -> Int {
        switch coloring {
        case .single:
            return 0
        case .rainbow:
            let hue = Double(column) / Double(columns) + time * 0.04
            return Int((hue - hue.rounded(.down)) * Double(colorBins)) % colorBins
        case .perStream:
            return Int(stream.variant) % colorBins
        case .spectrum:
            // Each stream sweeps the whole spectrum head → tail, starting at a
            // random point and direction and bouncing off the ends, so
            // neighboring streams show different slices of it.
            let start = Double(stream.variant & 0xFF) / 255
            let direction: Double = stream.variant & 0x100 == 0 ? 1 : -1
            let t = start + direction * Double(distance) / Double(max(stream.length - 1, 1))
            let wrapped = t - 2 * (t / 2).rounded(.down)            // 0..<2
            let position = wrapped <= 1 ? wrapped : 2 - wrapped      // ping-pong 0...1
            return Int((position * Double(colorBins - 1)).rounded())
        }
    }

    /// A soft radial halo in `base`, pre-rendered once so drawing a glow costs
    /// one image blit per head instead of a per-glyph Gaussian blur.
    private static func glowSprite(_ base: RGB) -> CGImage? {
        let side = 64
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let colors = [base.cgColor(alpha: 0.55), base.cgColor(alpha: 0.18), base.cgColor(alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.45, 1]) else { return nil }
        let center = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: CGFloat(side) / 2, options: [])
        return context.makeImage()
    }

    /// Trail shades for one point of a blended spectrum: light near the head,
    /// the family's dark shade toward the tail, plus a gentler brightness fade
    /// since the dark shades already carry most of the depth.
    private static func spectrumShades(of families: [[RGB]], hue: CGFloat, head: RGB) -> [CGColor] {
        var colors = (0..<levels).map { level -> CGColor in
            let t = CGFloat(level + 1) / CGFloat(levels)
            return families.sample(hue: hue, shade: 1 - t).scaled(by: 0.35 + 0.65 * t).cgColor
        }
        colors.append(head.cgColor)
        return colors
    }

    /// Trail shades from dim to bright, followed by the head color.
    private static func shades(of base: RGB, head: RGB) -> [CGColor] {
        var colors = (0..<levels).map { level -> CGColor in
            let t = CGFloat(level + 1) / CGFloat(levels)
            var rgb = base.scaled(by: 0.15 + 0.85 * t)
            if t > 0.85 { rgb = rgb.mixed(with: .white, amount: 0.2) }   // hot zone just behind the head
            return rgb.cgColor
        }
        colors.append(head.cgColor)
        return colors
    }
}
