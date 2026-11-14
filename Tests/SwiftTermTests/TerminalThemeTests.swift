//
//  TerminalThemeTests.swift
//  SwiftTermTests
//
//  TerminalTheme: colors, presets, Codable, iTerm2 .itermcolors and (macOS)
//  Apple Terminal .terminal import and export, and applying a theme to a view.
//

#if !SWIFTTERM_EMBEDDED
import Foundation
import Testing
@testable import SwiftTerm

@Suite("Terminal themes")
struct TerminalThemeTests {
    // MARK: Colors

    @Test func hexParsesAndPrints() throws {
        let color = try #require(TerminalThemeColor(hex: "#0C2EEEA6"))
        #expect(color.hex == "#0C2EEEA6")
        #expect(abs(color.alpha - 0.651) < 0.001)
        #expect(TerminalThemeColor(hex: "28fe14")?.hex == "#28FE14")
        #expect(TerminalThemeColor(hex: "#fff")?.hex == "#FFFFFF")
        #expect(TerminalThemeColor(hex: "#12345") == nil)
        #expect(TerminalThemeColor(hex: "#GGGGGG") == nil)
    }

    @Test func terminalColorUsesSixteenBitComponents() {
        let color = TerminalThemeColor(hex: "#FF0080")!.terminalColor
        #expect(color.red == 65535)
        #expect(color.green == 0)
        #expect(color.blue == 0x8080)
    }

    // MARK: Presets

    @Test func presetsHaveSixteenColorsAndDistinctNames() {
        #expect(TerminalTheme.presets.count == 4)
        #expect(Set(TerminalTheme.presets.map(\.name)).count == TerminalTheme.presets.count)
        for theme in TerminalTheme.presets {
            #expect(theme.ansi.count == 16)
        }
    }

    /// Spot checks against the published palettes.
    @Test func presetsUseThePublishedColors() {
        #expect(TerminalTheme.solarizedDark.background.hex == "#002B36")
        #expect(TerminalTheme.solarizedDark.ansi[4].hex == "#268BD2")
        #expect(TerminalTheme.solarizedLight.background.hex == "#FDF6E3")
        #expect(TerminalTheme.dracula.background.hex == "#282A36")
        #expect(TerminalTheme.dracula.ansi[13].hex == "#FF92DF")
        #expect(TerminalTheme.homebrew.foreground.hex == "#28FE14")
        #expect(TerminalTheme.homebrew.backgroundOpacity == 0.9)
        #expect(TerminalTheme.homebrew.textAntialiasing == false)
    }

    @Test func shortPalettesArePadded() {
        let theme = TerminalTheme(name: "Short", foreground: .init(red: 1, green: 1, blue: 1),
                                  background: .init(red: 0, green: 0, blue: 0),
                                  ansi: [.init(red: 1, green: 0, blue: 0)])
        #expect(theme.ansi.count == 16)
        #expect(theme.ansi[0].hex == "#FF0000")
        #expect(theme.ansi[1] == TerminalTheme.terminalAppANSI[1])
    }

    @Test func backgroundAlphaMovesToTheOpacity() {
        let theme = TerminalTheme(name: "T", foreground: .init(red: 1, green: 1, blue: 1),
                                  background: .init(red: 0, green: 0, blue: 0, alpha: 0.5),
                                  backgroundOpacity: 2)
        #expect(theme.background.alpha == 1)
        #expect(theme.backgroundOpacity == 1)
    }

    // MARK: Codable

    @Test(arguments: TerminalTheme.presets)
    func codableRoundTrip(theme: TerminalTheme) throws {
        let data = try JSONEncoder().encode(theme)
        let back = try JSONDecoder().decode(TerminalTheme.self, from: data)
        #expect(back == theme)
        #expect(back.cursorStyle?.tagName == theme.cursorStyle?.tagName)
    }

    @Test func decodingFillsMissingValues() throws {
        let json = ##"{"name":"Minimal","foreground":"#FFFFFF","background":"#000000"}"##
        let theme = try JSONDecoder().decode(TerminalTheme.self, from: Data(json.utf8))
        #expect(theme.ansi == TerminalTheme.terminalAppANSI)
        #expect(theme.backgroundOpacity == 1)
        #expect(theme.useBoldFonts && theme.textAntialiasing)
        #expect(theme.cursorStyle == nil)
    }

    @Test func colorsAreStoredAsHex() throws {
        let json = String(decoding: try JSONEncoder().encode(TerminalTheme.homebrew), as: UTF8.self)
        #expect(json.contains("\"#28FE14\""))
        #expect(json.contains("\"blinkBlock\""))
    }

    @Test func invalidColorFailsToDecode() {
        let json = ##"{"name":"Bad","foreground":"white","background":"#000000"}"##
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TerminalTheme.self, from: Data(json.utf8))
        }
    }

    // MARK: iTerm2

    private func itermEntry(_ r: Double, _ g: Double, _ b: Double, space: String = "sRGB") -> [String: Any] {
        ["Red Component": r, "Green Component": g, "Blue Component": b, "Color Space": space]
    }

    @Test func importsITermColors() throws {
        let plist: [String: Any] = [
            "Background Color": itermEntry(0.1, 0.2, 0.3),
            "Foreground Color": itermEntry(1, 1, 1),
            "Bold Color": itermEntry(1, 1, 0),
            "Cursor Color": itermEntry(0, 1, 0),
            "Selection Color": itermEntry(0, 0, 1),
            "Ansi 1 Color": itermEntry(1, 0, 0),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let theme = try TerminalTheme(itermColors: data, name: "Sample", base: .dracula)
        #expect(theme.name == "Sample")
        #expect(theme.background.hex == "#1A334D")
        #expect(theme.foreground.hex == "#FFFFFF")
        #expect(theme.boldForeground?.hex == "#FFFF00")
        #expect(theme.cursor?.hex == "#00FF00")
        #expect(theme.selection?.hex == "#0000FF")
        #expect(theme.ansi[1].hex == "#FF0000")
        // Colors the file leaves out come from the base theme.
        #expect(theme.ansi[2] == TerminalTheme.dracula.ansi[2])
        #expect(theme.fontName == TerminalTheme.dracula.fontName)
    }

    @Test func itermBackgroundAlphaBecomesTheOpacity() throws {
        var background = itermEntry(0, 0, 0)
        background["Alpha Component"] = 0.8
        let data = try PropertyListSerialization.data(fromPropertyList: ["Background Color": background],
                                                      format: .xml, options: 0)
        let theme = try TerminalTheme(itermColors: data, name: "T")
        #expect(abs(theme.backgroundOpacity - 0.8) < 0.0001)
        #expect(theme.background.alpha == 1)
    }

    #if canImport(CoreGraphics)
    @Test func itermP3ColorsAreConvertedToSRGB() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Ansi 1 Color": itermEntry(1, 0, 0, space: "P3")], format: .xml, options: 0)
        let red = try TerminalTheme(itermColors: data, name: "P3").ansi[1]
        // Display P3 red lies outside sRGB: the green and blue go negative and clamp.
        #expect(red.red == 1)
        #expect(red.green == 0)
    }
    #endif

    @Test(arguments: TerminalTheme.presets)
    func itermRoundTrip(theme: TerminalTheme) throws {
        let back = try TerminalTheme(itermColors: try theme.itermColorsData(), name: theme.name, base: theme)
        #expect(back.foreground.hex == theme.foreground.hex)
        #expect(back.background.hex == theme.background.hex)
        #expect(abs(back.backgroundOpacity - theme.backgroundOpacity) < 0.0001)
        #expect(back.selection?.hex == theme.selection?.hex)
        #expect(back.ansi.map(\.hex) == theme.ansi.map(\.hex))
    }

    @Test func rejectsFilesThatAreNotColorFiles() {
        #expect(throws: TerminalThemeError.self) {
            try TerminalTheme(itermColors: Data("hello".utf8), name: "x")
        }
        let empty = try! PropertyListSerialization.data(fromPropertyList: ["x": 1], format: .xml, options: 0)
        #expect(throws: TerminalThemeError.self) {
            try TerminalTheme(itermColors: empty, name: "x")
        }
    }
}

#if os(macOS)
import AppKit

@Suite("Terminal themes (macOS)")
@MainActor
struct TerminalThemeMacTests {
    @Test(arguments: TerminalTheme.presets)
    func terminalProfileRoundTrip(theme: TerminalTheme) throws {
        let back = try TerminalTheme(terminalProfile: try theme.terminalProfileData())
        #expect(back.name == theme.name)
        #expect(back.foreground.hex == theme.foreground.hex)
        #expect(back.background.hex == theme.background.hex)
        #expect(abs(back.backgroundOpacity - theme.backgroundOpacity) < 0.002)
        #expect(back.boldForeground?.hex == theme.boldForeground?.hex)
        #expect(back.cursor?.hex == theme.cursor?.hex)
        #expect(back.selection?.hex == theme.selection?.hex)
        #expect(back.ansi.map(\.hex) == theme.ansi.map(\.hex))
        #expect(back.useBoldFonts == theme.useBoldFonts)
        #expect(back.textAntialiasing == theme.textAntialiasing)
        #expect(back.cursorStyle?.tagName == (theme.cursorStyle ?? .blinkBlock).tagName)
        if let font = theme.font {
            #expect(back.fontName == font.fontName)
            #expect(back.fontSize == theme.fontSize)
        }
    }

    /// The Homebrew preset matches the profile Terminal.app ships.
    @Test func homebrewMatchesTerminalApp() throws {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings/Homebrew.terminal")
        guard let data = try? Data(contentsOf: url) else { return }
        let shipped = try TerminalTheme(terminalProfile: data)
        #expect(shipped.hasSameLook(as: .homebrew),
                "\(shipped) differs from the Homebrew preset")
    }

    @Test func missingProfileValuesUseTerminalDefaults() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["name": "Empty", "type": "Window Settings"], format: .xml, options: 0)
        let theme = try TerminalTheme(terminalProfile: data)
        #expect(theme.name == "Empty")
        #expect(theme.background.hex == "#FFFFFF")
        #expect(theme.foreground.hex == "#000000")
        #expect(theme.ansi == TerminalTheme.terminalAppANSI)
        #expect(theme.cursorStyle?.tagName == CursorStyle.steadyBlock.tagName)
    }

    @Test func rejectsFilesThatAreNotProfiles() {
        #expect(throws: TerminalThemeError.self) {
            try TerminalTheme(terminalProfile: Data("nope".utf8))
        }
    }

    @Test func applySetsTheViewsColorsFontAndOptions() throws {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200), font: nil,
                                options: TerminalOptions(cols: 20, rows: 4, scrollback: 0))
        let theme = TerminalTheme.homebrew
        view.apply(theme: theme)
        #expect(TerminalThemeColor(view.nativeForegroundColor).hex == "#28FE14")
        #expect(abs(view.backgroundOpacity - 0.9) < 0.001)
        #expect(TerminalThemeColor(try #require(view.boldForegroundColor)).hex == "#00F900")
        #expect(TerminalThemeColor(view.caretColor).hex == "#38FE27")
        #expect(TerminalThemeColor(view.selectedTextBackgroundColor).hex == "#0C2EEEA6")
        #expect(view.textAntialiasing == false)
        if let font = theme.font {
            #expect(view.font.fontName == font.fontName)
            #expect(view.font.pointSize == 12)
        }
        view.withTerminal { terminal in
            #expect(terminal.ansiColors[1] == TerminalTheme.terminalAppANSI[1].terminalColor)
        }
        view.apply(theme: .solarizedDark)
        #expect(view.boldForegroundColor.map { TerminalThemeColor($0).hex } == "#93A1A1")
        #expect(view.textAntialiasing)
        #expect(view.backgroundOpacity == 1)
    }
}
#endif
#endif
