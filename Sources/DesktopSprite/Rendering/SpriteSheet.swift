//
//  SpriteSheet.swift
//  32-Bit Life
//
//  Slices a PNG sprite sheet into per-state animation frames.
//
//  Expected layout: one row per state, one column per frame, in the order given by
//  `SpriteState.allCases` — idle, runningRight, runningLeft, surprised, jumping.
//  Frame counts come from `SpriteState.animation.frameCount`.
//
//      column ->   0        1        2        3
//      row 0    idle/0   idle/1
//      row 1    runR/0   runR/1   runR/2   runR/3
//      row 2    runL/0   runL/1   runL/2   runL/3
//      row 3    surp/0   surp/1
//      row 4    jump/0
//
//  Rows may be short — trailing cells are simply never read.
//

import AppKit
import os
import SwiftUI

/// A sprite provider backed by a sprite-sheet image in the app bundle.
struct SpriteSheet: SpriteProvider {

    private static let logger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "SpriteSheet")

    private let frames: [SpriteState: [Image]]

    /// Loads the sheet named by the configuration, or returns `nil` if it is absent
    /// or too small for the expected layout.
    ///
    /// Returning `nil` rather than trapping is deliberate: a missing or malformed
    /// sheet should degrade to the placeholder art, not crash a background app the
    /// user cannot easily see.
    init?(configuration: SpriteConfiguration) {
        self.init(
            assetName: configuration.spriteSheetAssetName,
            frameSize: configuration.spriteSheetFrameSize
        )
    }

    init?(assetName: String, frameSize: CGSize, bundle: Bundle = .main) {
        guard frameSize.width > 0, frameSize.height > 0 else { return nil }

        // Check the asset catalog first, then loose resources, so the sheet can be
        // added either by dragging it into Assets.xcassets or by adding the PNG
        // directly to the target.
        guard let nsImage = NSImage(named: assetName) ?? bundle.image(forResource: assetName) else {
            Self.logger.info("No sprite sheet named '\(assetName, privacy: .public)' in the bundle; using placeholder art.")
            return nil
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Self.logger.error("Sprite sheet '\(assetName, privacy: .public)' could not be decoded; using placeholder art.")
            return nil
        }

        let states = SpriteState.allCases
        let columns = states.map(\.animation.frameCount).max() ?? 1

        // A sheet supplied at @2x is twice the expected pixel size. Detect the factor
        // rather than assuming 1×, so both authoring resolutions work.
        let expectedWidth = CGFloat(columns) * frameSize.width
        let expectedHeight = CGFloat(states.count) * frameSize.height
        let scale = (CGFloat(cgImage.width) / expectedWidth).rounded(.down)

        guard scale >= 1,
              CGFloat(cgImage.height) >= expectedHeight * scale else {
            Self.logger.error("Sprite sheet '\(assetName, privacy: .public)' is \(cgImage.width)x\(cgImage.height)px, too small for a \(columns)x\(states.count) grid of \(Int(frameSize.width))x\(Int(frameSize.height))px frames. Using placeholder art.")
            return nil
        }

        let pixelFrame = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        var built: [SpriteState: [Image]] = [:]

        for (rowIndex, state) in states.enumerated() {
            var images: [Image] = []
            for columnIndex in 0..<state.animation.frameCount {
                // CGImage coordinates have their origin at the top-left, which lines up
                // with how the grid above reads, so no Y-flip is needed here.
                let cropRect = CGRect(
                    x: CGFloat(columnIndex) * pixelFrame.width,
                    y: CGFloat(rowIndex) * pixelFrame.height,
                    width: pixelFrame.width,
                    height: pixelFrame.height
                )
                guard let slice = cgImage.cropping(to: cropRect) else { continue }
                images.append(Image(decorative: slice, scale: scale))
            }
            guard images.count == state.animation.frameCount else {
                Self.logger.error("Sprite sheet '\(assetName, privacy: .public)' is missing frames for \(state.rawValue, privacy: .public); using placeholder art.")
                return nil
            }
            built[state] = images
        }

        frames = built
        Self.logger.info("Loaded sprite sheet '\(assetName, privacy: .public)' at \(Int(scale))× scale.")
    }

    func image(for state: SpriteState, frame: Int) -> Image? {
        guard let images = frames[state], !images.isEmpty else { return nil }
        return images[frame % images.count]
    }
}
