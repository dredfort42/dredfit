//
//  The Health Connect half of `WorkoutHealthWriting` — iOS's
//  `HealthKitWorkoutWriter` (HealthStore.swift). Health Connect is on-device
//  IPC: the app still holds no INTERNET permission.
//
//  THE TYPES (android/README.md "Health Connect" has the whole table):
//  - an HKWorkout (.functionalStrengthTraining) is an ExerciseSessionRecord,
//    EXERCISE_TYPE_CALISTHENICS — Health Connect's own table files squats,
//    lunges, planks, crunches and burpees there and keeps STRENGTH_TRAINING
//    for barbells, dumbbells and machines;
//  - its activeEnergyBurned sample is an ActiveCaloriesBurnedRecord over the
//    same interval (never a TotalCaloriesBurnedRecord: iOS writes active
//    energy only);
//  - bodyMass → WeightRecord, basalEnergyBurned → the BASAL_CALORIES_TOTAL
//    aggregate of BasalMetabolicRateRecord, workouts → ExerciseSessionRecord.
//  - height, date of birth and biological sex are not read: Health Connect
//    has no record for the last two, and without an age the height cannot
//    move the estimate (EnergyEstimate.resting).
//
//  IDEMPOTENCE. iOS looks its own workout up by HKMetadataKeyExternalUUID
//  before saving. Health Connect does it in the write: both records carry the
//  journal record's id as their `clientRecordId` (unique per record type and
//  app), so a second save of the same record replaces the first — never a
//  copy. The energy's `clientRecordVersion` is the estimate's model revision,
//  HKMetadataKeyAlgorithmVersion's twin: which model produced the number,
//  and a re-export by a newer model takes precedence.
//

package com.dredfit.health

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import com.dredfit.workout.BodyProfile
import com.dredfit.workout.EnergyEstimate
import kotlinx.coroutines.CompletableDeferred
import java.time.Instant
import java.time.ZoneId
import kotlin.coroutines.cancellation.CancellationException

class HealthConnectWriter(context: Context) : WorkoutHealthWriting {

    private val app = context.applicationContext

    /** Shows Health Connect's permission screen for `permissions`. Set by
     *  MainActivity while it exists — the screen needs an activity; main
     *  thread only. */
    var ask: ((Set<String>) -> Unit)? = null

    /** Requests waiting for that screen to close. Main thread only. */
    private val waiting = mutableListOf<CompletableDeferred<Unit>>()

    /** `SDK_AVAILABLE`, `SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED` (Android
     *  10–13 without a current Health Connect app) or `SDK_UNAVAILABLE` (a
     *  work profile, a device without the service). Cheap: a package or
     *  system-service lookup, no IPC. */
    fun status(): Int = statusForTests ?: HealthConnectClient.getSdkStatus(app)

    override val isAvailable: Boolean get() = status() == HealthConnectClient.SDK_AVAILABLE

    /** Android 10–13: the Health Connect app is on the phone, only too old —
     *  "Update", not "Install". */
    fun providerInstalled(): Boolean = try {
        app.packageManager.getPackageInfo(PROVIDER, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun client(): HealthConnectClient? =
        if (isAvailable) HealthConnectClient.getOrCreate(app) else null

    // MARK: - The permission

    override suspend fun requestAuthorization(): Boolean {
        if (!isAvailable) return false
        val launch = ask ?: return workoutShareGranted()
        val closed = CompletableDeferred<Unit>()
        waiting += closed
        // One screen at a time; a second request waits for the same one.
        if (waiting.size == 1) launch(permissions)
        closed.await()
        // Only the workout write decides the switch, read from Health Connect
        // rather than from the screen's result: a feature that degrades is
        // not a feature that failed.
        return workoutShareGranted()
    }

    /** The screen closed — answered, or gone with its activity. */
    fun answered() {
        val all = waiting.toList()
        waiting.clear()
        all.forEach { it.complete(Unit) }
    }

    override suspend fun workoutShareGranted(): Boolean =
        granted()?.contains(WRITE_EXERCISE) ?: false

    /** What this app may do now; null when Health Connect cannot say. */
    private suspend fun granted(): Set<String>? {
        val client = client() ?: return null
        return guarded("permissions") { client.permissionController.getGrantedPermissions() }
    }

    // MARK: - Reads

    override suspend fun latestBodyMass(): BodyMassReading? {
        val client = client() ?: return null
        return guarded("weight") {
            // Newest first, one record: `time` is when the weigh-in was true.
            val request = ReadRecordsRequest(WeightRecord::class, TimeRangeFilter.after(Instant.EPOCH),
                                             ascendingOrder = false, pageSize = 1)
            val newest = client.readRecords(request).records.firstOrNull() ?: return@guarded null
            val kg = newest.weight.inKilograms
            // Finite and positive, or treated as absent.
            if (kg.isFinite() && kg > 0) BodyMassReading(kg, newest.time) else null
        }
    }

    override suspend fun profile(): BodyProfile = BodyProfile.unknown

    override suspend fun restingKcal(start: Instant, end: Instant): Double? {
        if (start >= end) return null
        val client = client() ?: return null
        return guarded("resting energy") {
            // The total integrates the newest recorded rate over the interval —
            // and with NO rate recorded anywhere it answers anyway, with one
            // of its own making (1534.5 kcal/day with no weight either, a
            // figure worked out from the newest weight otherwise; API 37),
            // and names no app in either case. A figure nobody recorded is
            // not this person's resting energy: without a recorded rate at or
            // before the end, the ladder's next rung is the honest one.
            // HealthKit's sum is simply empty there.
            val recorded = client.readRecords(ReadRecordsRequest(BasalMetabolicRateRecord::class, TimeRangeFilter.before(end),
                                                                 ascendingOrder = false, pageSize = 1))
            if (recorded.records.isEmpty()) return@guarded null
            client.aggregate(AggregateRequest(setOf(BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL),
                                              TimeRangeFilter.between(start, end)))[BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL]
                ?.inKilocalories
        }
    }

    override suspend fun foreignWorkoutIntervals(start: Instant, end: Instant): List<TimeSpan> =
        WorkoutHealthWriting.foreignIntervals(sessionsTouching(start, end) ?: return emptyList(), excluding = app.packageName)

    /** Every session, whoever wrote it, that overlaps the window; null when
     *  the read failed or was refused. HealthKit's predicate finds every
     *  workout that OVERLAPS the window; Health Connect's time filter matches
     *  a session by its START only (API 37: a session begun before the window
     *  and ending inside it is not returned), so a watch session started a
     *  minute before ours would be missed. Every session that started before
     *  the end is read, and the overlap is decided here. Internal for
     *  HealthConnectTest, which can only write sessions of its own. */
    internal suspend fun sessionsTouching(start: Instant, end: Instant): List<WorkoutOrigin>? {
        if (start >= end) return emptyList()
        val client = client() ?: return null
        return guarded("workouts") {
            val found = mutableListOf<WorkoutOrigin>()
            var page: String? = null
            do {
                val response = client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class,
                                                                      TimeRangeFilter.before(end), pageToken = page))
                response.records.filter { it.endTime > start }
                    .mapTo(found) { WorkoutOrigin(it.metadata.dataOrigin.packageName, it.startTime, it.endTime) }
                page = response.pageToken
            } while (page != null)
            found
        }
    }

    // MARK: - The write

    override suspend fun saveWorkout(start: Instant, end: Instant, activeKcal: Double?, journalID: String): Boolean {
        val client = client() ?: return false
        val granted = granted() ?: return false
        return guarded("save") {
            val device = Device(type = Device.TYPE_PHONE, manufacturer = Build.MANUFACTURER, model = Build.MODEL)
            val zone = ZoneId.systemDefault().rules
            val session = ExerciseSessionRecord(
                startTime = start, startZoneOffset = zone.getOffset(start),
                endTime = end, endZoneOffset = zone.getOffset(end),
                metadata = Metadata.activelyRecorded(device, clientRecordId = journalID),
                exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS)
            // The calories ride only with a number AND the permission to write
            // it: one call is one transaction, and an unpermitted record in it
            // would fail the session too — the calories are worth less than
            // the workout, so they are what gets dropped.
            val energy = if (activeKcal != null && activeKcal.isFinite() && activeKcal > 0 && start < end &&
                             WRITE_ACTIVE_CALORIES in granted) {
                ActiveCaloriesBurnedRecord(
                    startTime = start, startZoneOffset = zone.getOffset(start),
                    endTime = end, endZoneOffset = zone.getOffset(end),
                    energy = Energy.kilocalories(activeKcal),
                    metadata = Metadata.activelyRecorded(device, clientRecordId = journalID,
                                                         clientRecordVersion = EnergyEstimate.modelRevision.toLong()))
            } else {
                null
            }
            client.insertRecords(listOfNotNull<Record>(session, energy))
            true
        } ?: false
    }

    /** Health Connect is best-effort: a refused type (SecurityException), a
     *  dead binder, a record it will not take — each answers "nothing", never
     *  a crash. A cancelled caller stays cancelled. */
    private suspend fun <T> guarded(what: String, call: suspend () -> T?): T? = try {
        call()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        Log.w(LOG, "Health Connect $what failed: ${failure.javaClass.simpleName}")
        null
    }

    companion object {
        private const val LOG = "HealthConnect"

        /** The UI suite's stand-in for Android 10–13 without Health Connect
         *  (or a work profile) on an API 37 emulator, which always has it.
         *  Set only by androidTest; a release build reads the phone. */
        @Volatile
        var statusForTests: Int? = null

        val WRITE_EXERCISE = HealthPermission.getWritePermission(ExerciseSessionRecord::class)
        val WRITE_ACTIVE_CALORIES = HealthPermission.getWritePermission(ActiveCaloriesBurnedRecord::class)

        /** Everything the switch asks for — iOS's share and read sets minus
         *  height, date of birth and sex (see the file header). The manifest
         *  declares exactly these (HealthPermissionsTest). */
        val permissions: Set<String> = setOf(
            WRITE_EXERCISE,
            WRITE_ACTIVE_CALORIES,
            HealthPermission.getReadPermission(WeightRecord::class),
            HealthPermission.getReadPermission(BasalMetabolicRateRecord::class),
            HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        )

        /** The Health Connect app's package on Android 10–13. */
        const val PROVIDER = "com.google.android.apps.healthdata"

        /** Health Connect's page in the Play Store app, opened on its
         *  onboarding once installed — Google's documented install link. */
        const val INSTALL_LINK = "market://details?id=$PROVIDER&url=healthconnect%3A%2F%2Fonboarding"

        /** The same page on the web, for a phone without the Play Store. */
        const val INSTALL_LINK_WEB = "https://play.google.com/store/apps/details?id=$PROVIDER"

        /** Install or update Health Connect: the Play Store app where there
         *  is one, the web page where there is not. */
        fun openInstallPage(context: Context) {
            val store = Intent(Intent.ACTION_VIEW, Uri.parse(INSTALL_LINK))
                .setPackage("com.android.vending")
                .putExtra("overlay", true)
                .putExtra("callerId", context.packageName)
            try {
                context.startActivity(store)
            } catch (_: ActivityNotFoundException) {
                try {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(INSTALL_LINK_WEB)))
                } catch (_: ActivityNotFoundException) {
                    // Neither a store nor a browser: nothing on the phone can
                    // open a link, and no message would give it one.
                }
            }
        }
    }
}
