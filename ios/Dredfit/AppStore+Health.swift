//
//  The store's half of Apple Health: the switch, the weight in force and the
//  export flags — the state, and the permission checks that flip the switch.
//  The export and its arithmetic are HealthExporter's. The rule this half
//  keeps: a record is flagged exported only after Health confirms the save,
//  so a hole in the export is always still retriable.
//

import Foundation

extension AppStore {

    // MARK: - Apple Health

    var healthExporter: HealthExporter { HealthExporter(health: health) }

    /// On denial the toggle stays off — reality over wishful state.
    func enableHealth() async -> Bool {
        guard health.isAvailable else { return false }
        let granted = await health.requestAuthorization()
        if granted {
            update { $0.settings.healthEnabled = true }
            // Health's reading is adopted from here on — if it is the later
            // statement about the weight (see `refreshBodyMassFromHealth`).
            await refreshBodyMassFromHealth()
        }
        return granted
    }

    /// Keeps the high-water mark: re-enabling later must not duplicate
    /// workouts already in Health.
    func disableHealth() {
        update { $0.settings.healthEnabled = false }
    }

    /// The switch follows the permission, which HealthKit grants per device:
    /// a restored backup or an offloaded app brings the flag without it, and the
    /// person can take the workout share back in Health at any time. Every
    /// save then failed under a switch that read "on" (owner, 27.09.2026).
    /// Nothing is lost — mark and flags are kept, and turning it back on asks
    /// again and offers what is pending. Never prompts.
    func reconcileHealthAuthorization() {
        guard settings.healthEnabled,
              !(health.isAvailable && health.workoutShareGranted) else { return }
        disableHealth()
    }

    /// Kilograms in, kilograms out — the pounds a US field displays are
    /// converted before they get here. `nil` clears it, and clearing is a real
    /// answer: no weight means no calories, not calories from a default.
    func setBodyMass(_ kg: Double?) {
        update {
            $0.settings.bodyMassKg = kg.flatMap(HealthExporter.sanitizedBodyMass)
            // Typed, so it is not Health's: the flag names the origin in the
            // caption, and the DATE is what keeps the number standing — a
            // Health sample older than this moment does not replace it, a
            // newer one does. A cleared weight carries no date: clearing is
            // not a claim about a number, and Health may fill the field again.
            $0.settings.bodyMassFromHealth = false
            $0.settings.bodyMassDate = $0.settings.bodyMassKg == nil ? nil : .now
        }
    }

    /// The number the app shows — and multiplies every calorie by — follows
    /// the LATEST statement about the weight, wherever it was made: Health's
    /// newest sample when that sample is newer than the number in force, the
    /// number in force otherwise. Called on every activation and at the head
    /// of every export run. The rule is `HealthExporter.adopts(reading:over:statedAt:)`,
    /// where a test can reach it.
    ///
    /// A `nil` reading NEVER clears anything: an empty Health and a refused
    /// read are the same nil (HealthKit does not distinguish them), and
    /// erasing on it would silently switch a person's calories off. Nor does
    /// it touch the origin flag: the number still came from where it came.
    ///
    /// Writes only on a real change: this runs on every foreground, and an
    /// unconditional write would rewrite the journal file for a number
    /// that did not move.
    func refreshBodyMassFromHealth() async {
        guard settings.healthEnabled, health.isAvailable else { return }
        let reading = await healthExporter.latestBodyMass()
        // Both re-checks are about that await, not about the guard above. The
        // toggle can go down while the query hangs — the backfill loop below
        // re-reads it at every boundary for exactly this reason — and a newer
        // activation may have cancelled this run, in which case its reading is
        // the older of the two and must not land on top of the newer one.
        guard settings.healthEnabled, !Task.isCancelled else { return }
        guard let reading,
              HealthExporter.adopts(reading: reading, over: settings.bodyMassKg,
                                    statedAt: settings.bodyMassDate)
        else { return }
        guard settings.bodyMassKg != reading.kg || !settings.bodyMassFromHealth
                || settings.bodyMassDate != reading.date
        else { return }
        // The weight reaches nothing the widget shows (same argument as the
        // export flags below).
        update(refreshWidget: false) {
            $0.settings.bodyMassKg = reading.kg
            $0.settings.bodyMassFromHealth = true
            $0.settings.bodyMassDate = reading.date
        }
    }

    func setWatchRecordsWorkouts(_ on: Bool) {
        update { $0.settings.watchRecordsWorkouts = on }
    }

    var healthBackfillCount: Int {
        records.filter { $0.healthExported != true }.count
    }

    /// Journal order, one flag at a time, only on a confirmed save. Stops at
    /// the first failure so the tail stays retriable — a failed save is never
    /// declared exported, and a later success cannot leapfrog it. The
    /// in-flight guard forbids a second concurrent run; the while-loop
    /// re-reads the journal (a workout finished mid-run is picked up) and
    /// re-checks the toggle (switching it off stops at the next boundary).
    func backfillHealth() async {
        guard !backfillInFlight else { return }
        backfillInFlight = true
        defer { backfillInFlight = false }
        // Before the context, not after: the weight the calories are
        // multiplied by has to be today's, and an export can run hours after
        // the activation that last refreshed it.
        await refreshBodyMassFromHealth()
        let exporter = healthExporter
        let context = await exporter.energyContext(
            bodyMassKg: settings.bodyMassKg,
            watchRecordsWorkouts: settings.watchRecordsWorkouts,
            pending: { self.records.filter { $0.healthExported != true } })
        while settings.healthEnabled,
              let index = records.firstIndex(where: { $0.healthExported != true }) {
            let record = records[index]
            guard await exporter.export(record, context: context) else { break }   // the tail stays pending
            // The await may have replaced the whole journal (importBackup):
            // flag by identity, never by the pre-await index.
            //
            // …and by identity AMONG THE UNEXPORTED, which is what makes the
            // loop terminate. The selection above asks for an unflagged
            // record and this asks only for a matching id, so two records
            // sharing an `id` — one journal, `sessionNumber` restarted by
            // `resetProgress`, the same `date` to the double — sent every
            // flag to the FIRST of the pair while the second stayed unflagged
            // and was picked again. The loop then wrote a duplicate HKWorkout
            // per turn, forever, into a store the app cannot clean up. Only a
            // hand-edited journal reaches it, which is exactly the input every
            // decoder in this project is written against.
            guard let i = records.firstIndex(where: {
                $0.id == record.id && $0.healthExported != true
            }) else { continue }
            // Durability per record, yes. Poking WidgetKit per record, no:
            // the export flags reach nothing the widget shows, so a full
            // backfill would spend the day's reload budget on identical
            // content (same reason as saveWorkoutSnapshot).
            update(refreshWidget: false) {
                $0.records[i].healthExported = true
                $0.settings.healthExportedThrough = max($0.settings.healthExportedThrough,
                                                        record.sessionNumber)
            }
        }
    }

    /// Past workouts are declared handled so they never export later, even
    /// after toggling off and on.
    func skipHealthBackfill() {
        update {
            for i in $0.records.indices { $0.records[i].healthExported = true }
            $0.settings.healthExportedThrough = max($0.settings.healthExportedThrough,
                                                    $0.records.last?.sessionNumber ?? 0)
        }
    }
}
