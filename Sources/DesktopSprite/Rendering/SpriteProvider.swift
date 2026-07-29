//
//  SpriteProvider.swift
//  32-Bit Life
//
//  The seam between "what the sprite is doing" and "what pixels to draw".
//

import SwiftUI

/// Supplies artwork for a given state and frame index.
///
/// Two implementations ship with the app:
///
/// - ``PlaceholderSprite`` — built-in pixel art defined as character grids in
///   source. Always available, no assets required.
/// - ``SpriteSheet`` — slices frames out of a PNG in the app bundle.
///
/// Both return a plain SwiftUI `Image`, so ``DesktopSpriteView`` does not know or
/// care which one it is talking to. Dropping in real artwork is therefore a matter
/// of adding a PNG to the bundle; no view code changes.
protocol SpriteProvider {

    /// Artwork for the given state and frame, or `nil` if unavailable.
    ///
    /// - Parameters:
    ///   - state: The sprite's current state.
    ///   - frame: A zero-based frame index. Implementations must tolerate an index
    ///     out of range rather than trapping — the frame clock and the artwork can
    ///     briefly disagree during a state transition.
    func image(for state: SpriteState, frame: Int) -> Image?
}

// MARK: - Selection

enum SpriteProviderFactory {

    /// Returns the best available provider: the bundled sprite sheet if one is
    /// present, otherwise the built-in placeholder art.
    ///
    /// This is why dropping in a sprite sheet requires no code edit — the app looks
    /// for the asset at launch and silently upgrades itself if it finds one.
    static func bestAvailable(configuration: SpriteConfiguration) -> any SpriteProvider {
        if let sheet = SpriteSheet(configuration: configuration) {
            return sheet
        }
        return PlaceholderSprite()
    }
}
