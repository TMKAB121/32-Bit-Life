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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The window is transparent and full-width. This background exists only
            // to define the layout bounds; it must never take hit tests, or the strip
            // would capture clicks meant for the desktop behind it.
            Color.clear
                .allowsHitTesting(false)

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
                // Artwork is drawn facing right; mirror it for leftward movement
                // rather than authoring a second set of frames.
                .scaleEffect(x: viewModel.facing == .right ? 1 : -1, y: 1)
                .position(viewModel.spriteCenter)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var sprite: some View {
        if let image = provider.image(for: viewModel.state, frame: viewModel.frameIndex) {
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
