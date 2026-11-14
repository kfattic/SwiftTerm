//
//  TerminalTheme+Mac.swift
//  SwiftTerm
//
//  Applying a TerminalTheme to a view, and Apple Terminal `.terminal` profiles.
//

#if os(macOS) && !SWIFTTERM_EMBEDDED
import AppKit

extension TerminalThemeColor {
    /// The color converted to sRGB.
    public init (_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? color
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent),
                  blue: Double(srgb.blueComponent), alpha: Double(srgb.alphaComponent))
    }

    /// The color as an sRGB `NSColor`.
    public var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

extension TerminalTheme {
    /// The font the theme asks for at `fontSize`, or `nil` when it names no
    /// font or the font is not installed.
    public var font: NSFont? {
        guard let fontName else { return nil }
        return NSFont(name: fontName, size: CGFloat(fontSize ?? Double(NSFont.systemFontSize)))
    }
}

extension TerminalView {
    /// Applies every value of `theme`: the colors and ANSI palette, the
    /// background opacity, the bold color, the font, the cursor and the text
    /// rendering choices.
    ///
    /// Values the theme leaves `nil` keep the view's current ones, except the
    /// bold color, which is cleared. A font that is not installed keeps the
    /// current font but takes the theme's size.
    ///
    /// The background opacity is shown only in a window that is not opaque;
    /// see ``backgroundOpacity``.
    public func apply (theme: TerminalTheme) {
        installColors(theme.ansi.map(\.terminalColor))
        nativeForegroundColor = theme.foreground.nsColor
        nativeBackgroundColor = theme.background.nsColor.withAlphaComponent(CGFloat(theme.backgroundOpacity))
        boldForegroundColor = theme.boldForeground?.nsColor
        if let cursor = theme.cursor {
            caretColor = cursor.nsColor
        }
        if let cursorText = theme.cursorText {
            caretTextColor = cursorText.nsColor
        }
        if let selection = theme.selection {
            selectedTextBackgroundColor = selection.nsColor
        }
        if let selectionForeground = theme.selectionForeground {
            selectedTextForegroundColor = selectionForeground.nsColor
        }
        useBoldFonts = theme.useBoldFonts
        textAntialiasing = theme.textAntialiasing
        if let newFont = theme.font {
            if !newFont.isEqual(font) { font = newFont }
        } else if let size = theme.fontSize, CGFloat(size) != font.pointSize,
                  let resized = NSFont(descriptor: font.fontDescriptor, size: CGFloat(size)) {
            font = resized
        }
        if let cursorStyle = theme.cursorStyle {
            setCursorStyle(cursorStyle)
        }
    }
}

// MARK: - Apple Terminal .terminal profiles

extension TerminalTheme {
    /// The keys of the 16 ANSI colors in an Apple Terminal profile.
    static let terminalANSIKeys = [
        "ANSIBlackColor", "ANSIRedColor", "ANSIGreenColor", "ANSIYellowColor",
        "ANSIBlueColor", "ANSIMagentaColor", "ANSICyanColor", "ANSIWhiteColor",
        "ANSIBrightBlackColor", "ANSIBrightRedColor", "ANSIBrightGreenColor", "ANSIBrightYellowColor",
        "ANSIBrightBlueColor", "ANSIBrightMagentaColor", "ANSIBrightCyanColor", "ANSIBrightWhiteColor",
    ]

    /// Reads an Apple Terminal `.terminal` file (Terminal → Settings →
    /// Profiles → Export).
    public init (terminalProfile data: Data) throws {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let profile = plist as? [String: Any] else {
            throw TerminalThemeError.invalidFormat("This is not an Apple Terminal profile.")
        }
        guard profile["type"] as? String == "Window Settings" || profile["BackgroundColor"] != nil
                || profile["TextColor"] != nil || profile["Font"] != nil else {
            throw TerminalThemeError.invalidFormat("This is not an Apple Terminal profile.")
        }
        self.init(terminalProfile: profile, name: profile["name"] as? String ?? "Imported")
    }

    /// Reads one Apple Terminal profile dictionary: the contents of a
    /// `.terminal` file, or one entry of Terminal's "Window Settings"
    /// preference.
    ///
    /// Values the profile leaves out take Terminal.app's defaults, as Terminal
    /// does: black text on white, Terminal's ANSI colors, a block cursor.
    public init (terminalProfile profile: [String: Any], name: String) {
        func color (_ key: String) -> NSColor? {
            guard let data = profile[key] as? Data else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        }
        func flag (_ key: String, _ defaultValue: Bool) -> Bool {
            (profile[key] as? NSNumber)?.boolValue ?? defaultValue
        }
        let font = (profile["Font"] as? Data).flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: $0)
        }
        let backgroundColor = color("BackgroundColor")
        let background = backgroundColor.map(TerminalThemeColor.init)
            ?? TerminalThemeColor(red: 1, green: 1, blue: 1)
        let opacity = backgroundColor.map { Double(($0.usingColorSpace(.sRGB) ?? $0).alphaComponent) } ?? 1
        let blink = flag("CursorBlink", false)
        let cursorStyle: CursorStyle
        switch (profile["CursorType"] as? NSNumber)?.intValue ?? 0 {
        case 1: cursorStyle = blink ? .blinkUnderline : .steadyUnderline
        case 2: cursorStyle = blink ? .blinkBar : .steadyBar
        default: cursorStyle = blink ? .blinkBlock : .steadyBlock
        }
        self.init(name: name,
                  foreground: color("TextColor").map(TerminalThemeColor.init)
                      ?? TerminalThemeColor(red: 0, green: 0, blue: 0),
                  background: background,
                  backgroundOpacity: opacity,
                  boldForeground: color("TextBoldColor").map(TerminalThemeColor.init),
                  cursor: color("CursorColor").map(TerminalThemeColor.init),
                  selection: color("SelectionColor").map(TerminalThemeColor.init),
                  ansi: Self.terminalANSIKeys.enumerated().map { index, key in
                      color(key).map(TerminalThemeColor.init) ?? Self.terminalAppANSI[index]
                  },
                  fontName: font?.fontName,
                  fontSize: font.map { Double($0.pointSize) },
                  cursorStyle: cursorStyle,
                  useBoldFonts: flag("UseBoldFonts", true),
                  textAntialiasing: flag("FontAntialias", true))
    }

    /// The theme as an Apple Terminal `.terminal` file, which Terminal can
    /// import (Terminal → Settings → Profiles → Import).
    ///
    /// Terminal profiles have no cursor text or selected text color, so those
    /// are not written.
    public func terminalProfileData () throws -> Data {
        func archive (_ object: NSObject) throws -> Data {
            try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
        }
        let blinks: Bool
        let cursorType: Int
        switch cursorStyle ?? .blinkBlock {
        case .blinkBlock: (cursorType, blinks) = (0, true)
        case .steadyBlock: (cursorType, blinks) = (0, false)
        case .blinkUnderline: (cursorType, blinks) = (1, true)
        case .steadyUnderline: (cursorType, blinks) = (1, false)
        case .blinkBar: (cursorType, blinks) = (2, true)
        case .steadyBar: (cursorType, blinks) = (2, false)
        }
        var profile: [String: Any] = [
            "name": name,
            "type": "Window Settings",
            "ProfileCurrentVersion": 2.07,
            "BackgroundColor": try archive(background.nsColor.withAlphaComponent(CGFloat(backgroundOpacity))),
            "TextColor": try archive(foreground.nsColor),
            "CursorType": cursorType,
            "CursorBlink": blinks,
            "UseBoldFonts": useBoldFonts,
            "FontAntialias": textAntialiasing,
        ]
        if let boldForeground { profile["TextBoldColor"] = try archive(boldForeground.nsColor) }
        if let cursor { profile["CursorColor"] = try archive(cursor.nsColor) }
        if let selection { profile["SelectionColor"] = try archive(selection.nsColor) }
        if let font { profile["Font"] = try archive(font) }
        for (index, key) in Self.terminalANSIKeys.enumerated() {
            profile[key] = try archive(ansi[index].nsColor)
        }
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}
#endif
