//
//  SpriteProvider.swift
//  32-Bit Life
//
//  The seam between "which animation is playing" and "what pixels to draw".
//

import SwiftUI

/// Supplies artwork for a given clip and frame index.
///
/// Two implementations ship with the app:
///
/// - ``PlaceholderSprite`` — built-in pixel art defined as character grids in
///   source. Always available, no assets required.
/// - ``SpriteSheetLibrary`` — slices frames out of PNGs in the app bundle.
///
/// Both return a plain SwiftUI `Image`, so ``DesktopSpriteView`` does not know or
/// care which one it is talking to. Dropping in real artwork is therefore a matter
/// of adding a PNG to the bundle; no view code changes.
///
/// Note the key is a ``ClipID`` and not a `SpriteState`. That is what allows artwork to
/// exist for animations no behaviour state maps to — flourishes, and the companion
/// effects they spawn.
protocol SpriteProvider {

    /// Artwork for the given clip and frame, or `nil` if unavailable.
    ///
    /// - Parameters:
    ///   - clip: The clip being played.
    ///   - frame: A zero-based frame index. Implementations must tolerate an index
    ///     out of range rather than trapping — the frame clock and the artwork can
    ///     briefly disagree during a transition.
    func image(for clip: ClipID, frame: Int) -> Image?

    /// Whether this provider can draw the clip at all.
    ///
    /// Asked once at launch so unplayable flourishes can be pruned from the catalogue.
    /// Without it, a manifest describing a clip the placeholder art has no pose for would
    /// have the sprite periodically stop and perform a red error rectangle.
    func hasArtwork(for clip: ClipID) -> Bool
}

extension SpriteProvider {

    func hasArtwork(for clip: ClipID) -> Bool {
        image(for: clip, frame: 0) != nil
    }
}

// MARK: - Selection

/// The artwork and the animation catalogue, resolved together.
///
/// They are returned as a pair because neither is complete without the other: the
/// catalogue's frame counts come from the artwork, and the artwork is sliced according
/// to the catalogue's rows.
struct SpriteAssets {
    let provider: any SpriteProvider
    let catalogue: AnimationCatalogue
}

enum SpriteProviderFactory {

    /// Returns the best available artwork — bundled sprite sheets if present, otherwise
    /// the built-in placeholder — together with the catalogue describing it.
    ///
    /// This is why dropping in a sprite sheet requires no code edit: the app reads the
    /// manifest, loads whatever sheets it names, derives the frame counts from the
    /// pixels, and silently upgrades itself.
    ///
    /// The order matters and reads backwards at first glance:
    ///
    /// 1. Decode the manifest — it is the only thing that knows the sheets' frame sizes.
    /// 2. Load those sheets, which yields the drawn frame count of every row.
    /// 3. Resolve the catalogue against those counts.
    /// 4. Slice the frames, now that the catalogue says which rows are which clips.
    static func bestAvailable(configuration: SpriteConfiguration, bundle: Bundle = .main) -> SpriteAssets {
        let manifest = AnimationCatalogue.loadManifest(configuration: configuration, bundle: bundle)
        let descriptors = AnimationCatalogue.sheetDescriptors(manifest: manifest, configuration: configuration)

        if var library = SpriteSheetLibrary(sheets: descriptors, bundle: bundle) {
            let catalogue = AnimationCatalogue.resolve(
                manifest: manifest,
                configuration: configuration,
                sheets: descriptors,
                frameCounts: library
            )
            library.sliceFrames(for: catalogue)
            return SpriteAssets(
                provider: library,
                catalogue: catalogue.filteringFlourishes { library.hasArtwork(for: $0) }
            )
        }

        // No sheet at all. The placeholder has poses for the five behaviour clips and
        // nothing else, so any flourish the manifest describes is pruned here.
        let placeholder = PlaceholderSprite()
        let catalogue = AnimationCatalogue.resolve(
            manifest: manifest,
            configuration: configuration,
            sheets: descriptors,
            frameCounts: nil
        )
        return SpriteAssets(
            provider: placeholder,
            catalogue: catalogue.filteringFlourishes { placeholder.hasArtwork(for: $0) }
        )
    }
}
