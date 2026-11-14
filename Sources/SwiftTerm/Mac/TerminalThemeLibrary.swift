//
//  TerminalThemeLibrary.swift
//  SwiftTerm
//
//  The state behind TerminalThemeSettingsView: the theme in use, the themes a
//  person saved, and whether the theme in use has unsaved changes. It has no
//  UI, so an app can drive it from its own settings screen too.
//

#if os(macOS) && !SWIFTTERM_EMBEDDED
import AppKit
import Combine

/// Where a ``TerminalThemeLibrary`` keeps its themes.
public protocol TerminalThemeStorage {
    /// The theme in use when the library was last changed, or `nil` the first time.
    func loadCurrentTheme () -> TerminalTheme?
    func saveCurrentTheme (_ theme: TerminalTheme)
    /// The themes the person saved, in order.
    func loadSavedThemes () -> [TerminalTheme]
    func saveSavedThemes (_ themes: [TerminalTheme])
}

/// Keeps the themes in `UserDefaults` as JSON.
public struct UserDefaultsTerminalThemeStorage: TerminalThemeStorage {
    let defaults: UserDefaults
    let currentKey: String
    let savedKey: String

    /// - Parameters:
    ///   - defaults: The defaults to use; `.standard` by default.
    ///   - keyPrefix: The prefix of the two keys the storage writes.
    public init (defaults: UserDefaults = .standard, keyPrefix: String = "SwiftTermTheme") {
        self.defaults = defaults
        currentKey = keyPrefix + ".current"
        savedKey = keyPrefix + ".saved"
    }

    public func loadCurrentTheme () -> TerminalTheme? {
        defaults.data(forKey: currentKey).flatMap { try? JSONDecoder().decode(TerminalTheme.self, from: $0) }
    }

    public func saveCurrentTheme (_ theme: TerminalTheme) {
        defaults.set(try? JSONEncoder().encode(theme), forKey: currentKey)
    }

    public func loadSavedThemes () -> [TerminalTheme] {
        defaults.data(forKey: savedKey).flatMap { try? JSONDecoder().decode([TerminalTheme].self, from: $0) } ?? []
    }

    public func saveSavedThemes (_ themes: [TerminalTheme]) {
        defaults.set(try? JSONEncoder().encode(themes), forKey: savedKey)
    }
}

/// The theme in use, the built-in themes and the person's saved themes.
///
/// Themes are told apart by name: saved themes have unique names that are not
/// the name of a built-in theme. Changes to the theme in use (``edit(_:)``)
/// apply right away, and are kept as the theme in use, but a saved theme only
/// changes on ``save()``. Saving a changed built-in theme stores it as
/// "<name> (mine)".
///
/// Apply ``theme`` to your terminal views whenever it changes, for example:
///
/// ```swift
/// library.$theme.sink { terminalView.apply(theme: $0) }
/// ```
@MainActor
public final class TerminalThemeLibrary: ObservableObject {
    /// The theme in use, with any unsaved changes.
    @Published public private(set) var theme: TerminalTheme
    /// The person's saved themes.
    @Published public private(set) var savedThemes: [TerminalTheme]
    /// The built-in themes.
    public let builtInThemes: [TerminalTheme]

    private let storage: TerminalThemeStorage

    /// - Parameters:
    ///   - storage: Where themes are kept; `UserDefaults` by default.
    ///   - builtInThemes: The themes that cannot be changed or deleted.
    ///   - defaultTheme: The theme in use when storage has none; the first
    ///     built-in theme when `nil`.
    public init (storage: TerminalThemeStorage = UserDefaultsTerminalThemeStorage(),
                 builtInThemes: [TerminalTheme] = TerminalTheme.presets,
                 defaultTheme: TerminalTheme? = nil)
    {
        self.storage = storage
        self.builtInThemes = builtInThemes
        savedThemes = storage.loadSavedThemes()
        theme = storage.loadCurrentTheme() ?? defaultTheme ?? builtInThemes.first
            ?? TerminalTheme(name: "Default", foreground: TerminalThemeColor(red: 1, green: 1, blue: 1),
                             background: TerminalThemeColor(red: 0, green: 0, blue: 0))
    }

    /// The saved or built-in theme that ``theme`` was picked from; `nil` when
    /// it was deleted.
    public var baseline: TerminalTheme? {
        savedThemes.first { $0.name == theme.name } ?? builtInThemes.first { $0.name == theme.name }
    }

    /// True when ``theme`` was picked from a built-in theme.
    public var isBuiltIn: Bool {
        !savedThemes.contains { $0.name == theme.name } && builtInThemes.contains { $0.name == theme.name }
    }

    /// True when ``theme`` differs from the theme it was picked from.
    public var hasUnsavedChanges: Bool {
        guard let baseline else { return true }
        return !baseline.hasSameLook(as: theme)
    }

    /// The name ``save()`` uses: the theme's own name, or "<name> (mine)" for
    /// a built-in theme.
    public var saveName: String {
        isBuiltIn ? uniqueName("\(theme.name) (mine)") : theme.name
    }

    /// Changes the theme in use. The change is kept as the theme in use, but
    /// is saved only by ``save()`` or ``saveAs(name:)``.
    public func edit (_ change: (inout TerminalTheme) -> Void) {
        var edited = theme
        change(&edited)
        edited.name = theme.name
        guard !edited.hasSameLook(as: theme) else { return }
        setTheme(edited)
    }

    /// Uses `theme`, dropping unsaved changes to the current one.
    public func select (_ theme: TerminalTheme) {
        setTheme(theme)
    }

    /// Drops the unsaved changes.
    public func discardChanges () {
        if let baseline { setTheme(baseline) }
    }

    /// Saves the changes: a saved theme is updated, a built-in theme is saved
    /// as "<name> (mine)". Returns the saved theme.
    @discardableResult
    public func save () -> TerminalTheme {
        var saved = theme
        if let index = savedThemes.firstIndex(where: { $0.name == theme.name }) {
            savedThemes[index] = saved
        } else {
            saved.name = saveName
            savedThemes.append(saved)
        }
        storage.saveSavedThemes(savedThemes)
        setTheme(saved)
        return saved
    }

    /// Saves the theme in use under a new name and uses it. The theme it was
    /// picked from keeps its last saved version. A name that is taken gets a
    /// number.
    @discardableResult
    public func saveAs (name: String) -> TerminalTheme {
        var saved = theme
        saved.name = uniqueName(name)
        savedThemes.append(saved)
        storage.saveSavedThemes(savedThemes)
        setTheme(saved)
        return saved
    }

    /// Adds a theme, for example an imported one, as a saved theme and uses it.
    @discardableResult
    public func add (_ theme: TerminalTheme) -> TerminalTheme {
        var added = theme
        added.name = uniqueName(theme.name)
        savedThemes.append(added)
        storage.saveSavedThemes(savedThemes)
        setTheme(added)
        return added
    }

    /// Renames a saved theme. Returns false when there is no saved theme with
    /// that name or the new name is taken.
    @discardableResult
    public func rename (_ name: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = savedThemes.firstIndex(where: { $0.name == name }), !trimmed.isEmpty,
              trimmed == name || !isTaken(trimmed) else {
            return false
        }
        savedThemes[index].name = trimmed
        storage.saveSavedThemes(savedThemes)
        if theme.name == name {
            var renamed = theme
            renamed.name = trimmed
            setTheme(renamed)
        }
        return true
    }

    /// Deletes a saved theme. When it is in use, the first built-in theme is used.
    public func delete (_ name: String) {
        guard savedThemes.contains(where: { $0.name == name }) else { return }
        savedThemes.removeAll { $0.name == name }
        storage.saveSavedThemes(savedThemes)
        if theme.name == name, let first = builtInThemes.first {
            setTheme(first)
        }
    }

    /// `base`, or `base` followed by the first free number.
    public func uniqueName (_ base: String) -> String {
        guard isTaken(base) else { return base }
        var number = 2
        while isTaken("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func isTaken (_ name: String) -> Bool {
        builtInThemes.contains { $0.name == name } || savedThemes.contains { $0.name == name }
    }

    private func setTheme (_ newTheme: TerminalTheme) {
        theme = newTheme
        storage.saveCurrentTheme(newTheme)
    }
}

extension TerminalTheme {
    /// The profiles in Apple Terminal's preferences, sorted by name. Empty when
    /// the app cannot read them, for example in the App Sandbox.
    public static func appleTerminalProfiles () -> [TerminalTheme] {
        let settings = UserDefaults(suiteName: "com.apple.Terminal")?.dictionary(forKey: "Window Settings") ?? [:]
        return settings.compactMap { name, value in
            (value as? [String: Any]).map { TerminalTheme(terminalProfile: $0, name: name) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
#endif
