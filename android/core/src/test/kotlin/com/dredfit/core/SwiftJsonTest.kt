//
//  What Swift's JSONDecoder accepts, refuses as a whole file, and refuses only
//  for one field — measured against the decoder itself (a scratch probe over
//  the app's own `AppData`, 09.10.2026) and pinned here, because kotlinx is
//  more lenient: it reads an unquoted `+7` as a literal, and `07` as seven.
//  No Swift file of this name; on iOS these are the standard library's rules.
//

package com.dredfit.core

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class SwiftJsonTest {

    private fun field(token: String) = (SwiftJson.parse("""{"v": $token}""") as JsonObject).getValue("v")

    /** Swift refuses the whole file for these tokens. */
    @Test
    fun tokensSwiftsScannerRefusesRefuseTheDocument() {
        for (token in listOf("+7", ".5", "1d", "0x1p3", "NaN", "Infinity", "-Infinity", "seven", "tru", "nul")) {
            assertFailsWith<SwiftDecodingException>(token) { field(token) }
        }
    }

    /** These pass Swift's scanner and fail only the conversion: the field
     *  falls to its default there, so it reads as no number here. */
    @Test
    fun tokensThatAreNoNumberFailOnlyTheField() {
        for (token in listOf("07", "00", "7.", "1e", "-", "1.5e", "1e400")) {
            assertNull(SwiftJson.int(field(token)), token)
        }
        assertNull(SwiftJson.double(field("1e400")))
    }

    @Test
    fun integralNumbersReadAsSwiftReadsThem() {
        assertEquals(7, SwiftJson.int(field("7.0")))
        assertEquals(7, SwiftJson.int(field("7e0")))
        assertEquals(0, SwiftJson.int(field("-0")))
        assertNull(SwiftJson.int(field("7.5")))
        assertNull(SwiftJson.int(JsonPrimitive("7")), "a string is never a number")
    }

    /** Swift skips a UTF-8 byte-order mark. */
    @Test
    fun aByteOrderMarkIsSkipped() {
        assertEquals(3, SwiftJson.int((SwiftJson.parse("﻿{\"v\": 3}") as JsonObject)["v"]))
    }
}
