//
//  ManifestTests.swift
//  DredfitCoreTests
//
//  Provenance for the golden fixture (issue #104). The reference contour
//  lives outside this repository, so the committed manifest — written by
//  scripts/update_reference_manifest.py, never by hand — is what ties the
//  fixture to the exact reference that generated it. A fixture changed
//  without a manifest update fails here, in CI, not in a reviewer's memory.
//

import CryptoKit
import XCTest
@testable import DredfitCore

final class ManifestTests: XCTestCase {

    private struct Manifest: Decodable {
        let generator: String
        let goldenSHA256: String
        let reference: [String: String]

        private enum CodingKeys: String, CodingKey {
            case generator
            case goldenSHA256 = "golden.json"
            case reference
        }
    }

    private func load(_ resource: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: resource,
                                                  withExtension: "json"),
                                "\(resource).json must ship with the test bundle")
        return try Data(contentsOf: url)
    }

    /// The one CI-checkable claim: the bundled fixture is byte-for-byte the
    /// file the manifest was computed from.
    func testGoldenFixtureMatchesTheManifest() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: load("reference-manifest"))
        let golden = try load("golden")
        let digest = SHA256.hash(data: golden).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, manifest.goldenSHA256,
                       "golden.json changed without provenance — run make_golden.js, "
                       + "then scripts/update_reference_manifest.py")
    }

    /// The manifest and the fixture must name the same reference version —
    /// two version carriers that disagree are worse than one.
    func testManifestNamesTheFixturesGenerator() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: load("reference-manifest"))
        struct GoldenHeader: Decodable { let generator: String }
        let golden = try JSONDecoder().decode(GoldenHeader.self, from: load("golden"))
        XCTAssertEqual(manifest.generator, golden.generator)
    }

    /// The contour's own hashes cannot be verified here (the reference lives
    /// outside the repo — that is the point of the manifest), but their
    /// presence and shape can: four named files, each a sha256 hex digest.
    func testManifestCarriesTheFullContour() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: load("reference-manifest"))
        let expected: Set<String> = ["SPEC-v2.md", "adaptive_engine.js",
                                     "make_golden.js", "verify2.js"]
        XCTAssertEqual(Set(manifest.reference.keys), expected)
        for (name, digest) in manifest.reference {
            XCTAssertEqual(digest.count, 64, "\(name): a sha256 hex digest has 64 chars")
            XCTAssertTrue(digest.allSatisfy(\.isHexDigit), "\(name): non-hex digest")
        }
        XCTAssertEqual(manifest.goldenSHA256.count, 64)
    }
}
