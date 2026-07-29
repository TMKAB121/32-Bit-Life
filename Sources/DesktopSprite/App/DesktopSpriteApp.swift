//
//  DesktopSpriteApp.swift
//  32-Bit Life
//
//  Application entry point.
//
//  There is no `WindowGroup` here on purpose. The only real window is the
//  transparent companion strip, which `AppDelegate` creates directly so it can
//  configure the `NSWindow` properties SwiftUI does not expose.
//
//  The `MenuBarExtra` is not optional garnish: with `LSUIElement` set the app has
//  no Dock icon and no menu bar of its own, so without a status item there would
//  be no way to quit it.
//

import SwiftUI

@main
struct DesktopSpriteApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("32-Bit Life", systemImage: "gamecontroller.fill") {
            MenuBarContent(appDelegate: appDelegate)
        }
    }
}

/// The status-item menu.
private struct MenuBarContent: View {

    @ObservedObject var appDelegate: AppDelegate
    @ObservedObject private var registry: SpriteActionRegistry

    @MainActor
    init(appDelegate: AppDelegate) {
        // Property wrappers must be initialised through their underscored storage.
        _appDelegate = ObservedObject(wrappedValue: appDelegate)
        _registry = ObservedObject(wrappedValue: appDelegate.actionRegistry)
    }

    var body: some View {
        Toggle("Show Sprite", isOn: $appDelegate.isSpriteVisible)

        Divider()

        ForEach(registry.actions, id: \.id) { action in
            Button {
                action.perform()
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }

        Divider()

        Button("Quit 32-Bit Life") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
