//
//  TerminalThemeSettingsView.swift
//  SwiftTerm
//
//  A ready-made settings screen for terminal themes, laid out like
//  Terminal.app's Settings → Profiles: pick a theme, see it in a live
//  terminal, change it, save it, import and export it.
//

#if os(macOS) && !SWIFTTERM_EMBEDDED
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A settings screen for terminal themes, built on ``TerminalThemeLibrary``.
///
/// - Themes: the built-in themes and the person's own, as cards. Save (⌘S),
///   Save As, Import (`.terminal`, `.itermcolors`, Apple Terminal's profiles)
///   and Export (`.terminal`, `.itermcolors`).
/// - Preview: a live `TerminalView` showing sample output in the theme.
/// - Customize: font and size, bold and antialiasing, cursor shape and blink,
///   the default, bold, cursor and selection colors, the background opacity
///   and the 16 ANSI colors.
///
/// Changes apply right away; a saved theme changes only on Save. Picking
/// another theme while there are unsaved changes asks to save or discard them.
///
/// ```swift
/// let library = TerminalThemeLibrary()
/// let settings = NSHostingView(rootView: TerminalThemeSettingsView(library: library))
/// let subscription = library.$theme.sink { terminalView.apply(theme: $0) }
/// ```
@available(macOS 13, *)
public struct TerminalThemeSettingsView: View {
    @ObservedObject var library: TerminalThemeLibrary
    @State private var message: String?
    @State private var showsProportionalFonts = false

    public init (library: TerminalThemeLibrary) {
        self.library = library
    }

    public var body: some View {
        Form {
            Section {
                themeGrid(library.builtInThemes)
                if !library.savedThemes.isEmpty {
                    Text("My Themes").font(.headline).padding(.top, 4)
                    themeGrid(library.savedThemes)
                }
                actions
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Themes")
            }

            Section {
                TerminalThemePreview(theme: library.theme)
                    .frame(height: 170)
                    // Stands in for what is behind a terminal window, so a
                    // translucent background shows as it would on screen.
                    .background(LinearGradient(colors: [SwiftUI.Color(red: 0.25, green: 0.45, blue: 0.85),
                                                        SwiftUI.Color(red: 0.85, green: 0.45, blue: 0.35)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } header: {
                Text("Preview — \(title)")
            }

            Section {
                customize
            } header: {
                HStack {
                    Text("Customize — \(title)")
                    Spacer()
                    if library.hasUnsavedChanges {
                        Text("Unsaved changes. Save (⌘S) keeps them as “\(library.saveName)”.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var title: String {
        library.hasUnsavedChanges ? "\(library.theme.name) (modified)" : library.theme.name
    }

    // MARK: Themes

    private func themeGrid (_ themes: [TerminalTheme]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(themes, id: \.name) { theme in
                card(theme)
            }
        }
    }

    private func card (_ theme: TerminalTheme) -> some View {
        let isCurrent = library.theme.name == theme.name
        let isSaved = library.savedThemes.contains { $0.name == theme.name }
        return Button { pick(theme) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 0) {
                    Text("$ ls").foregroundStyle(SwiftUI.Color(nsColor: theme.foreground.nsColor))
                    Rectangle().fill(SwiftUI.Color(nsColor: (theme.cursor ?? theme.foreground).nsColor))
                        .frame(width: 6, height: 12).padding(.leading, 2)
                }
                .font(.system(size: 11, design: .monospaced))
                HStack(spacing: 3) {
                    ForEach(1..<7) { index in
                        Circle().fill(SwiftUI.Color(nsColor: theme.ansi[index].nsColor)).frame(width: 7, height: 7)
                    }
                }
                Text(theme.name).font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftUI.Color(nsColor: theme.foreground.nsColor))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(SwiftUI.Color(nsColor: theme.background.nsColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(isCurrent ? SwiftUI.Color.accentColor : SwiftUI.Color.secondary.opacity(0.3), lineWidth: isCurrent ? 3 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .contextMenu {
            Button("Duplicate") { library.add(theme) }
            Button("Export…") { export(theme) }
            if isSaved {
                Button("Rename…") { rename(theme) }
                Divider()
                Button("Delete…", role: .destructive) { delete(theme) }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!library.hasUnsavedChanges)
            Button("Save As…") { saveAs() }
            Menu("Import") {
                Button("Terminal or iTerm2 File…") { importFile() }
                let profiles = TerminalTheme.appleTerminalProfiles()
                if !profiles.isEmpty {
                    Menu("From Apple Terminal") {
                        ForEach(profiles, id: \.name) { profile in
                            Button(profile.name) { add(profile, note: "Imported “\(profile.name)” from Terminal.") }
                        }
                    }
                }
            }
            .fixedSize()
            Button("Export…") { export(library.theme) }
            Spacer()
        }
    }

    // MARK: Customize

    private static let ansiNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

    private var customize: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("Font").gridColumnAlignment(.trailing)
                HStack(spacing: 10) {
                    Picker("Font", selection: fontNameBinding) {
                        ForEach(fontChoices, id: \.postScriptName) { choice in
                            Text(choice.label).tag(choice.postScriptName)
                        }
                    }
                    .labelsHidden().fixedSize()
                    Text("\(Int(fontSize)) pt").monospacedDigit()
                    Stepper("Font size", value: fontSizeBinding, in: 8...36, step: 1).labelsHidden()
                    Toggle("Show all fonts", isOn: $showsProportionalFonts).toggleStyle(.checkbox)
                }
            }
            GridRow {
                Text("Text")
                HStack(spacing: 18) {
                    Toggle("Use bold fonts", isOn: binding(\.useBoldFonts)).toggleStyle(.checkbox)
                    Toggle("Antialias text", isOn: binding(\.textAntialiasing)).toggleStyle(.checkbox)
                }
            }
            GridRow {
                Text("Cursor")
                HStack(spacing: 18) {
                    Picker("Cursor", selection: cursorShapeBinding) {
                        Text("Block").tag(CursorShape.block)
                        Text("Underline").tag(CursorShape.underline)
                        Text("Bar").tag(CursorShape.bar)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Toggle("Blink", isOn: cursorBlinkBinding).toggleStyle(.checkbox)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text("Colors")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        colorWell("Background", colorBinding(\.background))
                        colorWell("Text", colorBinding(\.foreground))
                        colorWell("Bold Text", optionalColorBinding(\.boldForeground, fallback: \.foreground))
                    }
                    GridRow {
                        colorWell("Cursor", optionalColorBinding(\.cursor, fallback: \.foreground))
                        colorWell("Selection", optionalColorBinding(\.selection, fallback: \.foreground), opacity: true)
                    }
                }
            }
            GridRow {
                Text("Opacity")
                HStack(spacing: 10) {
                    Slider(value: binding(\.backgroundOpacity), in: 0.3...1).labelsHidden().frame(width: 200)
                    Text("\(Int((library.theme.backgroundOpacity * 100).rounded())) %").monospacedDigit()
                    Text("Background only; text stays opaque.").font(.caption).foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("ANSI Colors").gridCellAnchor(.topTrailing)
                Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        SwiftUI.Color.clear.frame(width: 1, height: 1)
                        ForEach(0..<8) { index in
                            Text(Self.ansiNames[index]).font(.caption).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                    ForEach(0..<2) { row in
                        GridRow {
                            Text(row == 0 ? "Normal" : "Bright").font(.caption).foregroundStyle(.secondary).fixedSize()
                            ForEach(0..<8) { index in
                                ColorPicker("ANSI \(row * 8 + index)", selection: ansiBinding(row * 8 + index),
                                            supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                    }
                }
            }
        }
    }

    private func colorWell (_ label: String, _ binding: Binding<SwiftUI.Color>, opacity: Bool = false) -> some View {
        HStack(spacing: 6) {
            ColorPicker(label, selection: binding, supportsOpacity: opacity).labelsHidden()
            Text(label)
        }
    }

    // MARK: Bindings

    private func binding<Value> (_ keyPath: WritableKeyPath<TerminalTheme, Value>) -> Binding<Value> {
        Binding(get: { library.theme[keyPath: keyPath] },
                set: { value in library.edit { $0[keyPath: keyPath] = value } })
    }

    private func colorBinding (_ keyPath: WritableKeyPath<TerminalTheme, TerminalThemeColor>) -> Binding<SwiftUI.Color> {
        Binding(get: { SwiftUI.Color(nsColor: library.theme[keyPath: keyPath].nsColor) },
                set: { color in library.edit { $0[keyPath: keyPath] = TerminalThemeColor(NSColor(color)).withAlpha(1) } })
    }

    private func optionalColorBinding (_ keyPath: WritableKeyPath<TerminalTheme, TerminalThemeColor?>,
                                       fallback: KeyPath<TerminalTheme, TerminalThemeColor>) -> Binding<SwiftUI.Color> {
        Binding(get: { SwiftUI.Color(nsColor: (library.theme[keyPath: keyPath] ?? library.theme[keyPath: fallback]).nsColor) },
                set: { color in library.edit { $0[keyPath: keyPath] = TerminalThemeColor(NSColor(color)) } })
    }

    private func ansiBinding (_ index: Int) -> Binding<SwiftUI.Color> {
        Binding(get: { SwiftUI.Color(nsColor: library.theme.ansi[index].nsColor) },
                set: { color in library.edit { $0.ansi[index] = TerminalThemeColor(NSColor(color)).withAlpha(1) } })
    }

    private enum CursorShape: Hashable { case block, underline, bar }

    private var cursorShape: CursorShape {
        switch library.theme.cursorStyle ?? .blinkBlock {
        case .blinkBlock, .steadyBlock: return .block
        case .blinkUnderline, .steadyUnderline: return .underline
        case .blinkBar, .steadyBar: return .bar
        }
    }

    private var cursorBlinks: Bool {
        switch library.theme.cursorStyle ?? .blinkBlock {
        case .blinkBlock, .blinkUnderline, .blinkBar: return true
        default: return false
        }
    }

    private func setCursor (shape: CursorShape, blink: Bool) {
        let style: CursorStyle
        switch shape {
        case .block: style = blink ? .blinkBlock : .steadyBlock
        case .underline: style = blink ? .blinkUnderline : .steadyUnderline
        case .bar: style = blink ? .blinkBar : .steadyBar
        }
        library.edit { $0.cursorStyle = style }
    }

    private var cursorShapeBinding: Binding<CursorShape> {
        Binding(get: { cursorShape }, set: { setCursor(shape: $0, blink: cursorBlinks) })
    }

    private var cursorBlinkBinding: Binding<Bool> {
        Binding(get: { cursorBlinks }, set: { setCursor(shape: cursorShape, blink: $0) })
    }

    // MARK: Fonts

    private struct FontChoice {
        let postScriptName: String
        let label: String
    }

    private static let systemFontChoice = FontChoice(postScriptName: "", label: "System Monospaced")

    private var fontSize: Double {
        library.theme.fontSize ?? Double(NSFont.systemFontSize)
    }

    private var fontChoices: [FontChoice] {
        let manager = NSFontManager.shared
        var choices = [Self.systemFontChoice]
        for family in manager.availableFontFamilies.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            guard !family.hasPrefix("."), let members = manager.availableMembers(ofFontFamily: family),
                  let regular = members.first(where: { ($0[1] as? String) == "Regular" }) ?? members.first,
                  let name = regular[0] as? String, let font = NSFont(name: name, size: 12) else {
                continue
            }
            if showsProportionalFonts || font.isFixedPitch {
                choices.append(FontChoice(postScriptName: name, label: family))
            }
        }
        if let current = library.theme.fontName, !choices.contains(where: { $0.postScriptName == current }) {
            choices.append(FontChoice(postScriptName: current,
                                      label: NSFont(name: current, size: 12)?.displayName ?? current))
        }
        return choices
    }

    private var fontNameBinding: Binding<String> {
        Binding(get: { library.theme.fontName ?? "" },
                set: { name in library.edit { $0.fontName = name.isEmpty ? nil : name } })
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(get: { fontSize }, set: { size in library.edit { $0.fontSize = size } })
    }

    // MARK: Actions

    /// Picks a theme, asking first when the current one has unsaved changes.
    private func pick (_ theme: TerminalTheme) {
        guard theme.name != library.theme.name || library.hasUnsavedChanges else { return }
        guard confirmUnsavedChanges() else { return }
        library.select(theme)
        message = nil
    }

    private func add (_ theme: TerminalTheme, note: String) {
        guard confirmUnsavedChanges() else { return }
        let added = library.add(theme)
        message = note + (added.name == theme.name ? "" : " Saved as “\(added.name)”.")
    }

    private func save () {
        guard library.hasUnsavedChanges else { return }
        let saved = library.save()
        message = "Saved “\(saved.name)”."
    }

    private func saveAs () {
        let suggestion = library.isBuiltIn ? "\(library.theme.name) (mine)" : "\(library.theme.name) copy"
        guard let name = askForName(title: "Save Theme As", button: "Save", value: library.uniqueName(suggestion)) else {
            return
        }
        let saved = library.saveAs(name: name)
        message = "Saved “\(saved.name)”."
    }

    private func rename (_ theme: TerminalTheme) {
        guard let name = askForName(title: "Rename Theme", button: "Rename", value: theme.name) else { return }
        if !library.rename(theme.name, to: name) {
            message = "“\(name)” is already used by another theme."
        }
    }

    private func delete (_ theme: TerminalTheme) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(theme.name)”?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        library.delete(theme.name)
    }

    /// Asks to save or discard unsaved changes. Returns false on Cancel.
    private func confirmUnsavedChanges () -> Bool {
        guard library.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save the changes to “\(library.theme.name)”?"
        alert.informativeText = library.isBuiltIn
            ? "Save keeps them as “\(library.saveName)”. Discard goes back to \(library.theme.name)."
            : "Discard goes back to the last saved “\(library.theme.name)”."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            library.save()
            return true
        case .alertSecondButtonReturn:
            library.discardChanges()
            return true
        default:
            return false
        }
    }

    private func askForName (title: String, button: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static let terminalType = UTType(filenameExtension: "terminal") ?? .propertyList
    private static let itermColorsType = UTType(filenameExtension: "itermcolors") ?? .propertyList

    private func importFile () {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.terminalType, Self.itermColorsType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let name = url.deletingPathExtension().lastPathComponent
            let theme = url.pathExtension.lowercased() == "itermcolors"
                ? try TerminalTheme(itermColors: data, name: name, base: library.theme)
                : try TerminalTheme(terminalProfile: data)
            add(theme, note: "Imported \(url.lastPathComponent).")
        } catch {
            message = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func export (_ theme: TerminalTheme) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(theme.name).terminal"
        panel.allowedContentTypes = [Self.terminalType, Self.itermColorsType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = url.pathExtension.lowercased() == "itermcolors"
                ? try theme.itermColorsData()
                : try theme.terminalProfileData()
            try data.write(to: url, options: .atomic)
            message = "Exported \(url.lastPathComponent)."
        } catch {
            message = "Could not export: \(error.localizedDescription)"
        }
    }
}

/// A live terminal showing sample output in a theme.
@available(macOS 13, *)
public struct TerminalThemePreview: NSViewRepresentable {
    public var theme: TerminalTheme

    public init (theme: TerminalTheme) {
        self.theme = theme
    }

    static let sample =
        "Last login: Fri Nov 13 09:41:00 on ttys001\r\n" +
        "\u{1b}[32muser@host\u{1b}[0m ~ % ls -G\r\n" +
        "\u{1b}[34mDocuments\u{1b}[0m  \u{1b}[34mProjects\u{1b}[0m  \u{1b}[31mbuild.sh\u{1b}[0m  \u{1b}[35mlink\u{1b}[0m  notes.txt\r\n" +
        "\u{1b}[31m- removed line\u{1b}[0m   \u{1b}[32m+ added line\u{1b}[0m   \u{1b}[33mwarning\u{1b}[0m   \u{1b}[36minfo\u{1b}[0m\r\n" +
        "\u{1b}[1mBold text\u{1b}[0m and regular text\r\n" +
        "\u{1b}[7mreverse video\u{1b}[0m  " +
        (0..<16).map { "\u{1b}[48;5;\($0)m  " }.joined() + "\u{1b}[0m\r\n" +
        "\u{1b}[32muser@host\u{1b}[0m ~ % "

    public func makeNSView (context: Context) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 500, height: 170), font: nil,
                                options: TerminalOptions(cols: 70, rows: 8, scrollback: 0))
        view.apply(theme: theme)
        view.feed(text: Self.sample)
        return view
    }

    public func updateNSView (_ view: TerminalView, context: Context) {
        view.apply(theme: theme)
    }
}
#endif
