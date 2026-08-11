//
//  AppDelegate.swift
//  32-Bit Life
//
//  Window creation and macOS lifecycle.
//
//  Owns the companion window, the view model, and the action registry, and keeps
//  the window correctly placed as the screen configuration changes underneath it.
//

import AppKit
import Combine
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    private static let logger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "AppDelegate")

    // MARK: - Owned objects

    let configuration = SpriteConfiguration.default
    let actionRegistry = SpriteActionRegistry()
    let loginItem = LoginItemController()

    /// The artwork and the animation catalogue describing it.
    ///
    /// Resolved together and before the view model, because the catalogue is what tells
    /// the view model how many frames each clip has — and the catalogue cannot be built
    /// until the sheets have been read, since the frame counts come out of the pixels.
    private(set) lazy var assets = SpriteProviderFactory.bestAvailable(configuration: configuration)

    private(set) lazy var viewModel = SpriteViewModel(
        configuration: configuration,
        catalogue: assets.catalogue,
        actionRegistry: actionRegistry
    )

    /// Whether the sprite is currently on screen. Bound to the menu-bar toggle.
    @Published var isSpriteVisible = true {
        didSet {
            guard oldValue != isSpriteVisible else { return }
            isSpriteVisible ? showSprite() : hideSprite()
        }
    }

    private var window: SpriteWindow?

    /// Observer tokens paired with the centre they came from — `NSWorkspace` has its
    /// own notification centre, and a token must be removed from the centre that
    /// issued it.
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerActions()
        installWindow()
        registerObservers()
        viewModel.host = self
        viewModel.start()
        Self.logger.info("32-Bit Life launched.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
        for entry in observers {
            entry.center.removeObserver(entry.token)
        }
        observers.removeAll()
    }

    /// This app has no windows to reopen; the sprite is always there.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    /// Clicking the menu-bar item activates the app, which makes this a convenient
    /// moment to pick up any login-item change the user made in System Settings.
    func applicationDidBecomeActive(_ notification: Notification) {
        loginItem.refresh()
    }

    // MARK: - Actions

    /// Builds the action set offered by the sprite and the menu bar.
    ///
    /// Edit this method to change what clicking the sprite does. Every action is a
    /// ``SpriteAction``; see `BuiltInActions.swift` for the shipped examples.
    private func registerActions() {
        actionRegistry.register(PlaySystemSoundAction(soundName: "Pop"))
        actionRegistry.register(PostNotificationAction())
        if let url = URL(string: "https://developer.apple.com/documentation/appkit") {
            actionRegistry.register(OpenLinkAction(title: "Open AppKit docs", url: url))
        }
        actionRegistry.register(LogAction())

        // Clicking the sprite plays a sound; everything else is available from the
        // menu bar. Change this to any registered action's `id`.
        actionRegistry.defaultActionID = "system-sound"
    }

    // MARK: - Window

    private func installWindow() {
        guard let screen = ScreenGeometry.hostScreen() else {
            Self.logger.error("No screen available; the sprite cannot be placed.")
            return
        }

        let frame = ScreenGeometry.stripFrame(for: screen, configuration: configuration)

        let window = SpriteWindow(contentRect: frame)
        let hostingView = SpriteHostingView(
            rootView: DesktopSpriteView(viewModel: viewModel, provider: assets.provider)
        )
        window.contentView = hostingView
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the window must
        // appear without the app activating or taking focus from the user.
        window.orderFrontRegardless()

        self.window = window
        viewModel.updateStripSize(frame.size)
    }

    private func showSprite() {
        window?.orderFrontRegardless()
        viewModel.resume()
    }

    private func hideSprite() {
        viewModel.pause()
        window?.orderOut(nil)
    }

    // MARK: - System observation

    private func registerObservers() {
        // The Dock can be resized, hidden, or moved to another edge, and displays can
        // be added, removed, or have their resolution changed — all of which move the
        // line the sprite stands on. This notification covers every one of them.
        observe(NSApplication.didChangeScreenParametersNotification, on: .default) { [weak self] in
            self?.repositionWindow()
        }

        // Suspend while nobody can see the sprite. On a laptop this is the difference
        // between a background app that costs battery and one that does not.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, on: workspaceCenter) { [weak self] in
            self?.viewModel.pause()
        }
        observe(NSWorkspace.screensDidSleepNotification, on: workspaceCenter) { [weak self] in
            self?.viewModel.pause()
        }
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter) { [weak self] in
            self?.resumeIfVisible()
        }
        observe(NSWorkspace.screensDidWakeNotification, on: workspaceCenter) { [weak self] in
            self?.resumeIfVisible()
        }
    }

    private func observe(
        _ name: Notification.Name,
        on center: NotificationCenter,
        handler: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            // Delivery is on `.main`, so main-actor isolation already holds.
            MainActor.assumeIsolated { handler() }
        }
        observers.append((center: center, token: token))
    }

    private func resumeIfVisible() {
        guard isSpriteVisible else { return }
        viewModel.resume()
    }

    private func repositionWindow() {
        guard let window, let screen = ScreenGeometry.hostScreen() else { return }
        let frame = ScreenGeometry.stripFrame(for: screen, configuration: configuration)
        window.setFrame(frame, display: true)
        viewModel.updateStripSize(frame.size)
        Self.logger.debug("Repositioned to \(NSStringFromRect(frame), privacy: .public).")
    }
}

// MARK: - SpriteHost

extension AppDelegate: SpriteHost {

    var stripFrame: CGRect {
        window?.frame ?? .zero
    }

    func setClickThrough(_ enabled: Bool) {
        window?.ignoresMouseEvents = enabled
    }
}
