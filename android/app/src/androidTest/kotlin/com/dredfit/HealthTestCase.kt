//
//  The device half of the Health Connect suites: the real Health Connect on
//  the emulator (API 37), read back through its own client. Shared by
//  HealthConnectTest (permissions granted, in the suite) and HealthDeniedTest
//  (a fresh install, alone). On ReminderTestCase for its store helpers
//  (`onStore`, `readStore`, `tapOnce`).
//
//  Grants come from the shell's UiAutomation, never revokes: revoking a
//  Health Connect permission kills the app's process, which is the process
//  the instrumentation runs in (`pm revoke`, API 37, 11.10.2026).
//

package com.dredfit

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.dredfit.health.HealthConnectWriter
import kotlinx.coroutines.runBlocking
import java.time.Instant
import kotlin.reflect.KClass

abstract class HealthTestCase : ReminderTestCase() {

    protected val client: HealthConnectClient get() = HealthConnectClient.getOrCreate(app)

    /** What the debug manifest adds for the suite: reading back the calories,
     *  writing a weigh-in and a resting rate as a scale or a watch would. */
    protected val testPermissions = setOf(
        "android.permission.health.READ_ACTIVE_CALORIES_BURNED",
        "android.permission.health.WRITE_WEIGHT",
        "android.permission.health.WRITE_BASAL_METABOLIC_RATE",
    )

    protected fun grant(permissions: Set<String>) {
        for (p in permissions) instrumentation.uiAutomation.grantRuntimePermission(app.packageName, p)
    }

    protected fun granted(): Set<String> = runBlocking { client.permissionController.getGrantedPermissions() }

    /** Dredfit's own records of every type the suites touch — an app can
     *  delete only what it wrote, which is all these suites write. */
    protected fun deleteOwnRecords() = runBlocking {
        val all = TimeRangeFilter.after(Instant.EPOCH)
        val held = client.permissionController.getGrantedPermissions()
        for ((type, write) in listOf(ExerciseSessionRecord::class to HealthConnectWriter.WRITE_EXERCISE,
                                     ActiveCaloriesBurnedRecord::class to HealthConnectWriter.WRITE_ACTIVE_CALORIES,
                                     WeightRecord::class to "android.permission.health.WRITE_WEIGHT",
                                     BasalMetabolicRateRecord::class to "android.permission.health.WRITE_BASAL_METABOLIC_RATE")) {
            if (write in held) client.deleteRecords(type, all)
        }
    }

    /** Every record of `type` Dredfit wrote, oldest first. */
    protected fun <T : Record> own(type: KClass<T>): List<T> = runBlocking {
        client.readRecords(ReadRecordsRequest(type, TimeRangeFilter.after(Instant.EPOCH))).records
            .filter { it.metadata.dataOrigin.packageName == app.packageName }
    }
}
