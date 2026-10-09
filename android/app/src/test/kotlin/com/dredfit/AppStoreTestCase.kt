//
//  Port of ios/DredfitTests/AppStoreTestCase.swift: every suite that persists
//  a store to a scratch JSON file needs a fresh path per test and that file
//  gone afterwards — JUnit's @TempDir owns both.
//
//  The store runs on the system clock and zone unless a test pins them, as
//  the iOS suites run on `Date()` and `Calendar.current`.
//

package com.dredfit

import com.dredfit.store.AppStore
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

abstract class AppStoreTestCase {

    @TempDir
    lateinit var tempDir: Path

    /** The state file of this test — iOS's `tempURL`. */
    val tempPath: Path get() = tempDir.resolve("dredfit-test.json")

    fun makeStore(path: Path = tempPath, clock: Clock? = null): AppStore = AppStore(path, clock)

    /** A fixed hour-10 instant on the given day, in the system zone. */
    fun date(y: Int, m: Int, d: Int, zone: ZoneId = ZoneId.systemDefault()): Instant =
        ZonedDateTime.of(y, m, d, 10, 0, 0, 0, zone).toInstant()

    /** The START of the day `n` days before today — MIDNIGHTS, not elapsed
     *  seconds (see the Swift helper: a DST day turns `n × 86 400` into the
     *  neighbouring calendar day). */
    fun daysAgo(n: Long, zone: ZoneId = ZoneId.systemDefault()): Instant =
        LocalDate.now(zone).minusDays(n).atStartOfDay(zone).toInstant()
}
