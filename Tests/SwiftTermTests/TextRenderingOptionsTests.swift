//
//  TextRenderingOptionsTests.swift
//  SwiftTermTests
//
//  The Terminal.app-style text options: `textAntialiasing`, `useBoldFonts`,
//  `syntheticBold`, `boldForegroundColor` and `terminalAppLineHeight`. The
//  defaults must keep the existing rendering; each option is checked through
//  the snapshot attributes both renderers read and through rendered pixels.
//

#if os(macOS) && !SWIFTTERM_EMBEDDED
import AppKit
import Metal
import Testing
@testable import SwiftTerm

@Suite("Text rendering options")
@MainActor
struct TextRenderingOptionsTests {
    /// Andale Mono and Monaco ship with macOS and have no bold face.
    static let fontWithoutBold = NSFont(name: "AndaleMono", size: 14) ?? NSFont(name: "Monaco", size: 14)
    static let fontWithBold = NSFont(name: "Menlo-Regular", size: 14)!

    private func makeView(font: NSFont? = nil) -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 200), font: font,
                     options: TerminalOptions(cols: 20, rows: 4, scrollback: 0))
    }

    private func context(_ view: TerminalView) -> SnapshotRenderContext {
        SnapshotRenderContext(viewState: FrameViewState(view: view), style: .empty,
                              ansiColors: view.withTerminal { $0.ansiColors }, cols: 20)
    }

    private func attributes(_ style: CharacterStyle, fg: Attribute.Color = .defaultColor,
                            view: TerminalView) -> [NSAttributedString.Key: Any] {
        SnapshotTextBuilder().getAttributes(Attribute(fg: fg, bg: .defaultColor, style: style),
                                            withUrl: false, context: context(view))!.values
    }

    // MARK: Defaults

    @Test func defaultsKeepTheExistingRendering() {
        let view = makeView()
        #expect(view.textAntialiasing)
        #expect(view.useBoldFonts)
        #expect(view.syntheticBold == false)
        #expect(view.boldForegroundColor == nil)
        #expect(view.terminalAppLineHeight == false)
        let bold = attributes(.bold, view: view)
        #expect(bold[SwiftTermSyntheticBoldKey] == nil)
        #expect((bold[.foregroundColor] as! NSColor) == context(view).effectiveForegroundColor)
    }

    // MARK: useBoldFonts

    @Test func boldTextUsesTheRegularFaceWhenBoldFontsAreOff() {
        let view = makeView(font: Self.fontWithBold)
        #expect(view.fontSet.bold.fontName != view.fontSet.normal.fontName)
        view.useBoldFonts = false
        #expect(view.fontSet.bold.fontName == view.fontSet.normal.fontName)
        #expect(view.fontSet.boldItalic.fontName == view.fontSet.italic.fontName)
        let font = attributes(.bold, view: view)[.font] as! NSFont
        #expect(font.fontName == Self.fontWithBold.fontName)
        view.useBoldFonts = true
        #expect(view.fontSet.bold.fontName == "Menlo-Bold")
    }

    @Test func turningBoldFontsOffKeepsTheGrid() {
        let view = makeView(font: Self.fontWithBold)
        let before = view.cellDimension!
        let cols = view.withTerminal { $0.cols }
        view.useBoldFonts = false
        #expect(view.cellDimension == before)
        #expect(view.withTerminal { $0.cols } == cols)
    }

    @Test func boldTextKeepsItsBrightColorWithoutBoldFonts() {
        let view = makeView()
        view.useBoldFonts = false
        let color = attributes(.bold, fg: .ansi256(code: 1), view: view)[.foregroundColor] as! NSColor
        let bright = view.withTerminal { NSColor.make(color: $0.ansiColors[9]) }
        #expect(color == bright)
    }

    // MARK: syntheticBold

    @Test func syntheticBoldMarksBoldTextInAFontWithoutABoldFace() throws {
        let font = try #require(Self.fontWithoutBold)
        let view = makeView(font: font)
        view.syntheticBold = true
        #expect(view.fontSet.syntheticBold)
        #expect(attributes(.bold, view: view)[SwiftTermSyntheticBoldKey] != nil)
        #expect(attributes([.bold, .italic], view: view)[SwiftTermSyntheticBoldKey] != nil)
        #expect(attributes(.none, view: view)[SwiftTermSyntheticBoldKey] == nil)
        #expect(attributes(.italic, view: view)[SwiftTermSyntheticBoldKey] == nil)
    }

    @Test func syntheticBoldLeavesFontsWithABoldFaceAlone() {
        let view = makeView(font: Self.fontWithBold)
        view.syntheticBold = true
        #expect(view.fontSet.syntheticBold == false)
        #expect(attributes(.bold, view: view)[SwiftTermSyntheticBoldKey] == nil)
    }

    @Test func syntheticBoldIsOffWhileBoldFontsAreOff() throws {
        let view = makeView(font: try #require(Self.fontWithoutBold))
        view.syntheticBold = true
        view.useBoldFonts = false
        #expect(view.fontSet.syntheticBold == false)
        #expect(attributes(.bold, view: view)[SwiftTermSyntheticBoldKey] == nil)
    }

    @Test func syntheticBoldFollowsAFontChange() throws {
        let view = makeView(font: try #require(Self.fontWithoutBold))
        view.syntheticBold = true
        #expect(view.fontSet.syntheticBold)
        view.font = Self.fontWithBold
        #expect(view.fontSet.syntheticBold == false)
    }

    /// The plain-text path the Metal renderer uses must keep bold and regular
    /// runs apart even though both use the same font.
    @Test func plainRowsKeepSyntheticBoldRunsApart() throws {
        let view = makeView(font: try #require(Self.fontWithoutBold))
        view.syntheticBold = true
        view.feed(text: "ab\u{1b}[1mcd\u{1b}[0mef")
        let snapshot = TerminalSnapshot()
        view.withTerminal { terminal in
            _ = snapshot.refresh(terminal: terminal, viewState: FrameViewState(view: view),
                                 selection: SnapshotSelectionState(selection: view.selection))
        }
        let row = try #require(snapshot.rows.first)
        let context = SnapshotRenderContext(viewState: FrameViewState(view: view), snapshot: snapshot)
        let plain = try #require(SnapshotTextBuilder().plainRow(row: row, absoluteRow: snapshot.firstRow,
                                                                context: context))
        let bold = try #require(plain.runs.first(where: { $0.start <= 2 && $0.end > 2 }))
        let regular = try #require(plain.runs.first(where: { $0.start <= 0 && $0.end > 0 }))
        #expect(bold.style.syntheticBold)
        #expect(bold.end == 4)
        #expect(regular.style.syntheticBold == false)
    }

    @Test func contextIdentityTracksSyntheticBold() throws {
        let view = makeView(font: try #require(Self.fontWithoutBold))
        let off = context(view).identity
        view.syntheticBold = true
        #expect(context(view).identity != off)
    }

    // MARK: boldForegroundColor

    @Test func boldDefaultColoredTextUsesTheBoldColor() {
        let view = makeView()
        let boldColor = NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        view.boldForegroundColor = boldColor
        let context = context(view)
        view.withTerminal { _ in
            #expect(view.mapColor(color: .defaultColor, isFg: true, isBold: true) == boldColor)
            #expect(view.mapColor(color: .defaultColor, isFg: true, isBold: false) == view.nativeForegroundColor)
        }
        #expect(SwiftTerm.mapColor(color: .defaultColor, isFg: true, isBold: true, context: context) == boldColor)
        #expect(SwiftTerm.mapColor(color: .defaultColor, isFg: false, isBold: true, context: context)
                == context.effectiveBackgroundColor)
        #expect((attributes(.bold, view: view)[.foregroundColor] as! NSColor) == boldColor)
        #expect((attributes(.none, view: view)[.foregroundColor] as! NSColor) == context.effectiveForegroundColor)
    }

    @Test func boldTextWithAnExplicitColorKeepsIt() {
        let view = makeView()
        view.boldForegroundColor = .orange
        let color = attributes(.bold, fg: .ansi256(code: 4), view: view)[.foregroundColor] as! NSColor
        let bright = view.withTerminal { NSColor.make(color: $0.ansiColors[12]) }
        #expect(color == bright)
    }

    @Test func reverseVideoDoesNotUseTheBoldColor() {
        let view = makeView()
        view.boldForegroundColor = .orange
        view.feed(text: "\u{1b}[?5h")
        let context = context(view)
        #expect(context.boldForegroundColor == nil)
        view.withTerminal { _ in
            #expect(view.mapColor(color: .defaultColor, isFg: true, isBold: true) == view.nativeBackgroundColor)
        }
    }

    @Test func contextIdentityTracksTheBoldColor() {
        let view = makeView()
        let off = context(view).identity
        view.boldForegroundColor = .orange
        #expect(context(view).identity != off)
    }

    // MARK: terminalAppLineHeight

    @Test func terminalAppLineHeightRoundsEachMetric() {
        #expect(CellGeometry.cellHeight(ascent: 12.7, descent: 3.05, leading: 0,
                                        lineSpacing: 1, terminalAppLineHeight: false) == 16)
        #expect(CellGeometry.cellHeight(ascent: 12.7, descent: 3.05, leading: 0,
                                        lineSpacing: 1, terminalAppLineHeight: true) == 17)
        #expect(CellGeometry.cellHeight(ascent: 12.7, descent: 3.05, leading: 0,
                                        lineSpacing: 1.5, terminalAppLineHeight: true) == 26)
    }

    @Test func andaleMonoIsSeventeenPointsHighLikeTerminalApp() throws {
        let font = try #require(NSFont(name: "AndaleMono", size: 14))
        let view = makeView(font: font)
        let natural = view.cellDimension.height
        view.terminalAppLineHeight = true
        #expect(view.cellDimension.height == 17)
        #expect(view.cellDimension.height > natural)
        view.terminalAppLineHeight = false
        #expect(view.cellDimension.height == natural)
    }

    @Test func renderViewMeasuresTheSameLineHeight() throws {
        let font = try #require(NSFont(name: "AndaleMono", size: 14))
        let view = makeView(font: font)
        view.terminalAppLineHeight = true
        let renderView = TerminalRenderView(frame: CGRect(x: 0, y: 0, width: 400, height: 200), font: font)
        renderView.terminalAppLineHeight = true
        #expect(renderView.cellDimension.height == view.cellDimension.height)
    }

    // MARK: Core Graphics pixels

    /// Renders white text on black with the Core Graphics renderer and
    /// returns the RGBA pixels.
    private func renderCoreGraphics(_ view: TerminalView) -> (pixels: [UInt8], width: Int, height: Int) {
        view.nativeForegroundColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        view.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        if let state = view.captureFrameViewState() {
            _ = view.prepareFrame(viewState: state)
        }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (pixels, width, height)
    }

    /// Pixels that are neither background nor full text color: the
    /// antialiased edges.
    private func partialPixels(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 24 && pixels[$0] < 232 }.count
    }

    private func inkPixels(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 24 }.count
    }

    @Test func coreGraphicsDrawsCrispTextWithoutAntialiasing() {
        let text = "Wag@sQ0&%"
        let smooth = makeView(font: Self.fontWithBold)
        smooth.feed(text: text)
        let crisp = makeView(font: Self.fontWithBold)
        crisp.textAntialiasing = false
        crisp.feed(text: text)
        let smoothPixels = renderCoreGraphics(smooth).pixels
        let crispPixels = renderCoreGraphics(crisp).pixels
        #expect(inkPixels(crispPixels) > 0)
        #expect(partialPixels(smoothPixels) > 0)
        #expect(partialPixels(crispPixels) == 0)
    }

    @Test func coreGraphicsSyntheticBoldWidensBoldText() throws {
        let font = try #require(Self.fontWithoutBold)
        func ink(synthetic: Bool) -> Int {
            let view = makeView(font: font)
            view.textAntialiasing = false
            view.syntheticBold = synthetic
            view.feed(text: "\u{1b}[1mIIIIllll")
            return inkPixels(renderCoreGraphics(view).pixels)
        }
        let regular = ink(synthetic: false)
        let synthetic = ink(synthetic: true)
        #expect(regular > 0)
        #expect(synthetic > regular)
    }

    // MARK: Metal pixels

    private func renderMetal(_ view: TerminalView) -> [UInt8]? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        view.nativeForegroundColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        view.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let target = TerminalMetalLayerView(frame: view.bounds)
        target.renderDevice = device
        target.metalLayer.framebufferOnly = false
        target.renderContentsScale = 1
        target.renderDrawableSize = view.bounds.size
        guard let renderer = try? MetalTerminalRenderer(target: target) else { return nil }
        renderer.waitForCompletionAfterCommit = true
        renderer.capturesRenderedTexture = true
        guard view.renderSnapshotForMetal(renderer: renderer, target: target),
              let texture = renderer.lastRenderedTexture,
              texture.width > 0, texture.height > 0 else { return nil }
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                             mipmapLevel: 0)
        }
        return bytes
    }

    @Test func metalDrawsCrispTextWithoutAntialiasing() {
        let text = "Wag@sQ0&%"
        let smooth = makeView(font: Self.fontWithBold)
        smooth.feed(text: text)
        let crisp = makeView(font: Self.fontWithBold)
        crisp.textAntialiasing = false
        crisp.feed(text: text)
        guard let smoothPixels = renderMetal(smooth), let crispPixels = renderMetal(crisp) else { return }
        #expect(inkPixels(crispPixels) > 0)
        #expect(partialPixels(smoothPixels) > 0)
        #expect(partialPixels(crispPixels) == 0)
    }

    @Test func metalSyntheticBoldWidensBoldText() throws {
        let font = try #require(Self.fontWithoutBold)
        func ink(synthetic: Bool) -> Int? {
            let view = makeView(font: font)
            view.textAntialiasing = false
            view.syntheticBold = synthetic
            view.feed(text: "\u{1b}[1mIIIIllll")
            return renderMetal(view).map(inkPixels)
        }
        guard let regular = ink(synthetic: false), let synthetic = ink(synthetic: true) else { return }
        #expect(regular > 0)
        #expect(synthetic > regular)
    }
}
#endif
