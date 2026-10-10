//
//  Port of ios/DredfitTests/AppStoreTestCase.swift: every suite that persists
//  a store to a scratch JSON file needs a fresh path per test and that file
//  gone afterwards — JUnit's @TempDir owns both.
//
//  The store runs on the system clock and zone unless a test pins them, as
//  the iOS suites run on `Date()` and `Calendar.current`.
//

package com.dredfit

import com.dredfit.core.Pattern
import com.dredfit.reminders.NotificationScheduling
import com.dredfit.store.AppStore
import com.dredfit.widgets.WidgetPublishing
import com.dredfit.widgets.WidgetSnapshot
import org.junit.jupiter.api.Assumptions.assumeFalse
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
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

    fun makeStore(path: Path = tempPath, clock: Clock? = null,
                  notifications: NotificationScheduling = NotificationScheduling.none,
                  widgets: WidgetPublishing = WidgetPublishing.none): AppStore =
        AppStore(path, clock, notifications = notifications, widgets = widgets)

    /** What the store handed the widget, in order — iOS's temp
     *  `widgetSnapshotURL`, read back after each write. */
    class WidgetRecorder : WidgetPublishing {
        val published = mutableListOf<WidgetSnapshot>()
        val last: WidgetSnapshot get() = published.last()
        override fun publish(snapshot: WidgetSnapshot) {
            published += snapshot
        }
    }

    /** A fixed hour-10 instant on the given day, in the system zone. */
    fun date(y: Int, m: Int, d: Int, zone: ZoneId = ZoneId.systemDefault()): Instant =
        ZonedDateTime.of(y, m, d, 10, 0, 0, 0, zone).toInstant()

    /** The START of the day `n` days before today — MIDNIGHTS, not elapsed
     *  seconds (see the Swift helper: a DST day turns `n × 86 400` into the
     *  neighbouring calendar day). */
    fun daysAgo(n: Long, zone: ZoneId = ZoneId.systemDefault()): Instant =
        LocalDate.now(zone).minusDays(n).atStartOfDay(zone).toInstant()

    /** Where a read puts `tempPath` aside first — `<name>.corrupt.json`. */
    val corruptPath: Path get() = tempDir.resolve("dredfit-test.corrupt.json")

    /** Every test that makes a file unreadable by permission: root reads
     *  through 0o000 and writes through 0o555, as on iOS. */
    fun assumeNotRoot() = assumeFalse(System.getProperty("user.name") == "root", "root ignores permissions")

    /** A POSIX mode on `path`, as iOS's `setAttributes([.posixPermissions:])`. */
    fun setPermissions(path: Path, mode: String) {
        Files.setPosixFilePermissions(path, PosixFilePermissions.fromString(mode))
    }

    /** `"squat",x,"push_h",x,…` — a `[Pattern: Int]` the way Swift writes
     *  it, for the suites that seed a state file by hand. */
    fun pairs(value: (Pattern) -> Any): String =
        Pattern.allCases.joinToString(",") { p -> "\"${p.rawValue}\",${value(p)}" }

    /** Writes `json` as the state file and opens a store on it — the door
     *  the app loads through. */
    fun storeFrom(json: String, path: Path = tempPath): AppStore {
        Files.writeString(path, json)
        return makeStore(path)
    }
}
