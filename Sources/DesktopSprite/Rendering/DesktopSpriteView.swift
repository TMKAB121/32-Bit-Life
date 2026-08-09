//
//  DesktopSpriteView.swift
//  32-Bit Life
//
//  The SwiftUI layer. Deliberately dumb: no timers, no physics, no decisions —
//  it reads the view model and draws. All logic lives in `SpriteViewModel`.
//

import SwiftUI

/// Renders the sprite inside the transparent companion window.
struct DesktopSpriteView: View {

    @ObservedObject var viewModel: SpriteViewModel

    /// Where the artwork comes from. See ``SpriteProvider``.
    let provider: any SpriteProvider

    /// The backing scale factor of whichever display the window is currently on.
    ///
    /// SwiftUI keeps this up to date when the window moves between a Retina and a
    /// non-Retina screen, which is exactly what ``pixelSnapped(_:)`` needs.
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The window is transparent and full-width. This background exists only
            // to define the layout bounds; it must never take hit tests, or the strip
            // would capture clicks meant for the desktop behind it.
            Color.clear
                .allowsHitTesting(false)

            // Effects behind the sprite, then the sprite, then effects in front. The
            // view model publishes them already sorted by `z`, so this is a partition
            // rather than a sort.
            effectLayers(viewModel.effects.filter { $0.z < 0 })

            sprite
                .frame(
                    width: viewModel.configuration.spriteSize.width,
                    height: viewModel.configuration.spriteSize.height
                )
                // The tap gesture is attached *before* `.position`, and that ordering
                // matters: `.position` expands its view to fill the available space,
                // so a gesture applied afterwards would make the entire full-width
                // strip tappable instead of just the sprite.
                .onTapGesture {
                    viewModel.handleTap()
                }
                .position(pixelSnapped(viewModel.spriteCenter))

            effectLayers(viewModel.effects.filter { $0.z >= 0 })
        }
        .ignoresSafeArea()
    }

    /// Draws companion animations — a struck block, a charge glow, a puff of dust.
    ///
    /// Note what is deliberately absent: any gesture. Effects are decoration and must
    /// never take hit tests, or a large one would hand the full-width strip back the
    /// ability to swallow desktop clicks — the exact problem `ignoresMouseEvents` exists
    /// to solve.
    @ViewBuilder
    private func effectLayers(_ renders: [EffectRender]) -> some View {
        ForEach(renders) { render in
            if let image = provider.image(for: render.clip, frame: render.frame) {
                image
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .frame(width: render.size.width, height: render.size.height)
                    .allowsHitTesting(false)
                    .position(pixelSnapped(render.position))
            }
        }
    }

    /// Rounds a point onto the physical pixel grid.
    ///
    /// The view model advances position by `speed × delta`, which lands the sprite on
    /// fractional point values. Pixel art cannot survive that: at 4× scale, a sprite
    /// sitting half a point off the grid renders some of its pixel columns one device
    /// pixel wider than others, and the pattern shifts every frame — the sprite visibly
    /// shimmers and crawls as it runs. Rounding the centre to whole device pixels keeps
    /// every source pixel the same size from frame to frame.
    ///
    /// This snaps to *device* pixels, which keeps motion smooth. Snapping to whole
    /// *source* pixels instead — `spriteSize.width / 16` points at a time — would give
    /// the stepped movement of an actual NES sprite, if you want that look.
    private func pixelSnapped(_ point: CGPoint) -> CGPoint {
        guard displayScale > 0 else { return point }
        return CGPoint(
            x: (point.x * displayScale).rounded() / displayScale,
            y: (point.y * displayScale).rounded() / displayScale
        )
    }

    @ViewBuilder
    private var sprite: some View {
        if let image = provider.image(for: viewModel.clipID, frame: viewModel.frameIndex) {
            image
                .resizable()
                // Both of these matter for pixel art. Without `.interpolation(.none)`
                // a 16×16 sprite scaled to 64×64 on a Retina display is smeared into
                // a blurry smudge; nearest-neighbour keeps the pixels square.
                .interpolation(.none)
                .antialiased(false)
        } else {
            // Last-resort marker so a broken provider is visible rather than silent.
            Rectangle()
                .fill(Color.red.opacity(0.5))
        }
    }
}
