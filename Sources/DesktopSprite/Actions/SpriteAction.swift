//
//  SpriteAction.swift
//  32-Bit Life
//
//  The extension point for "small macOS actions".
//
//  Adding a new action means writing one type conforming to `SpriteAction` and
//  registering it in `AppDelegate`. Nothing else needs to change: the sprite's
//  click handler and the menu bar both read from the registry.
//

import Combine
import Foundation

/// Something the companion can do when clicked or when chosen from the menu bar.
///
/// The descriptive properties are deliberately left non-isolated so SwiftUI can read
/// them for list identity and labelling; only ``perform()`` is confined to the main
/// actor, since that is the part that touches AppKit.
protocol SpriteAction {

    /// A stable identifier, used for lookup and as a SwiftUI list identity.
    var id: String { get }

    /// Human-readable name, shown in the menu bar.
    var title: String { get }

    /// An SF Symbol name shown alongside the title.
    var systemImage: String { get }

    /// Runs the action.
    @MainActor func perform()
}

/// The set of actions available to the companion.
///
/// Ordered rather than a dictionary, because the menu bar shows them in
/// registration order.
@MainActor
final class SpriteActionRegistry: ObservableObject {

    @Published private(set) var actions: [any SpriteAction] = []

    /// The action fired by clicking the sprite.
    ///
    /// Defaults to the first registered action if never set explicitly.
    @Published var defaultActionID: String?

    init(actions: [any SpriteAction] = []) {
        self.actions = actions
        self.defaultActionID = actions.first?.id
    }

    /// Adds an action. Re-registering an existing `id` replaces the previous entry.
    func register(_ action: any SpriteAction) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
        if defaultActionID == nil {
            defaultActionID = action.id
        }
    }

    /// Runs the action with the given identifier, if it exists.
    func perform(id: String) {
        actions.first { $0.id == id }?.perform()
    }

    /// Runs the default action, if one is set.
    func performDefaultAction() {
        guard let defaultActionID else { return }
        perform(id: defaultActionID)
    }
}
