/// Which characters rain down. Raw values are persisted, so don't rename them.
enum GlyphStyle: String, CaseIterable, Sendable {
    case classic, katakana, mixed, binary, hex

    var displayName: String {
        switch self {
        case .classic: "Classic ASCII (cmatrix)"
        case .katakana: "Katakana"
        case .mixed: "Katakana + Latin"
        case .binary: "Binary"
        case .hex: "Hexadecimal"
        }
    }

    var characters: [Character] {
        switch self {
        case .classic: Self.printableASCII
        case .katakana: Self.halfWidthKatakana + Self.digits
        case .mixed: Self.halfWidthKatakana + Self.digits + Self.latinCapitals + Self.symbols
        case .binary: Array("01")
        case .hex: Self.digits + Array("ABCDEF")
        }
    }

    private static let printableASCII = (33...126).compactMap { Unicode.Scalar($0).map(Character.init) }
    private static let halfWidthKatakana = (0xFF66...0xFF9D).compactMap { Unicode.Scalar($0).map(Character.init) }
    private static let digits = Array("0123456789")
    private static let latinCapitals = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let symbols = Array(":.\"=*+-<>|¦")
}
