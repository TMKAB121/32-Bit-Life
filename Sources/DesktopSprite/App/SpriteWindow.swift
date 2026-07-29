//
//  SpriteWindow.swift
//  32-Bit Life
//
//  The transparent floating window the sprite lives in.
//

import AppKit
import SwiftUI

/// A borderless, transparent, non-activating panel spanning the bottom of the screen.
///
/// This is an `NSPanel` rather than a plain `NSWindow` for one specific reason:
/// `.nonactivatingPanel` is only honoured on panels, and without it clicking the
/// sprite would pull keyboard focus away from whatever the user was actually
/// working in. A desktop companion must never steal focus.
final class SpriteWindow: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Transparency. All three are required — a clear background colour alone
        // still leaves an opaque window with a drop shadow.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Float above ordinary application windows. `.statusBar` sits above
        // `.floating`, so the sprite stays visible over utility panels too, while
        // remaining below the menu bar itself.
        level = .statusBar

        // - canJoinAllSpaces:   follow the user between Spaces instead of living on one
        // - stationary:         do not slide around during Exposé / Mission Control
        // - fullScreenAuxiliary: remain visible over full-screen apps
        // - ignoresCycle:       stay out of Cmd-` window cycling
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Click-through by default. `SpriteViewModel` flips this off for the few
        // points the sprite occupies, and back on the moment the cursor leaves.
        ignoresMouseEvents = true

        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // The companion is decorative; it should not appear in window menus or be
        // restored by the system on relaunch.
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    /// Required so the panel can receive clicks at all. Combined with
    /// `.nonactivatingPanel`, accepting key status does not activate the app.
    override var canBecomeKey: Bool { true }

    /// Never the main window — that is reserved for real document windows.
    override var canBecomeMain: Bool { false }
}

/// An `NSHostingView` that accepts the first click.
///
/// By default, clicking into an inactive application is consumed as an activation
/// click and never reaches the view. Since this app is an agent that is almost never
/// frontmost, that would make the sprite feel dead — the first click would do nothing
/// and only a second click would register. Returning `true` here delivers every click
/// straight to SwiftUI.
final class SpriteHostingView<Content: View>: NSHostingView<Content> {

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
