//
//  The iOS files the Android suites read IN PLACE — the String Catalogs the
//  generated resources come from, and the sources that ask for their keys —
//  never a copy. Swift derives `iosRoot` from `#filePath` in each suite; here
//  it is derived once, for every suite that needs it (LifeBenefitTest,
//  SetsNoticeTest). The files are declared as inputs of the test task in
//  app/build.gradle.kts, so an edit reruns the suites.
//

package com.dredfit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.test.assertNotNull
import kotlin.test.fail

object IosCatalogs {

    /** `ios/`, found by walking up from the working directory — Gradle runs a
     *  module's tests in the module (`android/app`), but a run from elsewhere
     *  must not read as a missing catalog. */
    val iosRoot: Path
        get() {
            var dir: Path? = Paths.get(System.getProperty("user.dir")).toAbsolutePath()
            while (dir != null) {
                val candidate = dir.resolve("ios")
                if (Files.isDirectory(candidate.resolve("Dredfit"))) return candidate
                dir = dir.parent
            }
            fail("no ios/Dredfit above ${System.getProperty("user.dir")}")
        }

    /** The `strings` object of a catalog under `ios/`. */
    fun strings(catalog: String): JsonObject {
        val root = Json.parseToJsonElement(Files.readString(iosRoot.resolve(catalog))).jsonObject
        return assertNotNull(root["strings"]?.jsonObject)
    }

    /** `localizations.<lang>.stringUnit.<field>`, or null anywhere along the way. */
    fun unit(entry: JsonObject?, lang: String, field: String = "value"): String? =
        (((entry?.get("localizations") as? JsonObject)?.get(lang) as? JsonObject)
            ?.get("stringUnit") as? JsonObject)?.get(field)?.jsonPrimitive?.contentOrNull
}
