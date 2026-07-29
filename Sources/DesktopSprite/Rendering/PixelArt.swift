//
//  PixelArt.swift
//  32-Bit Life
//
//  Turns character-grid pixel art into a CGImage.
//
//  Authoring art as strings keeps it readable and diffable in source, which is
//  exactly what a placeholder needs to be.
//

import AppKit
import SwiftUI

/// A straight (non-premultiplied) 8-bit RGBA colour.
struct PixelColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    static let clear = PixelColor(red: 0, green: 0, blue: 0, alpha: 0)

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Convenience initialiser taking a 24-bit hex value, e.g. `0xE03C28`.
    init(hex: UInt32) {
        self.init(
            red: UInt8((hex >> 16) & 0xFF),
            green: UInt8((hex >> 8) & 0xFF),
            blue: UInt8(hex & 0xFF)
        )
    }
}

/// Builds images from character-grid pixel art.
enum PixelArt {

    /// The palette used by the built-in placeholder frames.
    ///
    /// Any character not listed here renders as transparent, so `.` is simply
    /// "not in the palette".
    static let defaultPalette: [Character: PixelColor] = [
        "K": PixelColor(hex: 0x1A1A2E),  // outline / dark
        "S": PixelColor(hex: 0xF8C088),  // skin
        "R": PixelColor(hex: 0xE03C28),  // cap and shirt
        "B": PixelColor(hex: 0x3050C8),  // overalls
        "Y": PixelColor(hex: 0x8B4513),  // hair and shoes
        "W": PixelColor(hex: 0xFFFFFF)   // eye highlight
    ]

    /// Renders a character grid into a `CGImage`, one pixel per character.
    ///
    /// - Parameters:
    ///   - rows: Grid rows, top to bottom. Every row must have the same length;
    ///     a ragged grid returns `nil` rather than producing garbled art.
    ///   - palette: Character-to-colour mapping. Unmapped characters are transparent.
    /// - Returns: An image whose dimensions are the grid's dimensions in pixels, or
    ///   `nil` if the grid is empty or ragged.
    static func makeImage(rows: [String], palette: [Character: PixelColor] = defaultPalette) -> CGImage? {
        let height = rows.count
        guard let width = rows.first?.count, width > 0, height > 0 else { return nil }
        guard rows.allSatisfy({ $0.count == width }) else {
            assertionFailure("Pixel art grid is ragged: every row must be \(width) characters.")
            return nil
        }

        // Premultiplied RGBA. Because every palette entry is either fully opaque or
        // fully transparent, premultiplying is a no-op — the colour components are
        // already correct for both cases.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, character) in row.enumerated() {
                let color = palette[character] ?? .clear
                guard color.alpha > 0 else { continue }
                let offset = (rowIndex * width + columnIndex) * 4
                bytes[offset + 0] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                bytes[offset + 3] = color.alpha
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            // Nearest-neighbour at the CoreGraphics level. The view layer also sets
            // `.interpolation(.none)`; both are needed to guarantee crisp pixels.
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Renders a character grid straight to a SwiftUI `Image`.
    static func makeSwiftUIImage(rows: [String], palette: [Character: PixelColor] = defaultPalette) -> Image? {
        guard let cgImage = makeImage(rows: rows, palette: palette) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
