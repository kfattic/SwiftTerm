//
//  AppDelegate.swift
//  MacTerminal
//
//  Created by Miguel de Icaza on 3/11/20.
//  Copyright © 2020 Miguel de Icaza. All rights reserved.
//

import Cocoa
import Combine
import SwiftUI
import SwiftTerm
@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet var loggingMenuItem: NSMenuItem?

    /// The terminal themes; see `showThemeSettings`.
    let themeLibrary = TerminalThemeLibrary()
    private var themeWindow: NSWindow?
    private var themeSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // MacTerminal → Settings… (⌘,) shows the theme settings.
        if let appMenu = NSApp.mainMenu?.items.first?.submenu,
           let settings = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
            settings.title = "Settings…"
            settings.target = self
            settings.action = #selector(showThemeSettings(_:))
        }
    }

    /// Shows `TerminalThemeSettingsView`. Once a theme is picked, every
    /// terminal window follows it, and new windows open with it.
    @objc func showThemeSettings(_ sender: Any?) {
        if themeWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Terminal Themes"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: TerminalThemeSettingsView(library: themeLibrary))
            window.center()
            themeWindow = window
            themeSubscription = themeLibrary.$theme.dropFirst().sink { theme in
                MainActor.assumeIsolated {
                    UserDefaults.standard.set(true, forKey: "UsesTerminalTheme")
                    ViewController.applyThemeToAllTerminals(theme)
                }
            }
        }
        themeWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let terminal = ViewController.lastTerminal {
            ViewController.closeTerminalUIWhenMetalIsIdle(terminal)
        }
    }


}
