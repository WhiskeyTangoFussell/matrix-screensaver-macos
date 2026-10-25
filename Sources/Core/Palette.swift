import CoreGraphics

/// A plain RGB triple in the 0...1 range (sRGB).
struct RGB: Equatable, Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    static let white = RGB(r: 1, g: 1, b: 1)

    init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(r: CGFloat((hex >> 16) & 0xFF) / 255,
                  g: CGFloat((hex >> 8) & 0xFF) / 255,
                  b: CGFloat(hex & 0xFF) / 255)
    }

    func mixed(with other: RGB, amount t: CGFloat) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func scaled(by k: CGFloat) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }

    var cgColor: CGColor { cgColor(alpha: 1) }

    func cgColor(alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    /// Fully saturated color for a hue in 0...1.
    static func hue(_ h: CGFloat) -> RGB {
        let h6 = (h - h.rounded(.down)) * 6
        let x = 1 - abs(h6.truncatingRemainder(dividingBy: 2) - 1)
        switch Int(h6) {
        case 0: return RGB(r: 1, g: x, b: 0)
        case 1: return RGB(r: x, g: 1, b: 0)
        case 2: return RGB(r: 0, g: 1, b: x)
        case 3: return RGB(r: 0, g: x, b: 1)
        case 4: return RGB(r: x, g: 0, b: 1)
        default: return RGB(r: 1, g: 0, b: x)
        }
    }
}

/// How a palette entry assigns colors to streams.
enum ColorScheme: Sendable {
    /// Every stream uses the same color.
    case solid(RGB)
    /// Hue sweeps across the columns and slowly cycles over time.
    case rainbow
    /// Hue families, each ordered light → medium → dark. Streams either pick
    /// one color at random or blend across all of them (`blendColors`).
    case families([[RGB]])
}

extension [[RGB]] {
    /// Bilinear sample of a family grid: `hue` 0...1 runs from the first family
    /// to the last, `shade` 0...1 runs from light to dark within a family.
    func sample(hue: CGFloat, shade: CGFloat) -> RGB {
        func lerp(_ colors: [RGB], _ t: CGFloat) -> RGB {
            let position = t.clamped(to: 0...1) * CGFloat(colors.count - 1)
            let i = Swift.min(Int(position), colors.count - 2)
            return colors.count == 1 ? colors[0] : colors[i].mixed(with: colors[i + 1], amount: position - CGFloat(i))
        }
        return lerp(map { lerp($0, shade) }, hue)
    }
}

/// The rain color palette. Raw values are persisted, so don't rename them.
enum MatrixColor: String, CaseIterable, Sendable {
    case tokyoNight, rainbowSpectrum
    case matrixGreen, emerald, lime, mint, cyan, iceBlue, azure, violet
    case magenta, pink, red, orange, amber, gold, white, rainbow

    var displayName: String {
        switch self {
        case .tokyoNight: "Tokyo Night (Neon)"
        case .rainbowSpectrum: "Rainbow Spectrum (Pastel)"
        case .matrixGreen: "Matrix Green"
        case .emerald: "Emerald"
        case .lime: "Lime"
        case .mint: "Mint"
        case .cyan: "Cyan"
        case .iceBlue: "Ice Blue"
        case .azure: "Azure"
        case .violet: "Violet"
        case .magenta: "Magenta"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .amber: "Amber"
        case .gold: "Gold"
        case .white: "White"
        case .rainbow: "Rainbow"
        }
    }

    var scheme: ColorScheme {
        switch self {
        case .tokyoNight: .families(Self.tokyoNightNeon)
        case .rainbowSpectrum: .families(Self.pastelRainbow)
        case .rainbow: .rainbow
        case .matrixGreen: .solid(RGB(r: 0.00, g: 1.00, b: 0.25))
        case .emerald: .solid(RGB(r: 0.05, g: 0.80, b: 0.45))
        case .lime: .solid(RGB(r: 0.65, g: 1.00, b: 0.10))
        case .mint: .solid(RGB(r: 0.55, g: 1.00, b: 0.75))
        case .cyan: .solid(RGB(r: 0.00, g: 0.95, b: 1.00))
        case .iceBlue: .solid(RGB(r: 0.60, g: 0.85, b: 1.00))
        case .azure: .solid(RGB(r: 0.15, g: 0.45, b: 1.00))
        case .violet: .solid(RGB(r: 0.60, g: 0.30, b: 1.00))
        case .magenta: .solid(RGB(r: 1.00, g: 0.15, b: 0.90))
        case .pink: .solid(RGB(r: 1.00, g: 0.45, b: 0.70))
        case .red: .solid(RGB(r: 1.00, g: 0.12, b: 0.12))
        case .orange: .solid(RGB(r: 1.00, g: 0.50, b: 0.05))
        case .amber: .solid(RGB(r: 1.00, g: 0.72, b: 0.00))
        case .gold: .solid(RGB(r: 1.00, g: 0.88, b: 0.35))
        case .white: .solid(RGB(r: 0.92, g: 0.92, b: 0.92))
        }
    }

    /// The full rainbow (red → orange → yellow → green → cyan → blue → violet →
    /// magenta), softened toward pastel by mixing in white. Each family is
    /// light/medium/dark like the Tokyo Night set.
    static let pastelRainbow: [[RGB]] = [0, 30, 55, 120, 185, 220, 270, 315].map { degrees in
        let hue = RGB.hue(CGFloat(degrees) / 360)
        return [
            hue.mixed(with: .white, amount: 0.6),
            hue.mixed(with: .white, amount: 0.4),
            hue.mixed(with: .white, amount: 0.25).scaled(by: 0.75),
        ]
    }

    /// Neon pink, purple and blue in light/medium/dark shades, built around
    /// the Tokyo Night editor theme's accent colors (#f7768e, #bb9af7, #7aa2f7).
    static let tokyoNightNeon: [[RGB]] = [
        [RGB(hex: 0xFF9ED8), RGB(hex: 0xFF4FAE), RGB(hex: 0xC2187A)],   // pink
        [RGB(hex: 0xCDA8FF), RGB(hex: 0xA25CFF), RGB(hex: 0x6C2BD9)],   // purple
        [RGB(hex: 0x8CD5FF), RGB(hex: 0x4D8DFF), RGB(hex: 0x2A52D6)],   // blue
    ]
}
