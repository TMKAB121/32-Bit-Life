//
//  LoginItemController.swift
//  32-Bit Life
//
//  Registers the app as a login item so the companion survives a reboot.
//
//  Wraps `SMAppService`, which replaced the old `SMLoginItemSetEnabled` helper-bundle
//  dance in macOS 13 and needs no helper target at all.
//

import ServiceManagement
import os

/// Manages whether the app opens automatically at login.
///
/// ### Testing this
///
/// `SMAppService` registers *the path the app currently occupies*. Run from Xcode,
/// that is a path inside DerivedData which gets wiped on the next clean build — so
/// registration appears to succeed and then silently stops working. This is only
/// meaningfully testable once the app is signed and living in `/Applications`.
///
/// Every failure here is logged and swallowed. Failing to become a login item is a
/// disappointment, not a reason for a background app to misbehave at launch.
@MainActor
final class LoginItemController: ObservableObject {

    private static let logger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "LoginItem")

    /// The current registration status, as macOS sees it.
    @Published private(set) var status: SMAppService.Status = .notRegistered

    init() {
        refresh()
    }

    /// Whether the app is currently registered and approved.
    var isEnabled: Bool { status == .enabled }

    /// Whether macOS is waiting for the user to approve the login item.
    ///
    /// This happens when the user has previously disabled the item in System Settings.
    /// Registering again succeeds but the status stays here until they approve it, so
    /// the menu offers a shortcut to the right settings pane.
    var requiresApproval: Bool { status == .requiresApproval }

    /// Re-reads the status from the system.
    func refresh() {
        status = SMAppService.mainApp.status
    }

    /// Registers or unregisters the app as a login item.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Self.logger.info("Registered as a login item.")
            } else {
                try SMAppService.mainApp.unregister()
                Self.logger.info("Unregistered as a login item.")
            }
        } catch {
            // Common causes: the app is unsigned, or is running from a location macOS
            // will not register (DerivedData, a disk image, the Downloads quarantine).
            Self.logger.error("Could not change login item state: \(error.localizedDescription, privacy: .public)")
        }
        // Always re-read rather than assuming the requested value took effect —
        // registration can succeed into `.requiresApproval` rather than `.enabled`.
        refresh()
    }

    /// Opens System Settings at the Login Items pane.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
