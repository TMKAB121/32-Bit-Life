//
//  BuiltInActions.swift
//  32-Bit Life
//
//  The actions that ship with the prototype. Each one is small on purpose —
//  they are templates as much as features.
//

import AppKit
import os
import UserNotifications

private let actionLogger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "Actions")

// MARK: - Log

/// Does nothing but write to the log.
///
/// This is the copy-paste template for new actions, and a safe default to bind to
/// the sprite's click while you are still deciding what it should do.
struct LogAction: SpriteAction {
    let id = "log"
    let title = "Log a message"
    let systemImage = "text.alignleft"

    var message: String = "The sprite was clicked."

    func perform() {
        actionLogger.info("\(message, privacy: .public)")
    }
}

// MARK: - Open a link

/// Opens a URL in the user's default handler.
///
/// Named `OpenLinkAction` rather than `OpenURLAction` to avoid colliding with
/// SwiftUI's environment type of that name.
struct OpenLinkAction: SpriteAction {
    let id: String
    let title: String
    let systemImage = "safari"
    let url: URL

    init(id: String = "open-link", title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }

    func perform() {
        // Under the App Sandbox this works for `http`, `https`, `mailto` and other
        // registered URL schemes. Launching an arbitrary `.app` by file path does not
        // — see the sandboxing note in README.md.
        if !NSWorkspace.shared.open(url) {
            actionLogger.error("Could not open \(url.absoluteString, privacy: .public)")
        }
    }
}

// MARK: - System sound

/// Plays a built-in macOS alert sound.
///
/// Sound names are the files in `/System/Library/Sounds` — "Pop", "Tink", "Submarine",
/// "Funk", "Glass", "Blow", and so on.
struct PlaySystemSoundAction: SpriteAction {
    let id = "system-sound"
    let title = "Play a sound"
    let systemImage = "speaker.wave.2"

    var soundName: String = "Pop"

    func perform() {
        guard let sound = NSSound(named: soundName) else {
            actionLogger.error("No system sound named '\(soundName, privacy: .public)'.")
            return
        }
        sound.stop()  // Restart from the beginning if it is still playing.
        sound.play()
    }
}

// MARK: - Notification

/// Posts a local notification banner.
///
/// Authorisation is requested lazily, on first use, rather than at launch: an agent
/// app that fires a permission prompt the instant it starts is obnoxious, and the
/// prompt makes far more sense once the user has actually asked for a notification.
@MainActor
final class PostNotificationAction: SpriteAction {
    // Explicitly non-isolated so they can satisfy the protocol's non-isolated
    // requirements and be read by SwiftUI for menu labels and list identity.
    nonisolated let id = "notification"
    nonisolated let title = "Send a notification"
    nonisolated let systemImage = "bell"

    private let body: String
    private var hasRequestedAuthorization = false

    init(body: String = "Still here, still running along the bottom of your screen.") {
        self.body = body
    }

    func perform() {
        // `UNUserNotificationCenter.current()` traps if the app has no bundle
        // identifier, which happens when running an unbundled binary. Fail soft.
        guard Bundle.main.bundleIdentifier != nil else {
            actionLogger.error("Notifications need a bundled app with a bundle identifier.")
            return
        }

        let center = UNUserNotificationCenter.current()
        guard hasRequestedAuthorization else {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    actionLogger.error("Notification authorisation failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                guard granted else {
                    actionLogger.info("Notification authorisation denied.")
                    return
                }
                Task { @MainActor [weak self] in
                    self?.deliver(via: center)
                }
            }
            return
        }

        deliver(via: center)
    }

    private func deliver(via center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "32-Bit Life"
        content.body = body
        content.sound = .default

        // A nil trigger delivers immediately.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                actionLogger.error("Could not post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
