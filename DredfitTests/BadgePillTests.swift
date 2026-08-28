import SwiftUI
import XCTest
@testable import Dredfit

/// The pill is the one piece of the interface that is a BITMAP rather than a
/// view, so the palette cannot follow the appearance on its own — the render
/// has to be told which one it is for, and the cache has to be able to tell
/// two of them apart. That is what these assert.
@MainActor
final class BadgePillTests: XCTestCase {
    private let badge = "new variation"

    /// The defect this wave fixes: with the appearance out of the key, the
    /// second call was a cache hit and Today kept drawing the light pill on
    /// the dark card.
    func testLightAndDarkProduceDifferentPills() throws {
        let light = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                  typeSize: .large,
                                                  colorScheme: .light,
                                                  contrast: .standard))
        let dark = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                 typeSize: .large,
                                                 colorScheme: .dark,
                                                 contrast: .standard))
        // The fill, not the glyph: a corner of the capsule is accentSoft in
        // both, and its two values (#FBE3D6 / #3A2013) are far enough apart
        // that no rounding can bring them together.
        let lightFill = try XCTUnwrap(fillSample(light))
        let darkFill = try XCTUnwrap(fillSample(dark))
        XCTAssertNotEqual(lightFill, darkFill,
                          "the pill baked the appearance it was first drawn in")
        // Which way round, so a swapped argument cannot pass either.
        XCTAssertGreaterThan(brightness(lightFill), brightness(darkFill))
    }

    /// Increased Contrast has its own column in the palette, so it has to be
    /// its own cache entry — otherwise the standard-contrast bitmap answers
    /// for both.
    func testIncreasedContrastIsItsOwnEntry() throws {
        let standard = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                     typeSize: .large,
                                                     colorScheme: .dark,
                                                     contrast: .standard))
        let increased = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                      typeSize: .large,
                                                      colorScheme: .dark,
                                                      contrast: .increased))
        // Same fill in both dark columns (#3A2013); accentText is what
        // brightens, #E8590C to #FF7526. So this compares the glyph band.
        XCTAssertNotEqual(try XCTUnwrap(inkSample(standard)),
                          try XCTUnwrap(inkSample(increased)))
    }

    /// The cache still has to BE a cache: same arguments, same object.
    func testSameAppearanceIsServedFromTheCache() throws {
        let first = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                  typeSize: .large,
                                                  colorScheme: .light,
                                                  contrast: .standard))
        let second = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                   typeSize: .large,
                                                   colorScheme: .light,
                                                   contrast: .standard))
        XCTAssertIdentical(first, second)
    }

    // MARK: - Pixels

    /// A few points in from the left edge and vertically centred: inside the
    /// capsule, before the first glyph.
    private func fillSample(_ image: UIImage) -> [UInt8]? {
        pixel(image, atX: 3, y: image.size.height / 2)
    }

    /// The horizontal centre of the capsule, where the text is.
    private func inkSample(_ image: UIImage) -> [UInt8]? {
        pixel(image, atX: image.size.width / 2, y: image.size.height / 2)
    }

    private func pixel(_ image: UIImage, atX x: CGFloat, y: CGFloat) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let scale = image.scale
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Draw the whole image offset so the wanted pixel lands in the 1×1
        // context — simpler than reading the backing store, and independent
        // of how the renderer laid its bytes out.
        context.draw(cgImage,
                     in: CGRect(x: -x * scale, y: -(image.size.height - y) * scale,
                                width: CGFloat(cgImage.width),
                                height: CGFloat(cgImage.height)))
        return bytes
    }

    private func brightness(_ rgba: [UInt8]) -> Int {
        Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2])
    }
}
