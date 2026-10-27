import Foundation

/// Every user-adjustable option, plus the mapping from friendly 1–10 slider
/// values to the physical quantities the simulation and renderer use.
struct MatrixSettings: Equatable, Sendable {
    /// Sentinel font name meaning "the system monospaced font (SF Mono)".
    static let systemMonospacedFontName = "System Monospaced"

    var fontName = "CaskaydiaCoveNF-Bold"   // falls back to SF Mono if not installed
    var fontSize: Double = 16          // points, 8...48
    var speed: Double = 4              // 1...10
    var density: Double = 4.5          // 1...10, steps of 0.5
    var trailLength: Double = 5        // 1...10
    var mutationRate: Double = 3       // 0...10
    var color: MatrixColor = .tokyoNight
    var glyphStyle: GlyphStyle = .classic
    var brightHeads = true             // white leading glyph (cmatrix -b)
    var fadeTrails = true              // tail dims toward black
    var lengthVariance: Double = 50    // ±% around the trail length, 0...100
    var speedSpread: Double = 150      // +% above the base speed, 0...300 (cmatrix -a)
    var glow = true                    // soft bloom around heads
    var blendColors = true             // multi-color schemes: gradient along each stream
    var glidingMotion = true           // light glides smoothly over fixed characters; off = cmatrix row steps
    var frameRate = 30                 // frames per second, one of `frameRates`

    static let fontSizeRange: ClosedRange<Double> = 8...48
    static let levelRange: ClosedRange<Double> = 1...10
    static let mutationRange: ClosedRange<Double> = 0...10
    static let varianceRange: ClosedRange<Double> = 0...100
    static let spreadRange: ClosedRange<Double> = 0...300
    static let frameRates = [30, 60]
}

// MARK: - Derived simulation values

extension MatrixSettings {
    /// How many rows per second a stream's head travels at speed factor 1.
    /// Exponential so the slow end has fine control: 1 → 3, 4 ≈ 7, 10 → 40.
    var rowsPerSecond: Double { 3 * pow(40.0 / 3, (speed - 1) / 9) }

    /// Mean seconds a column waits before launching its next stream.
    /// The wait only starts once the previous stream has cleared the top row,
    /// so this sets the size of the dark gaps between streams.
    /// Exponential mapping: density 1 ≈ 8 s, density 10 ≈ 0.15 s.
    var meanSpawnInterval: Double {
        let t = (density - 1) / 9
        return 8 * pow(0.15 / 8, t)
    }

    /// Mean trail length as a fraction of the screen height.
    var meanTrailFraction: Double { 0.08 + (trailLength - 1) / 9 * 0.6 }

    /// Range a stream's length multiplier is drawn from, e.g. 50% → 0.5...1.5.
    var lengthFactorRange: ClosedRange<Double> { Self.factorRange(variance: lengthVariance) }

    /// Range a stream's speed multiplier is drawn from. The base speed is the
    /// floor, so spread only ever adds speed: 150% → 1.0...2.5.
    var speedFactorRange: ClosedRange<Double> { 1...(1 + speedSpread.clamped(to: Self.spreadRange) / 100) }

    /// Keeps the low end above zero so 100% never yields frozen or empty streams.
    private static func factorRange(variance: Double) -> ClosedRange<Double> {
        let v = variance.clamped(to: varianceRange) / 100
        return max(1 - v, 0.15)...(1 + v)
    }

    /// Seconds between frames. Motion is time-based, so this only affects
    /// smoothness (and CPU use), not speed.
    var frameInterval: Double { 1 / Double(frameRate) }

    /// Probability per second that any single cell swaps to a new glyph.
    var mutationsPerCellPerSecond: Double { mutationRate * 0.05 }
}

// MARK: - Persistence

extension MatrixSettings {
    private enum Key {
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let speed = "speed"
        static let density = "density"
        static let trailLength = "trailLength"
        static let mutationRate = "mutationRate"
        static let color = "color"
        static let glyphStyle = "glyphStyle"
        static let brightHeads = "brightHeads"
        static let fadeTrails = "fadeTrails"
        static let lengthVariance = "lengthVariance"
        static let speedSpread = "speedSpread"
        static let glow = "glow"
        static let blendColors = "blendColors"
        static let glidingMotion = "glidingMotion"
        static let frameRate = "frameRate"
    }

    /// Reads settings, falling back to defaults for missing or invalid values.
    init(defaults: UserDefaults) {
        let fallback = MatrixSettings()
        func double(_ key: String, _ value: Double, in range: ClosedRange<Double>) -> Double {
            guard defaults.object(forKey: key) != nil else { return value }
            return defaults.double(forKey: key).clamped(to: range)
        }
        func bool(_ key: String, _ value: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
        }

        fontName = defaults.string(forKey: Key.fontName) ?? fallback.fontName
        fontSize = double(Key.fontSize, fallback.fontSize, in: Self.fontSizeRange)
        speed = double(Key.speed, fallback.speed, in: Self.levelRange)
        density = double(Key.density, fallback.density, in: Self.levelRange)
        trailLength = double(Key.trailLength, fallback.trailLength, in: Self.levelRange)
        mutationRate = double(Key.mutationRate, fallback.mutationRate, in: Self.mutationRange)
        color = defaults.string(forKey: Key.color).flatMap(MatrixColor.init) ?? fallback.color
        glyphStyle = defaults.string(forKey: Key.glyphStyle).flatMap(GlyphStyle.init) ?? fallback.glyphStyle
        brightHeads = bool(Key.brightHeads, fallback.brightHeads)
        fadeTrails = bool(Key.fadeTrails, fallback.fadeTrails)
        lengthVariance = double(Key.lengthVariance, fallback.lengthVariance, in: Self.varianceRange)
        speedSpread = double(Key.speedSpread, fallback.speedSpread, in: Self.spreadRange)
        glow = bool(Key.glow, fallback.glow)
        blendColors = bool(Key.blendColors, fallback.blendColors)
        glidingMotion = bool(Key.glidingMotion, fallback.glidingMotion)
        let savedRate = defaults.integer(forKey: Key.frameRate)
        frameRate = Self.frameRates.contains(savedRate) ? savedRate : fallback.frameRate
    }

    func save(to defaults: UserDefaults) {
        defaults.set(fontName, forKey: Key.fontName)
        defaults.set(fontSize, forKey: Key.fontSize)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(density, forKey: Key.density)
        defaults.set(trailLength, forKey: Key.trailLength)
        defaults.set(mutationRate, forKey: Key.mutationRate)
        defaults.set(color.rawValue, forKey: Key.color)
        defaults.set(glyphStyle.rawValue, forKey: Key.glyphStyle)
        defaults.set(brightHeads, forKey: Key.brightHeads)
        defaults.set(fadeTrails, forKey: Key.fadeTrails)
        defaults.set(lengthVariance, forKey: Key.lengthVariance)
        defaults.set(speedSpread, forKey: Key.speedSpread)
        defaults.set(glow, forKey: Key.glow)
        defaults.set(blendColors, forKey: Key.blendColors)
        defaults.set(glidingMotion, forKey: Key.glidingMotion)
        defaults.set(frameRate, forKey: Key.frameRate)
        defaults.synchronize()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
