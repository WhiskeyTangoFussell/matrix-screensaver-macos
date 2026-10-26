/// Which characters rain down. Raw values are persisted, so don't rename them.
enum GlyphStyle: String, CaseIterable, Sendable {
    case classic, hex, binary, unicode, katakana, mixed, katakanaEnhanced, katakanaFilm

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .hex: "Hexadecimal"
        case .binary: "Binary"
        case .katakana: "Katakana"
        case .mixed: "Katakana (Combined)"
        case .katakanaEnhanced: "Katakana (Enhanced)"
        case .katakanaFilm: "Katakana (Film)"
        case .unicode: "Unicode"
        }
    }

    var characters: [Character] {
        switch self {
        case .classic: Self.printableASCII
        case .katakana: Self.halfWidthKatakana + Self.digits
        case .mixed: Self.halfWidthKatakana + Self.digits + Self.latinCapitals + Self.symbols
        case .katakanaEnhanced: Self.halfWidthKatakana + Self.digits
        case .katakanaFilm: Self.digits + Self.symbols
        case .unicode: Self.worldLetters + Self.halfWidthKatakana + Self.digits
        case .binary: Array("01")
        case .hex: Self.digits + Array("ABCDEF")
        }
    }

    /// Characters drawn flipped left-to-right, in addition to `characters`.
    /// Enhanced shows katakana both ways; Film mirrors them all, like the movie.
    var mirroredCharacters: [Character] {
        switch self {
        case .katakanaEnhanced, .katakanaFilm: Self.halfWidthKatakana
        default: []
        }
    }

    private static let printableASCII = (33...126).compactMap { Unicode.Scalar($0).map(Character.init) }
    private static let halfWidthKatakana = (0xFF66...0xFF9D).compactMap { Unicode.Scalar($0).map(Character.init) }
    /// Letters from Latin (accented), Greek, Cyrillic, Hebrew, Arabic, Armenian,
    /// Georgian and Runic. Only standalone letters are kept: combining marks and
    /// vowel signs can't stand alone in a cell. Wide CJK/Hangul are left out
    /// because the widest glyph sets every column's pitch.
    private static let worldLetters: [Character] = [
        0xC0...0x17F,     // Latin-1 Supplement + Latin Extended-A
        0x391...0x3C9,    // Greek
        0x400...0x45F,    // Cyrillic
        0x5D0...0x5EA,    // Hebrew
        0x621...0x64A,    // Arabic
        0x531...0x586,    // Armenian
        0x10D0...0x10FA,  // Georgian
        0x16A0...0x16EA,  // Runic
    ].flatMap { $0 }.compactMap(Unicode.Scalar.init).filter {
        switch $0.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .otherLetter: true
        default: false
        }
    }.map(Character.init)
    private static let digits = Array("0123456789")
    private static let latinCapitals = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let symbols = Array(":.\"=*+-<>|¦")
}
