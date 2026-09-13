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

    /// Increased Contrast is its own column of the palette, so it has to be
    /// its own cache entry — otherwise the standard-contrast bitmap answers
    /// for both, and the day a token gains an Increased Contrast value the
    /// pill is the one thing that never picks it up.
    ///
    /// Object identity, not pixels, since finding 16 moved the glyph off
    /// accentText (4.20:1 on accentSoft) onto `ink`: BOTH of the pill's two
    /// tokens are Increased-Contrast-invariant today — ink is #F2F2F4 in both
    /// dark columns and accentSoft #3A2013 in both — so the two bitmaps are
    /// legitimately identical and no pixel can tell them apart in either
    /// scheme. What the finding leaves testable is the half that was the
    /// defect: whether `contrast` is in the key at all. Dropped from it, the
    /// second call is a cache hit and hands back the very same object.
    ///
    /// That the colours are resolved for the appearance they are asked for is
    /// still pinned by the light/dark test above, where the fill does move.
    /// The MOVE itself — that the glyph is `ink` and not accentText — is not
    /// pinned here and deliberately not faked: the centre pixel is a stroke
    /// antialiased into the fill at an unknown coverage, and both tones sit on
    /// the same side of accentSoft in both schemes, so every assertion this
    /// bitmap can carry passes for the colour the finding replaced as well.
    /// The gate for the pair is the floor in `BrandPaletteTests`, which now
    /// measures ink-on-accentSoft in all four appearances.
    func testIncreasedContrastIsItsOwnEntry() throws {
        let standard = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                     typeSize: .large,
                                                     colorScheme: .dark,
                                                     contrast: .standard))
        let increased = try XCTUnwrap(BadgePill.image(text: badge, scale: 2,
                                                      typeSize: .large,
                                                      colorScheme: .dark,
                                                      contrast: .increased))
        XCTAssertNotIdentical(standard, increased,
                              "the contrast fell out of the cache key")
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

    // A glyph sampler stood here — the horizontal centre of the capsule. It
    // went with the assertion that used it: once finding 16 put the glyph on
    // `ink`, no reading of that pixel separates a passing pill from a failing
    // one (see the contrast test above). A helper kept "in case" is a helper
    // the next reader builds a false assertion on.

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
