//
//  SpriteSheetLibrary.swift
//  32-Bit Life
//
//  Loads any number of named PNG sprite sheets and slices them into per-clip frames.
//
//  Expected layout: one row per clip, one column per frame. Which row belongs to which
//  clip is stated in `Animations.json`, *not* inferred from an enum's declaration order —
//  that indirection is the point. Adding a row no longer renumbers everything beneath it,
//  and a clip can live on a sheet of its own.
//
//      column ->   0        1        2        3
//      row 0    idle/0   idle/1
//      row 1    runR/0   runR/1   runR/2   runR/3
//      row 2    runL/0   runL/1   runL/2   runL/3
//      row 3    surp/0   surp/1
//      row 4    jump/0
//      row 5    charge/0 charge/1 charge/2 charge/3
//
//  Frame counts are *derived from the artwork*: trailing transparent cells in a row are
//  not frames. Draw a third idle pose into row 0 and the idle animation becomes three
//  frames, with no code and no manifest edit. See `drawnFrameCounts` for the details and
//  for why only *trailing* blanks are trimmed.
//

import AppKit
import os
import SwiftUI

/// A sprite provider backed by one or more sprite-sheet images in the app bundle.
///
/// Built in two phases, because the two halves depend on each other in opposite
/// directions: the catalogue needs frame counts to resolve its clips, and the slicer
/// needs resolved clips to know which rows to cut. So ``init(sheets:bundle:)`` loads the
/// pixels and answers ``FrameCountSource``, then ``sliceFrames(for:)`` does the cutting
/// once the catalogue exists.
struct SpriteSheetLibrary: SpriteProvider, FrameCountSource {

    private static let logger = Logger(subsystem: "com.thirtytwobitlife.desktopsprite", category: "SpriteSheet")

    // MARK: - Loaded sheet

    private struct LoadedSheet {
        let image: CGImage
        let descriptor: SheetDescriptor
        /// Size of one frame in the file's own pixels, including any authoring scale.
        let framePixels: CGSize
        let columns: Int
        /// Drawn frames per row, after trailing-transparent cells are trimmed.
        let rowFrameCounts: [Int]
    }

    private let sheets: [String: LoadedSheet]
    private var frames: [ClipID: [Image]] = [:]

    // MARK: - Loading

    /// Loads every sheet named by the catalogue's descriptors.
    ///
    /// Returns `nil` only when *no* sheet could be loaded, which is the signal to fall
    /// back to ``PlaceholderSprite`` entirely. A single missing sheet among several is
    /// logged and skipped: clips on the sheets that did load keep working.
    init?(sheets descriptors: [String: SheetDescriptor], bundle: Bundle = .main) {
        var loaded: [String: LoadedSheet] = [:]

        for (name, descriptor) in descriptors {
            guard descriptor.frameSize.width > 0, descriptor.frameSize.height > 0 else {
                Self.logger.error("Sheet '\(name, privacy: .public)' has a zero frame size; skipping it.")
                continue
            }
            // Check the asset catalogue first, then loose resources, so a sheet can be
            // added either by dragging it into Assets.xcassets or by adding the PNG
            // directly to the target.
            guard let nsImage = NSImage(named: name) ?? bundle.image(forResource: name) else {
                Self.logger.info("No sprite sheet named '\(name, privacy: .public)' in the bundle.")
                continue
            }
            guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Self.logger.error("Sprite sheet '\(name, privacy: .public)' could not be decoded.")
                continue
            }

            let framePixels = CGSize(
                width: descriptor.frameSize.width * descriptor.scale,
                height: descriptor.frameSize.height * descriptor.scale
            )
            let columns = Int(CGFloat(cgImage.width) / framePixels.width)
            let rows = Int(CGFloat(cgImage.height) / framePixels.height)
            guard columns >= 1, rows >= 1 else {
                Self.logger.error("Sprite sheet '\(name, privacy: .public)' is \(cgImage.width)x\(cgImage.height)px, smaller than one \(Int(framePixels.width))x\(Int(framePixels.height))px frame.")
                continue
            }

            let counts = Self.drawnFrameCounts(
                in: cgImage,
                framePixels: framePixels,
                columns: columns,
                rows: rows,
                name: name
            )

            loaded[name] = LoadedSheet(
                image: cgImage,
                descriptor: descriptor,
                framePixels: framePixels,
                columns: columns,
                rowFrameCounts: counts
            )
            Self.logger.info("Loaded sheet '\(name, privacy: .public)': \(columns)x\(rows) grid, frames per row \(counts.map(String.init).joined(separator: ","), privacy: .public).")
        }

        guard !loaded.isEmpty else { return nil }
        sheets = loaded
    }

    // MARK: - Frame derivation

    /// Counts the drawn frames in each row by looking at the alpha channel.
    ///
    /// Two decisions here are worth the words:
    ///
    /// **Why one normalising draw instead of reading the PNG's bytes.** A hand-authored
    /// PNG can be indexed, greyscale, 16-bit, or premultiplied in either order, and
    /// walking `dataProvider` bytes means handling all of it. Drawing the sheet once into
    /// a context of known layout — 8-bit RGBA, premultiplied, alpha last — makes the
    /// stride arithmetic below exact for every input. For a 128×160 sheet the whole scan
    /// is about twenty thousand byte reads, once, at launch.
    ///
    /// **Why only trailing blanks are trimmed.** A transparent cell in the *middle* of a
    /// row is legitimate artwork — a blink-off, a flicker gap, a frame where the character
    /// is meant to vanish for an instant. Trimming every empty cell would silently eat
    /// those and shorten the animation. Trimming only from the right end answers the
    /// question actually being asked: "where does this row's artwork stop?"
    ///
    /// A row with nothing drawn in it at all returns `0`, meaning "not authored yet" —
    /// the clip is dropped rather than the whole sheet being rejected.
    private static func drawnFrameCounts(
        in image: CGImage,
        framePixels: CGSize,
        columns: Int,
        rows: Int,
        name: String
    ) -> [Int] {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let raw = context.data else {
            // Falling back to "every cell is a frame" keeps the sheet usable; the clips
            // will simply animate through blank frames until the manifest says otherwise.
            Self.logger.error("Could not scan alpha for sheet '\(name, privacy: .public)'; assuming every cell is a frame.")
            return Array(repeating: columns, count: rows)
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // A bitmap context's buffer starts at the *top-left* of the image even though its
        // drawing coordinates are bottom-left origin, so row 0 here is row 0 of the grid
        // as read above — the same orientation `CGImage.cropping(to:)` uses. No Y flip.
        func isBlank(row: Int, column: Int) -> Bool {
            let originX = Int(CGFloat(column) * framePixels.width)
            let originY = Int(CGFloat(row) * framePixels.height)
            let endX = min(originX + Int(framePixels.width), width)
            let endY = min(originY + Int(framePixels.height), height)

            for y in originY..<endY {
                let rowStart = y * width * 4
                for x in originX..<endX where bytes[rowStart + x * 4 + 3] != 0 {
                    return false
                }
            }
            return true
        }

        return (0..<rows).map { row in
            var count = columns
            while count > 0, isBlank(row: row, column: count - 1) {
                count -= 1
            }
            return count
        }
    }

    // MARK: - Slicing

    /// Cuts the frames for every clip in the catalogue and caches them.
    ///
    /// Done once at launch so the render path is a dictionary lookup, not a crop.
    mutating func sliceFrames(for catalogue: AnimationCatalogue) {
        var built: [ClipID: [Image]] = [:]

        for clip in catalogue.allClips {
            guard let sheet = sheets[clip.sheet] else { continue }
            guard clip.row >= 0, clip.row < sheet.rowFrameCounts.count else {
                Self.logger.error("Clip '\(clip.id.rawValue, privacy: .public)' wants row \(clip.row) of '\(clip.sheet, privacy: .public)', which has \(sheet.rowFrameCounts.count) rows.")
                continue
            }

            var images: [Image] = []
            for column in 0..<min(clip.frameCount, sheet.columns) {
                // CGImage coordinates have their origin at the top-left, which lines up
                // with how the grid in this file's header reads, so no Y flip is needed.
                let cropRect = CGRect(
                    x: CGFloat(column) * sheet.framePixels.width,
                    y: CGFloat(clip.row) * sheet.framePixels.height,
                    width: sheet.framePixels.width,
                    height: sheet.framePixels.height
                )
                guard let slice = sheet.image.cropping(to: cropRect) else { continue }
                images.append(Image(decorative: slice, scale: sheet.descriptor.scale))
            }

            guard !images.isEmpty else {
                Self.logger.error("Clip '\(clip.id.rawValue, privacy: .public)' produced no frames from '\(clip.sheet, privacy: .public)' row \(clip.row).")
                continue
            }
            built[clip.id] = images
        }

        frames = built
    }

    // MARK: - FrameCountSource

    func frameCount(sheet: String, row: Int) -> Int? {
        guard let loaded = sheets[sheet], row >= 0, row < loaded.rowFrameCounts.count else { return nil }
        let count = loaded.rowFrameCounts[row]
        return count > 0 ? count : nil
    }

    // MARK: - SpriteProvider

    func image(for clip: ClipID, frame: Int) -> Image? {
        guard let images = frames[clip], !images.isEmpty else { return nil }
        // Wrapping rather than trapping: the frame clock and the artwork can briefly
        // disagree on the tick a clip changes.
        return images[frame % images.count]
    }

    func hasArtwork(for clip: ClipID) -> Bool {
        frames[clip]?.isEmpty == false
    }
}
