import AppKit
import CoreText

/// Resolves a glyph style's characters to Core Text glyphs, pulling in
/// fallback fonts for characters the chosen font lacks (e.g. katakana in Menlo).
struct GlyphAtlas {
    struct Entry {
        var fontIndex: Int
        var glyph: CGGlyph
        var advance: CGFloat
        /// Mirrored glyphs draw leftward from their origin, so they're
        /// positioned one advance further right.
        var xOffset: CGFloat = 0
    }

    /// `fonts[0]` is the primary font; the rest are fallbacks.
    let fonts: [CTFont]
    let entries: [Entry]
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    /// Offset from the bottom of a cell to the text baseline.
    let baseline: CGFloat

    /// Horizontal pitch between columns, in glyph widths. cmatrix leaves a
    /// blank terminal column between streams; 1.5 keeps that airy look
    /// without wasting as much space.
    private static let columnPitch: CGFloat = 1.5

    init(style: GlyphStyle, fontName: String, size: CGFloat) {
        let primary = Self.makeFont(named: fontName, size: size)
        var fonts = [primary]
        var mirroredIndex: [Int: Int] = [:]   // font index → its mirrored copy
        var entries: [Entry] = []

        // Fallback glyphs much wider than the primary font's would widen every
        // column (the widest glyph sets the pitch), so they're skipped.
        let maxFallbackAdvance = (Self.entry(for: "0", in: primary, fontIndex: 0)?.advance ?? size * 0.6) * 1.25

        func resolve(_ character: Character) -> Entry? {
            let text = String(character)
            if let entry = Self.entry(for: text, in: primary, fontIndex: 0) {
                return entry
            }
            let fallback = CTFontCreateForString(primary, text as CFString, CFRange(location: 0, length: text.utf16.count))
            let name = CTFontCopyPostScriptName(fallback) as String
            // LastResort draws a "missing character" box; better to leave it out.
            guard name != "LastResort" else { return nil }
            let index = fonts.firstIndex { CTFontCopyPostScriptName($0) as String == name } ?? {
                fonts.append(fallback)
                return fonts.count - 1
            }()
            return Self.entry(for: text, in: fonts[index], fontIndex: index)
                .flatMap { $0.advance <= maxFallbackAdvance ? $0 : nil }
        }

        entries = style.characters.compactMap(resolve)
        for character in style.mirroredCharacters {
            guard var entry = resolve(character) else { continue }
            let index = mirroredIndex[entry.fontIndex] ?? {
                var flip = CGAffineTransform(scaleX: -1, y: 1)
                fonts.append(CTFontCreateCopyWithAttributes(fonts[entry.fontIndex], 0, &flip, nil))
                mirroredIndex[entry.fontIndex] = fonts.count - 1
                return fonts.count - 1
            }()
            entry.fontIndex = index
            entry.xOffset = entry.advance
            entries.append(entry)
        }
        if entries.isEmpty, let zero = Self.entry(for: "0", in: primary, fontIndex: 0) {
            entries = [zero]
        }

        let ascent = fonts.map(CTFontGetAscent).max() ?? size
        let descent = fonts.map(CTFontGetDescent).max() ?? 0
        let widest = entries.map(\.advance).max() ?? size * 0.6

        self.fonts = fonts
        self.entries = entries
        cellWidth = (widest * Self.columnPitch).rounded(.up)
        cellHeight = (ascent + descent).rounded(.up)
        baseline = descent
    }

    private static func makeFont(named name: String, size: CGFloat) -> CTFont {
        if name != MatrixSettings.systemMonospacedFontName, let font = NSFont(name: name, size: size) {
            return font as CTFont
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
    }

    private static func entry(for text: String, in font: CTFont, fontIndex: Int) -> Entry? {
        var units = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), glyphs[0] != 0 else {
            return nil
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
        return Entry(fontIndex: fontIndex, glyph: glyphs[0], advance: advance.width)
    }
}
