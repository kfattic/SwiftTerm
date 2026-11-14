//
//  TerminalTheme.swift
//  SwiftTerm
//
//  A terminal look as plain data: colors, the 16 ANSI colors, font, cursor and
//  a few rendering choices. Themes can be stored (Codable), read from and
//  written to iTerm2 `.itermcolors` files here, and to Apple Terminal
//  `.terminal` files on macOS (see TerminalTheme+Mac.swift).
//

#if !SWIFTTERM_EMBEDDED
import Foundation

/// An sRGB color with alpha, each component from 0 to 1 in steps of 1/255.
///
/// It is stored as a `#RRGGBB` or `#RRGGBBAA` string, so saved themes are easy
/// to read and edit. Components are rounded to 8 bits, so a color reads back
/// exactly as it was stored.
public struct TerminalThemeColor: Hashable, Sendable, Codable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init (red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA`; the `#` is optional.
    public init? (hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(digits, radix: 16) else {
            return nil
        }
        let rgb = digits.count == 8 ? value >> 8 : value
        let alpha = digits.count == 8 ? Double(value & 0xff) / 255 : 1
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255,
                  alpha: alpha)
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the color is not opaque.
    public var hex: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return byte(alpha) == 255 ? rgb : rgb + String(format: "%02X", byte(alpha))
    }

    public var description: String { hex }

    /// The color as a SwiftTerm palette color (alpha is dropped).
    public var terminalColor: Color {
        Color(red: UInt16((red * 65535).rounded()),
              green: UInt16((green * 65535).rounded()),
              blue: UInt16((blue * 65535).rounded()))
    }

    /// The same color with another alpha.
    public func withAlpha (_ alpha: Double) -> TerminalThemeColor {
        TerminalThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public init (from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = TerminalThemeColor(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "\"\(text)\" is not a #RRGGBB or #RRGGBBAA color")
        }
        self = color
    }

    public func encode (to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    private static func clamp (_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(1, max(0, value)) * 255).rounded() / 255
    }
}

/// A complete terminal look: the default colors, the 16 ANSI colors, the
/// font, the cursor and how text is drawn.
///
/// A theme is plain data. Apply it to a view with
/// `TerminalView.apply(theme:)` (macOS), keep it with `Codable`, and read or
/// write the formats other terminals use:
///
/// - iTerm2 `.itermcolors`: ``init(itermColors:name:base:)`` and ``itermColorsData()``
/// - Apple Terminal `.terminal` (macOS): `init(terminalProfile:)` and `terminalProfileData()`
///
/// ```swift
/// terminalView.apply(theme: .solarizedDark)
///
/// let data = try Data(contentsOf: url)
/// let theme = try TerminalTheme(itermColors: data, name: "My Colors")
/// ```
public struct TerminalTheme: Hashable, Sendable, Codable {
    /// The name shown to people.
    public var name: String
    /// The color of text with no explicit color.
    public var foreground: TerminalThemeColor
    /// The color behind text with no explicit background color.
    public var background: TerminalThemeColor
    /// How opaque the background is, from 0 to 1. Text stays opaque.
    public var backgroundOpacity: Double
    /// The color of bold text in the default foreground color, or `nil` to use `foreground`.
    public var boldForeground: TerminalThemeColor?
    /// The cursor color, or `nil` for the view's default.
    public var cursor: TerminalThemeColor?
    /// The color of the text under a block cursor, or `nil` for the view's default.
    public var cursorText: TerminalThemeColor?
    /// The selection color, or `nil` for the view's default. Its alpha is kept.
    public var selection: TerminalThemeColor?
    /// The color of selected text, or `nil` for the view's default.
    public var selectionForeground: TerminalThemeColor?
    /// The 16 ANSI colors: black, red, green, yellow, blue, magenta, cyan,
    /// white, then their bright versions.
    public var ansi: [TerminalThemeColor]
    /// The PostScript name of the font, or `nil` to keep the view's font.
    public var fontName: String?
    /// The font size in points, or `nil` to keep the view's size.
    public var fontSize: Double?
    /// The cursor shape and blink, or `nil` to keep the terminal's.
    public var cursorStyle: CursorStyle?
    /// Draw bold text with the font's bold face; see `TerminalView.useBoldFonts`.
    public var useBoldFonts: Bool
    /// Draw text with antialiasing; see `TerminalView.textAntialiasing`.
    public var textAntialiasing: Bool

    public init (name: String,
                 foreground: TerminalThemeColor,
                 background: TerminalThemeColor,
                 backgroundOpacity: Double = 1,
                 boldForeground: TerminalThemeColor? = nil,
                 cursor: TerminalThemeColor? = nil,
                 cursorText: TerminalThemeColor? = nil,
                 selection: TerminalThemeColor? = nil,
                 selectionForeground: TerminalThemeColor? = nil,
                 ansi: [TerminalThemeColor] = TerminalTheme.terminalAppANSI,
                 fontName: String? = nil,
                 fontSize: Double? = nil,
                 cursorStyle: CursorStyle? = nil,
                 useBoldFonts: Bool = true,
                 textAntialiasing: Bool = true)
    {
        self.name = name
        self.foreground = foreground
        self.background = background.withAlpha(1)
        self.backgroundOpacity = Self.clampOpacity(backgroundOpacity)
        self.boldForeground = boldForeground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selection = selection
        self.selectionForeground = selectionForeground
        self.ansi = Self.normalized(ansi)
        self.fontName = fontName
        self.fontSize = fontSize
        self.cursorStyle = cursorStyle
        self.useBoldFonts = useBoldFonts
        self.textAntialiasing = textAntialiasing
    }

    /// Pads a short palette with Terminal.app's colors and drops extra entries.
    static func normalized (_ ansi: [TerminalThemeColor]) -> [TerminalThemeColor] {
        (0..<16).map { $0 < ansi.count ? ansi[$0] : terminalAppANSI[$0] }
    }

    /// Clamped to 0...1 and rounded to whole percent, as Terminal.app shows
    /// it: files store the opacity as an 8-bit or 32-bit alpha, which would
    /// not read back as the value it came from.
    static func clampOpacity (_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return (min(1, max(0, value)) * 100).rounded() / 100
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case name, foreground, background, backgroundOpacity, boldForeground, cursor, cursorText,
             selection, selectionForeground, ansi, fontName, fontSize, cursorStyle, useBoldFonts,
             textAntialiasing
    }

    /// Missing optional values take their defaults, so themes saved by an
    /// older version keep loading.
    public init (from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cursorStyleName = try c.decodeIfPresent(String.self, forKey: .cursorStyle)
        self.init(name: try c.decode(String.self, forKey: .name),
                  foreground: try c.decode(TerminalThemeColor.self, forKey: .foreground),
                  background: try c.decode(TerminalThemeColor.self, forKey: .background),
                  backgroundOpacity: try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1,
                  boldForeground: try c.decodeIfPresent(TerminalThemeColor.self, forKey: .boldForeground),
                  cursor: try c.decodeIfPresent(TerminalThemeColor.self, forKey: .cursor),
                  cursorText: try c.decodeIfPresent(TerminalThemeColor.self, forKey: .cursorText),
                  selection: try c.decodeIfPresent(TerminalThemeColor.self, forKey: .selection),
                  selectionForeground: try c.decodeIfPresent(TerminalThemeColor.self, forKey: .selectionForeground),
                  ansi: try c.decodeIfPresent([TerminalThemeColor].self, forKey: .ansi) ?? Self.terminalAppANSI,
                  fontName: try c.decodeIfPresent(String.self, forKey: .fontName),
                  fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize),
                  cursorStyle: cursorStyleName.flatMap(CursorStyle.init(tagName:)),
                  useBoldFonts: try c.decodeIfPresent(Bool.self, forKey: .useBoldFonts) ?? true,
                  textAntialiasing: try c.decodeIfPresent(Bool.self, forKey: .textAntialiasing) ?? true)
    }

    public func encode (to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(foreground, forKey: .foreground)
        try c.encode(background, forKey: .background)
        try c.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try c.encodeIfPresent(boldForeground, forKey: .boldForeground)
        try c.encodeIfPresent(cursor, forKey: .cursor)
        try c.encodeIfPresent(cursorText, forKey: .cursorText)
        try c.encodeIfPresent(selection, forKey: .selection)
        try c.encodeIfPresent(selectionForeground, forKey: .selectionForeground)
        try c.encode(ansi, forKey: .ansi)
        try c.encodeIfPresent(fontName, forKey: .fontName)
        try c.encodeIfPresent(fontSize, forKey: .fontSize)
        try c.encodeIfPresent(cursorStyle?.tagName, forKey: .cursorStyle)
        try c.encode(useBoldFonts, forKey: .useBoldFonts)
        try c.encode(textAntialiasing, forKey: .textAntialiasing)
    }

    // MARK: Hashable (CursorStyle is compared by its tag name)

    public static func == (lhs: TerminalTheme, rhs: TerminalTheme) -> Bool {
        lhs.name == rhs.name && lhs.hasSameLook(as: rhs)
    }

    public func hash (into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(foreground)
        hasher.combine(background)
        hasher.combine(ansi)
        hasher.combine(fontName)
    }

    /// True when the two themes look the same; the names may differ.
    public func hasSameLook (as other: TerminalTheme) -> Bool {
        foreground == other.foreground && background == other.background
            && backgroundOpacity == other.backgroundOpacity && boldForeground == other.boldForeground
            && cursor == other.cursor && cursorText == other.cursorText
            && selection == other.selection && selectionForeground == other.selectionForeground
            && ansi == other.ansi && fontName == other.fontName && fontSize == other.fontSize
            && cursorStyle?.tagName == other.cursorStyle?.tagName
            && useBoldFonts == other.useBoldFonts && textAntialiasing == other.textAntialiasing
    }
}

// MARK: - Presets

extension TerminalTheme {
    private static func rgb (_ hex: String) -> TerminalThemeColor {
        TerminalThemeColor(hex: hex)!
    }

    /// Terminal.app's ANSI colors, used by its profiles that do not set their own.
    public static let terminalAppANSI: [TerminalThemeColor] = [
        "#000000", "#C23621", "#25BC24", "#ADAD27", "#492EE1", "#D338D3", "#33BBC8", "#CBCCCD",
        "#818383", "#FC391F", "#31E722", "#EAEC23", "#5833FF", "#F935F8", "#14F0F0", "#E9EBEB",
    ].map(rgb)

    /// Terminal.app's "Homebrew" profile: green text on a black background
    /// that is 90% opaque, Andale Mono 12 without antialiasing.
    ///
    /// For text that matches Terminal.app, also set `syntheticBold` and
    /// `terminalAppLineHeight` on the view: Andale Mono has no bold face.
    public static let homebrew = TerminalTheme(
        name: "Homebrew",
        foreground: rgb("#28FE14"),
        background: rgb("#000000"),
        backgroundOpacity: 0.9,
        boldForeground: rgb("#00F900"),
        cursor: rgb("#38FE27"),
        selection: rgb("#0C2EEE").withAlpha(0.65),
        ansi: terminalAppANSI,
        fontName: "AndaleMono",
        fontSize: 12,
        cursorStyle: .blinkBlock,
        textAntialiasing: false)

    /// The Solarized palette as Ethan Schoonover published it for terminals
    /// (https://ethanschoonover.com/solarized/).
    static let solarizedANSI: [TerminalThemeColor] = [
        "#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
        "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3",
    ].map(rgb)

    /// Solarized Dark (https://ethanschoonover.com/solarized/).
    public static let solarizedDark = TerminalTheme(
        name: "Solarized Dark",
        foreground: rgb("#839496"),
        background: rgb("#002B36"),
        boldForeground: rgb("#93A1A1"),
        cursor: rgb("#93A1A1"),
        selection: rgb("#073642"),
        ansi: solarizedANSI)

    /// Solarized Light (https://ethanschoonover.com/solarized/).
    public static let solarizedLight = TerminalTheme(
        name: "Solarized Light",
        foreground: rgb("#657B83"),
        background: rgb("#FDF6E3"),
        boldForeground: rgb("#586E75"),
        cursor: rgb("#586E75"),
        selection: rgb("#EEE8D5"),
        ansi: solarizedANSI)

    /// Dracula (https://draculatheme.com/contribute).
    public static let dracula = TerminalTheme(
        name: "Dracula",
        foreground: rgb("#F8F8F2"),
        background: rgb("#282A36"),
        cursor: rgb("#F8F8F2"),
        selection: rgb("#44475A"),
        ansi: [
            "#21222C", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#F8F8F2",
            "#6272A4", "#FF6E6E", "#69FF94", "#FFFFA5", "#D6ACFF", "#FF92DF", "#A4FFFF", "#FFFFFF",
        ].map(rgb))

    /// The built-in themes.
    public static let presets: [TerminalTheme] = [homebrew, solarizedDark, solarizedLight, dracula]
}

// MARK: - iTerm2 .itermcolors

/// An error reading a theme file.
public enum TerminalThemeError: Error, Equatable, LocalizedError {
    /// The data is not a property list with the expected keys.
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let detail): return detail
        }
    }
}

extension TerminalTheme {
    static let itermANSIKeys = (0..<16).map { "Ansi \($0) Color" }

    /// Reads an iTerm2 `.itermcolors` file.
    ///
    /// The file only has colors. The font, cursor style and rendering choices
    /// come from `base`, as do colors the file leaves out. Colors in the
    /// "Calibrated" or "P3" color spaces are converted to sRGB.
    ///
    /// - Parameters:
    ///   - data: The contents of the file.
    ///   - name: The theme name, usually the file name without its extension.
    ///   - base: The theme that supplies everything the file does not set.
    public init (itermColors data: Data, name: String, base: TerminalTheme = .solarizedDark) throws {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            throw TerminalThemeError.invalidFormat("This is not an iTerm2 color file.")
        }
        func color (_ key: String) -> TerminalThemeColor? {
            (dict[key] as? [String: Any]).flatMap(Self.itermColor)
        }
        guard color("Foreground Color") != nil || color("Background Color") != nil
                || Self.itermANSIKeys.contains(where: { color($0) != nil }) else {
            throw TerminalThemeError.invalidFormat("This iTerm2 color file has no colors.")
        }
        var theme = base
        theme.name = name
        if let background = color("Background Color") {
            theme.background = background.withAlpha(1)
            theme.backgroundOpacity = Self.clampOpacity(background.alpha)
        }
        theme.foreground = color("Foreground Color") ?? base.foreground
        theme.boldForeground = color("Bold Color") ?? base.boldForeground
        theme.cursor = color("Cursor Color") ?? base.cursor
        theme.cursorText = color("Cursor Text Color") ?? base.cursorText
        theme.selection = color("Selection Color") ?? base.selection
        theme.selectionForeground = color("Selected Text Color") ?? base.selectionForeground
        theme.ansi = Self.itermANSIKeys.enumerated().map { index, key in
            color(key) ?? base.ansi[index]
        }
        self = theme
    }

    /// The theme's colors as an iTerm2 `.itermcolors` file (sRGB).
    public func itermColorsData () throws -> Data {
        func entry (_ color: TerminalThemeColor) -> [String: Any] {
            ["Red Component": color.red, "Green Component": color.green, "Blue Component": color.blue,
             "Alpha Component": color.alpha, "Color Space": "sRGB"]
        }
        var background = entry(self.background)
        background["Alpha Component"] = backgroundOpacity
        var dict: [String: Any] = [
            "Foreground Color": entry(foreground),
            "Background Color": background,
        ]
        if let boldForeground { dict["Bold Color"] = entry(boldForeground) }
        if let cursor { dict["Cursor Color"] = entry(cursor) }
        if let cursorText { dict["Cursor Text Color"] = entry(cursorText) }
        if let selection { dict["Selection Color"] = entry(selection) }
        if let selectionForeground { dict["Selected Text Color"] = entry(selectionForeground) }
        for (index, key) in Self.itermANSIKeys.enumerated() {
            dict[key] = entry(ansi[index])
        }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// One iTerm2 color dictionary, converted to sRGB.
    static func itermColor (_ dict: [String: Any]) -> TerminalThemeColor? {
        func component (_ key: String) -> Double? {
            (dict[key] as? Double) ?? (dict[key] as? NSNumber)?.doubleValue
        }
        guard let red = component("Red Component"),
              let green = component("Green Component"),
              let blue = component("Blue Component") else {
            return nil
        }
        let alpha = component("Alpha Component") ?? 1
        let space = dict["Color Space"] as? String ?? "sRGB"
        return convertToSRGB(red: red, green: green, blue: blue, alpha: alpha, space: space)
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

extension TerminalTheme {
    static func convertToSRGB (red: Double, green: Double, blue: Double, alpha: Double,
                               space: String) -> TerminalThemeColor {
        let sourceName: CFString
        switch space {
        case "P3": sourceName = CGColorSpace.displayP3
        // iTerm2 writes "Calibrated" for NSColor's calibrated RGB, which is
        // the Generic RGB color space.
        case "Calibrated": sourceName = "kCGColorSpaceGenericRGB" as CFString
        default: return TerminalThemeColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        guard let source = CGColorSpace(name: sourceName),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let color = CGColor(colorSpace: source, components: [red, green, blue, alpha].map { CGFloat($0) }),
              let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3 else {
            return TerminalThemeColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        return TerminalThemeColor(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]),
                                  alpha: Double(c.count > 3 ? c[3] : 1))
    }
}
#else
extension TerminalTheme {
    static func convertToSRGB (red: Double, green: Double, blue: Double, alpha: Double,
                               space: String) -> TerminalThemeColor {
        TerminalThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

#endif // !SWIFTTERM_EMBEDDED
