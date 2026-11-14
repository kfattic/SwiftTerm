//
//  TerminalThemeLibraryTests.swift
//  SwiftTermTests
//
//  TerminalThemeLibrary: picking, editing, Save / Save As, rename, delete,
//  import, storage, and a smoke test of TerminalThemeSettingsView.
//

#if os(macOS) && !SWIFTTERM_EMBEDDED
import AppKit
import SwiftUI
import Testing
@testable import SwiftTerm

private final class MemoryThemeStorage: TerminalThemeStorage {
    var current: TerminalTheme?
    var saved: [TerminalTheme] = []
    func loadCurrentTheme () -> TerminalTheme? { current }
    func saveCurrentTheme (_ theme: TerminalTheme) { current = theme }
    func loadSavedThemes () -> [TerminalTheme] { saved }
    func saveSavedThemes (_ themes: [TerminalTheme]) { saved = themes }
}

@Suite("Terminal theme library")
@MainActor
struct TerminalThemeLibraryTests {
    private func makeLibrary (_ storage: MemoryThemeStorage = MemoryThemeStorage()) -> TerminalThemeLibrary {
        TerminalThemeLibrary(storage: storage)
    }

    @Test func startsWithTheFirstBuiltInTheme() {
        let library = makeLibrary()
        #expect(library.theme == TerminalTheme.presets[0])
        #expect(library.isBuiltIn)
        #expect(library.hasUnsavedChanges == false)
    }

    @Test func editingMarksUnsavedChangesAndKeepsTheName() {
        let library = makeLibrary()
        library.edit { $0.fontSize = 18; $0.name = "ignored" }
        #expect(library.theme.name == TerminalTheme.presets[0].name)
        #expect(library.theme.fontSize == 18)
        #expect(library.hasUnsavedChanges)
        library.discardChanges()
        #expect(library.hasUnsavedChanges == false)
        #expect(library.theme.fontSize == TerminalTheme.presets[0].fontSize)
    }

    @Test func savingABuiltInThemeMakesAnOwnCopy() {
        let library = makeLibrary()
        library.select(.dracula)
        library.edit { $0.fontSize = 16 }
        #expect(library.saveName == "Dracula (mine)")
        let saved = library.save()
        #expect(saved.name == "Dracula (mine)")
        #expect(library.theme.name == "Dracula (mine)")
        #expect(library.savedThemes.map(\.name) == ["Dracula (mine)"])
        #expect(library.hasUnsavedChanges == false)
        #expect(library.isBuiltIn == false)
        // The built-in theme is unchanged.
        #expect(library.builtInThemes.contains(.dracula))

        // Saving again updates the same copy.
        library.edit { $0.fontSize = 20 }
        library.save()
        #expect(library.savedThemes.count == 1)
        #expect(library.savedThemes[0].fontSize == 20)

        // Another copy of the same built-in theme gets a number.
        library.select(.dracula)
        library.edit { $0.fontSize = 10 }
        #expect(library.save().name == "Dracula (mine) 2")
    }

    @Test func saveAsKeepsTheOriginal() {
        let library = makeLibrary()
        library.select(.solarizedDark)
        library.save()
        let original = library.theme
        library.edit { $0.textAntialiasing = false }
        let copy = library.saveAs(name: "Crisp")
        #expect(copy.name == "Crisp")
        #expect(library.theme.name == "Crisp")
        #expect(library.savedThemes.first { $0.name == original.name } == original)
        #expect(library.saveAs(name: "Crisp").name == "Crisp 2")
    }

    @Test func renameAndDelete() {
        let library = makeLibrary()
        library.add(.dracula)
        #expect(library.theme.name == "Dracula 2")
        #expect(library.rename("Dracula 2", to: "Night"))
        #expect(library.theme.name == "Night")
        #expect(library.rename("Night", to: "Homebrew") == false)
        #expect(library.rename("Nope", to: "Other") == false)
        library.delete("Night")
        #expect(library.savedThemes.isEmpty)
        #expect(library.theme == library.builtInThemes[0])
    }

    @Test func pickingAThemeDropsUnsavedChanges() {
        let library = makeLibrary()
        library.edit { $0.fontSize = 30 }
        library.select(.solarizedLight)
        #expect(library.theme == .solarizedLight)
        library.select(TerminalTheme.presets[0])
        #expect(library.theme.fontSize == TerminalTheme.presets[0].fontSize)
    }

    @Test func storageKeepsTheCurrentAndSavedThemes() {
        let storage = MemoryThemeStorage()
        let library = makeLibrary(storage)
        library.select(.dracula)
        library.edit { $0.fontSize = 17 }
        library.save()
        library.edit { $0.fontSize = 19 }
        let reopened = makeLibrary(storage)
        #expect(reopened.savedThemes.map(\.name) == ["Dracula (mine)"])
        #expect(reopened.theme.fontSize == 19)
        #expect(reopened.hasUnsavedChanges)
    }

    @Test func userDefaultsStorageRoundTrips() throws {
        let suite = "SwiftTermTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsTerminalThemeStorage(defaults: defaults, keyPrefix: "T")
        #expect(storage.loadCurrentTheme() == nil)
        #expect(storage.loadSavedThemes().isEmpty)
        storage.saveCurrentTheme(.homebrew)
        storage.saveSavedThemes([.dracula, .solarizedDark])
        #expect(storage.loadCurrentTheme() == .homebrew)
        #expect(storage.loadSavedThemes() == [.dracula, .solarizedDark])
    }

    @Test func settingsViewRenders() throws {
        let library = makeLibrary()
        let host = NSHostingView(rootView: TerminalThemeSettingsView(library: library))
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 1100)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide > 0)
        // The view follows the library.
        library.select(.dracula)
        host.layoutSubtreeIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
    }
}
#endif
