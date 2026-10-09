//
//  Provenance for the golden fixture (issue #104) — the port of
//  ManifestTests.swift. The committed manifest, written by
//  scripts/update_reference_manifest.py and never by hand, ties the fixture to
//  the exact reference that generated it. Both files are read from the Swift
//  package's Fixtures folder, so this test and the Swift one guard ONE file.
//

package com.dredfit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ManifestTest {

    private class Manifest(val generator: String, val goldenSHA256: String, val reference: Map<String, String>)

    private fun manifest(): Manifest {
        val root = Json.parseToJsonElement(Golden.bytes("reference-manifest.json").decodeToString()).jsonObject
        return Manifest(
            generator = root.getValue("generator").jsonPrimitive.content,
            goldenSHA256 = root.getValue("golden.json").jsonPrimitive.content,
            reference = root.getValue("reference").jsonObject.mapValues { (it.value as JsonPrimitive).content })
    }

    /** The one CI-checkable claim: the fixture is byte-for-byte the file the
     *  manifest was computed from. */
    @Test
    fun goldenFixtureMatchesTheManifest() {
        val digest = MessageDigest.getInstance("SHA-256").digest(Golden.bytes("golden.json"))
            .joinToString("") { "%02x".format(it) }
        assertEquals(manifest().goldenSHA256, digest,
                     "golden.json changed without provenance — run make_golden.js, " +
                         "then scripts/update_reference_manifest.py")
    }

    /** The manifest and the fixture must name the same reference version. */
    @Test
    fun manifestNamesTheFixturesGenerator() {
        val golden = Json.parseToJsonElement(Golden.bytes("golden.json").decodeToString()) as JsonObject
        assertEquals(golden.getValue("generator").jsonPrimitive.content, manifest().generator)
    }

    /** The contour's own hashes cannot be verified here, but their presence
     *  and shape can: four named files, each a sha256 hex digest. */
    @Test
    fun manifestCarriesTheFullContour() {
        val m = manifest()
        assertEquals(setOf("SPEC-v2.md", "adaptive_engine.js", "make_golden.js", "verify2.js"), m.reference.keys)
        for ((name, digest) in m.reference) {
            assertEquals(64, digest.length, "$name: a sha256 hex digest has 64 chars")
            assertTrue(digest.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }, "$name: non-hex digest")
        }
        assertEquals(64, m.goldenSHA256.length)
    }
}
