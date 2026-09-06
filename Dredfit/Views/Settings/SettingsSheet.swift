//
//  Rest days, equipment, sounds, a reminder, Apple Health, backup.
//

import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import UIKit
import DredfitCore

struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var importPickerShown = false
    @State private var pendingImportURL: URL?
    @State private var importConfirmShown = false
    @State private var importFailed = false
    @State private var backfillPromptShown = false   // Apple Health
    @State private var bodyMassPromptShown = false
    @State private var bodyMassField = ""
    @State private var howItWorksShown = false
    /// Optimistic value while authorization is in flight: without it the
    /// switch visibly bounces off before the system sheet appears.
    @State private var healthSwitch: Bool?
    @State private var exportedBackup: ExportedBackup?
    @State private var exportFailed = false
    /// Whether the reminder switch was just asked to turn ON. It is the only
    /// way to tell a refusal from an ordinary turn-off — see `reminderSection`.
    @State private var reminderRequested = false
    @State private var reminderDenied = false
    /// What the pull-up bar switch was ASKED to become, while the question
    /// about the workout that answer would discard is on screen — and nil
    /// whenever there is no question. See `equipmentSection`.
    @State private var pendingBarToggle: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Settings")
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 26)

                    howItWorksSection
                    restDaysSection
                    equipmentSection
                    soundsSection
                    appearanceSection
                    reminderSection
                    healthSection
                    backupSection
                    aboutSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // Keyed like milestone.done — the same English word as the
            // workout's set button, different meaning.
            PrimaryButton(title: String(localized: "settings.done",
                                        defaultValue: "Done")) { dismiss() }
                .accessibilityIdentifier("settings-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $howItWorksShown) {
            HowItWorksView()
        }
        .fileImporter(isPresented: $importPickerShown,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                pendingImportURL = url
                importConfirmShown = true
            }
        }
        .alert(String(localized: "Replace history?"),
               isPresented: $importConfirmShown) {
            // An ALERT, not a confirmationDialog: iOS 26 presents the latter
            // as an anchored popover, so the same question drew a centred card
            // in the workout and a tailed bubble pointing at a settings row.
            // An alert has no anchor — every one of these is the same window,
            // centred, whatever it was raised from.
            //
            // And the workaround the popover forced is gone with it. A popover
            // suppresses its cancel action, because tapping outside IS the
            // cancel, so the escape had to be a SECOND, role-less button. An
            // alert does not: measured on iPhone 17 Pro / iOS 26.5, the node is
            // `Alert` with no `Popover` beside it, and all four buttons stood in
            // the accessibility tree — the `.cancel` one included. So the escape
            // is one button again, carrying the role AND the name that says what
            // it does. "Cancel" answers "cancel what?"; this one does not.
            // It also carries the cancel action's own cleanup: dismissing by a
            // tap outside never ran `pendingImportURL = nil`, so the picked
            // file stayed in state with no way to reach the line that clears
            // it.
            Button(String(localized: "Keep my history"), role: .cancel) { pendingImportURL = nil }
            Button(String(localized: "Replace"), role: .destructive) { runImport() }
        } message: {
            Text("Import replaces your current history and settings.")
        }
        .alert(String(localized: "Couldn't read this file."), isPresented: $importFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        Button {
            howItWorksShown = true
        } label: {
            backupRow(icon: "questionmark.circle",
                      title: String(localized: "How it works"))
        }
        .accessibilityIdentifier("how-it-works")
    }

    // MARK: - Rest days

    /// Respects the locale's first day.
    private var weekdaysInDisplayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var restDaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Rest days"))
            HStack(spacing: 8) {
                ForEach(weekdaysInDisplayOrder, id: \.self) { wd in
                    dayChip(wd)
                }
            }
            Text("Highlighted days are rest days")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
            // The second sentence names the rule `toggleRestDay` enforces by
            // refusing the seventh chip. Worth saying now that the chip which
            // cannot act is dimmed rather than silent (UX review 05.09.2026).
            Text("3–4 rest days a week is the recommended rhythm. At least one training day always stays.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let isRest = store.settings.restWeekdays.contains(weekday)
        // The natural way to move the week — light up the days you want off —
        // walks into `toggleRestDay`'s silent refusal on the fourth tap, and a
        // chip that absorbs a tap reads as broken beside six that answer. The
        // predicate is NOT `isRest`: what cannot happen is turning the LAST
        // training day into a rest day (UX review 05.09.2026).
        let isLocked = !isRest && store.settings.restWeekdays.count == 6
        // The marker the calendar already uses for today (CalendarScreen: an
        // accent ring). Without it the chips say nothing about which column is
        // the day you are standing in, which is what someone arriving from the
        // "Rest day" screen came here to change.
        let isToday = weekday == Calendar.current.component(.weekday, from: .now)
        let symbol = Calendar.current.shortWeekdaySymbols[weekday - 1]
        return Button {
            store.toggleRestDay(weekday)
        } label: {
            Text(symbol)
                .dredfitFont(13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isRest ? Theme.accentSoft : Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(isRest ? Theme.accent : Theme.hairline, lineWidth: 1.5))
                )
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Theme.accent, lineWidth: 2)
                            .padding(-3)
                    }
                }
                // ink, not accent: accent text on accentSoft is 2.91:1.
                .foregroundStyle(isRest ? Theme.ink : Theme.ink2)
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.4 : 1)
        .accessibilityIdentifier("weekday-\(weekday)")
        // Colour alone doesn't reach VoiceOver: without the trait a chip
        // announces only "Mon".
        .accessibilityAddTraits(isRest ? [.isSelected] : [])
        // The ring is colour only, so today has to be spoken too.
        .accessibilityLabel(isToday ? String(localized: "\(symbol), today") : symbol)
    }

    // The session-length picker is gone. The audit measured what its rungs
    // actually did: 10, 15 and 20 produced the SAME plan, and the "20" rung
    // missed its own target in 100 % of sessions. The plan handle that replaced
    // it is gone too, for a different reason: it still asked how much of the
    // workout the person had in them BEFORE they had done any of it. The engine
    // announces the range a session can land in, and the shortening happens on
    // the work screen, one skipped set at a time, where the answer is known.

    // MARK: - Sounds

    private var soundsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { store.settings.soundsEnabled },
                set: { store.setSounds($0) })) {
                Text("Sounds and haptics")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            // Only under the ON switch: with sounds off there is no tone for
            // the ringer switch to have an opinion about, and a sub-row that
            // cannot change anything is the control this wave is removing.
            if store.settings.soundsEnabled { silentModeRow }
        }
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.settings.reminderEnabled },
                set: { on in
                    reminderRequested = on
                    reminderDenied = false
                    store.setReminderEnabled(on)
                })) {
                Text("Reminder")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            // The rule was written nowhere a person could read it — not here,
            // not in How it works, not in the notification itself — and it is
            // the objection reminders get refused over (UX review 05.09.2026).
            Text("On training days only — never on a rest day, and never after you have trained.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)

            if store.settings.reminderEnabled {
                DatePicker(String(localized: "Time"),
                           selection: reminderTimeBinding,
                           displayedComponents: .hourAndMinute)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .tint(Theme.accent)
            }
            if reminderDenied { reminderDeniedNote }
        }
        // iOS asks once. For anyone who has already said no there is no system
        // sheet on the second ask — `setReminderEnabled` simply flips the
        // switch back off when authorization is refused, taking the "Time" row
        // down with it, and nothing anywhere says why. That bounce is the only
        // evidence this view gets, so it is what names the state.
        .onChange(of: store.settings.reminderEnabled) { _, enabled in
            guard reminderRequested, !enabled else { return }
            reminderRequested = false
            reminderDenied = true
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(
                    hour: store.settings.reminderHour,
                    minute: store.settings.reminderMinute)) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                store.setReminderTime(hour: c.hour ?? 9, minute: c.minute ?? 0)
            })
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Health"))
            Toggle(isOn: healthBinding) {
                Text("Save workouts to Health")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            Text("Workouts appear in the Health app. Nothing leaves your device.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
            if store.settings.healthEnabled {
                bodyMassRow
                watchToggle
            }
        }
        .alert(String(localized: "Add past workouts to Health?"),
               isPresented: $backfillPromptShown) {
            Button {
                Task { await store.backfillHealth() }
            } label: {
                Text("Export \(store.healthBackfillCount) workouts")
            }
            Button {
                store.skipHealthBackfill()
            } label: {
                Text("Only new ones")
            }
        }
        .alert(String(localized: "Body weight"), isPresented: $bodyMassPromptShown) {
            TextField(massUnitLabel, text: $bodyMassField)
                .keyboardType(.decimalPad)
            Button(String(localized: "Save")) { commitBodyMass() }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Used only to estimate the calories of each workout. It stays on this device.")
        }
    }

    /// Weight is the factor the whole estimate is multiplied by, so an absent
    /// one is not an empty field — it is the reason no calories are written.
    ///
    /// Two rows, one look. While Health supplies the weight the row does not
    /// open an editor: the phone has one owner, their weight is re-read on
    /// every activation, and a field that accepted a number only to have the
    /// next foreground replace it would be a lie. The field comes back the
    /// moment Health stops answering — no record there, or the read refused.
    private var bodyMassRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.settings.bodyMassFromHealth {
                bodyMassContent(chevron: false)
                    .accessibilityIdentifier("body-mass-row")
                    .accessibilityElement(children: .combine)
                Text("Taken from Health, and kept up to date.")
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
            } else {
                Button {
                    bodyMassField = editableBodyMass
                    bodyMassPromptShown = true
                } label: {
                    bodyMassContent(chevron: true)
                }
                .accessibilityIdentifier("body-mass-row")
                if store.settings.bodyMassKg == nil {
                    Text("Without it, workouts are saved with no calorie estimate.")
                        .dredfitFont(12.5)
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
    }

    private func bodyMassContent(chevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "scalemass")
                .dredfitFont(15, weight: .medium)
                .accessibilityHidden(true)
            Text("Body weight")
                .dredfitFont(16, weight: .medium)
            Spacer(minLength: 8)
            Text(bodyMassDisplay)
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
            if chevron {
                Image(systemName: "chevron.right")
                    .dredfitFont(12, weight: .semibold)
                    .foregroundStyle(Theme.ink2)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        // The read-only row keeps the tappable row's height, so switching
        // between them does not move the toggle underneath.
        .frame(minHeight: 44)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The manual half of the double-count guard. The automatic half reads the
    /// other workouts in Health, and HealthKit never says whether that read was
    /// allowed — a refusal looks exactly like "nothing found there", which is
    /// the wrong answer for precisely the person wearing a watch.
    ///
    /// And, since the weight started following Health, the ONLY way left to
    /// say "write no estimate at all": clearing the weight used to say it, and
    /// the field is not even reachable for the person whose Health holds a
    /// weight. So the label names the EFFECT and the caption names both
    /// reasons. The stored key stays `watchRecordsWorkouts` — it is the wire
    /// name in every saved file, and a label is not a reason to move it.
    private var watchToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { store.settings.watchRecordsWorkouts },
                set: { store.setWatchRecordsWorkouts($0) })) {
                Text("Leave calories out")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("watch-records-toggle")
            Text("""
                 Turn it on if an Apple Watch records the same workouts — \
                 otherwise the session counts twice — or if you simply want \
                 no estimate written.
                 """)
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
    }

    /// A denial leaves the toggle off. On success, past history is offered
    /// once.
    private var healthBinding: Binding<Bool> {
        Binding(
            get: { healthSwitch ?? store.settings.healthEnabled },
            set: { on in
                guard on else {
                    healthSwitch = nil
                    return store.disableHealth()
                }
                healthSwitch = true
                Task {
                    let granted = await store.enableHealth()
                    healthSwitch = nil   // reality (granted or denied) takes over
                    if granted, store.healthBackfillCount > 0 {
                        backfillPromptShown = true
                    }
                }
            })
    }

    // MARK: - Backup

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: String(localized: "Backup"))
            // The control says "history"; the file holds the whole `settings`
            // block too, weight included (AppStore+Backup.exportURL). The one
            // line that ever named settings stood in the IMPORT alert — read,
            // if at all, long after the file had been sent somewhere. Not a
            // broken promise (nothing here goes anywhere by itself) but an
            // under-described one — so this line stands ABOVE the rows, where
            // the other sections put theirs below (UX review 05.09.2026).
            Text("""
                 The file holds your history, your plan and your settings — \
                 including your weight, if you entered one. It goes only where \
                 you send it.
                 """)
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
            exportRow
            Button {
                importPickerShown = true
            } label: {
                backupRow(icon: "square.and.arrow.down",
                          title: String(localized: "Import history"))
            }
            // A frozen launch would import into the empty state that stood in
            // for the real journal.
            .disabled(store.journalFrozen)
            // backupRow sets Theme.ink itself, so `disabled` alone leaves a
            // live-looking row that quietly does nothing.
            .opacity(store.journalFrozen ? 0.4 : 1)
            if store.journalFrozen { frozenNote }
        }
    }

    private func backupRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .dredfitFont(15, weight: .medium)
                .accessibilityHidden(true)
            Text(title)
                .dredfitFont(16, weight: .medium)
            Spacer()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: String(localized: "About"))
            Link(destination: Self.reviewURL) {
                backupRow(icon: "star", title: String(localized: "Rate on the App Store"))
            }
            ShareLink(item: Self.appStoreURL) {
                backupRow(icon: "heart", title: String(localized: "Recommend Dredfit"))
            }
            // ink2, not ink3: ink3 is 2.35:1 on the light ground, and a
            // version line is the string a bug report is read off. Quiet is
            // the ROLE of this line; unreadable was an oversight
            // (owner's call, UX review 05.09.2026).
            Text(versionLine)
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
    }

    private static let appStoreURL = URL(string: "https://apps.apple.com/app/id6791739610")!
    private static let reviewURL = URL(string:
        "https://apps.apple.com/app/id6791739610?action=write-review")!

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Dredfit \(version) (\(build))"
    }

    private func runImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        do {
            try store.importBackup(from: url)
        } catch {
            importFailed = true
        }
    }
}

// MARK: - Equipment, export and the notes, in an extension
//
// Not in the type body: SettingsSheet is the tallest view in the app and the
// linter's 600-line ceiling on a TYPE BODY is a CI error. An extension does
// not count towards it — the same split AppStore lives under.

extension SettingsSheet {

    // MARK: - Equipment
    //
    // In the extension for the reason the block below it is: the linter bounds
    // a TYPE's own body at 600 lines as a CI error, and this section grew a
    // confirmation alert (UX review 05.09.2026, finding 6). An extension in the
    // same file weighs nothing against that ceiling and keeps every private
    // member reachable.

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Equipment"))
            Toggle(isOn: Binding(
                get: { pendingBarToggle ?? store.engineState.hasBar },
                set: { on in
                    // The switch regenerates today's session, and a workout in
                    // flight is fingerprinted against the OLD one. After the
                    // flip `resumableWorkout()` returns nil, so the resume card
                    // on Today just disappears — and the sets already done are
                    // not recorded either: `settleAbandonedWorkout` refuses a
                    // snapshot whose fingerprint no longer matches the session.
                    // A switch that silently spends a workout has to ask first
                    // (UX review 05.09.2026, finding 6).
                    guard store.barToggleWouldDiscardWorkout(on) else {
                        return store.setHasBar(on)
                    }
                    pendingBarToggle = on
                })) {   // the alert below answers for it
                Text("Pull-up bar")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("hasbar-toggle")
            Text("Every other workout swaps the horizontal pull for a vertical one")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
        // An ALERT, like every other question in this app: iOS 26 draws a
        // confirmationDialog as an anchored popover, which suppresses its own
        // cancel and reads a stray tap as an answer.
        //
        // Flipping the switch BACK inside the three-hour window makes the
        // snapshot match again and the workout resumable again — which is why
        // the message does not offer that as a way out. It would be a promise
        // about a clock the person cannot see.
        //
        // Driven by the optional rather than by a Bool, so BOTH ways out clear
        // the mirror — the switch snaps back to the state on a cancel with no
        // cleanup line of its own to forget. It is also what makes the flipped
        // switch visible at all: `setHasBar` is never called, so nothing in the
        // store changes and nothing would redraw the row.
        .alert(String(localized: "Drop today's unfinished workout?"),
               isPresented: Binding(get: { pendingBarToggle != nil },
                                    set: { if !$0 { pendingBarToggle = nil } }),
               presenting: pendingBarToggle) { on in
            Button(String(localized: "Keep the workout"), role: .cancel) { }
            Button(String(localized: "Switch the bar"), role: .destructive) {
                store.setHasBar(on)
            }
        } message: { _ in
            Text("""
                 The bar changes today's plan, so the workout you started can't \
                 be picked up again and the sets already done won't be recorded. \
                 Finish it first and nothing is lost.
                 """)
        }
    }


    // MARK: - Sounds past the ringer switch

    /// The other half of "Sounds and haptics", and the half a silent phone
    /// makes matter. One switch drives two channels and only one of them
    /// answers to the hardware: the tones play in `.ambient`, which the Silent
    /// switch mutes, while the haptics carry the session on their own and were
    /// weighted apart for exactly that case (`WorkoutSignals`). Unsaid, an ON
    /// switch in a silent room reads as a broken app — and early morning, when
    /// Silent is on, is when people train (UX review 05.09.2026, finding 53).
    ///
    /// Off by default: a phone silenced in a gym was silenced on purpose, so
    /// this is the athlete saying otherwise rather than the app deciding for
    /// them. The category actually moves — `RootView` pushes the choice into
    /// `CountdownSounds` — so the caption below can name what will happen
    /// instead of describing a switch that changes nothing.
    private var silentModeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { store.settings.playsTonesInSilentMode },
                set: { store.setPlaysTonesInSilentMode($0) })) {
                Text("Play tones in Silent mode")
                    .dredfitFont(15)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("silent-mode-toggle")
            Group {
                if store.settings.playsTonesInSilentMode {
                    Text("The tones play even with the ringer switch off.")
                } else {
                    Text("In Silent mode the tones go quiet — the vibration keeps going.")
                }
            }
            .dredfitFont(12.5)
            .foregroundStyle(Theme.ink2)
        }
    }

    // MARK: - Appearance

    /// A theme of its own, applied by the single `.preferredColorScheme` on
    /// `RootView` (finding 54). Three chips rather than a menu, and the same
    /// chips the rest days use: the choice is small, always visible, and worth
    /// no more room than a week of weekdays.
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Appearance"))
            HStack(spacing: 8) {
                appearanceChip(.system, String(localized: "appearance.system",
                                               defaultValue: "System"))
                appearanceChip(.light, String(localized: "appearance.light",
                                              defaultValue: "Light"))
                appearanceChip(.dark, String(localized: "appearance.dark",
                                             defaultValue: "Dark"))
            }
            // The one limit worth saying out loud: widgets and the Lock Screen
            // are drawn by another process, which never sees this choice.
            // Better said here than discovered as a bug on the Home Screen.
            Text("Widgets and the Lock Screen keep following the system.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
    }

    /// Keyed by the raw value, which is also the wire name in the settings
    /// file — an identifier a UI test can rely on without reading a label that
    /// changes with the locale.
    private func appearanceChip(_ choice: AppearanceChoice, _ title: String) -> some View {
        let isOn = store.settings.appearance == choice
        return Button {
            store.setAppearance(choice)
        } label: {
            Text(title)
                .dredfitFont(13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isOn ? Theme.accentSoft : Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? Theme.accent : Theme.hairline, lineWidth: 1.5))
                )
                // ink, not accent: accent text on accentSoft is 2.91:1 — the
                // same pin the day chips carry.
                .foregroundStyle(isOn ? Theme.ink : Theme.ink2)
        }
        .accessibilityIdentifier("appearance-\(choice.rawValue)")
        // Colour alone doesn't reach VoiceOver: without the trait all three
        // chips announce the same thing.
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Body weight, shown in the locale's unit and stored in one
    //
    // Moved out of the type body unchanged when the UX-review captions were
    // added (05.09.2026): the body carries the linter's 600-line ceiling and
    // an extension does not, so the block that no longer needed to be near the
    // rows went first.

    /// Displayed in pounds where the locale uses them; the store keeps
    /// kilograms always, because a file carrying both cannot be read back.
    private var massUnit: UnitMass {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }

    private var massUnitLabel: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        return formatter.string(from: massUnit)
    }

    private var bodyMassDisplay: String {
        guard let kg = store.settings.bodyMassKg else { return String(localized: "Not set") }
        return Measurement(value: kg, unit: UnitMass.kilograms)
            .converted(to: massUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    private var editableBodyMass: String {
        guard let kg = store.settings.bodyMassKg else { return "" }
        return Measurement(value: kg, unit: UnitMass.kilograms)
            .converted(to: massUnit).value
            .formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// An empty or unreadable field CLEARS the weight rather than keeping the
    /// old one. What it no longer does is switch the calories off: Health
    /// re-supplies the number on the next activation, and while it does, this
    /// field is not even reachable. "Write no estimate" is said with the
    /// toggle below instead — that promise moved, it did not disappear. The
    /// comma is accepted because half the shipping locales type one.
    private func commitBodyMass() {
        let typed = bodyMassField
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(typed), value > 0 else {
            return store.setBodyMass(nil)
        }
        store.setBodyMass(Measurement(value: value, unit: massUnit)
            .converted(to: .kilograms).value)
    }

    /// The file is built by the TAP and only then shared, where before it was
    /// handed to `ShareLink` as a lazy `Transferable`. The old shape had
    /// nowhere to put a failure: the throw happened inside the transfer
    /// representation, so a file that could not be written produced silence and
    /// left the belief that a backup existed. Import has always had its alert;
    /// the rescuing half of the pair has one now too (UX review 05.09.2026).
    ///
    /// The sheet and the alert hang HERE rather than on the root view, which
    /// already carries two alerts and a sheet of its own.
    private var exportRow: some View {
        Button {
            do {
                let url = try store.exportURL()
                exportedBackup = ExportedBackup(url: url)
            } catch {
                exportFailed = true
            }
        } label: {
            backupRow(icon: "square.and.arrow.up",
                      title: String(localized: "Export history"))
        }
        // A frozen launch would export the empty state that stood in for the
        // real journal.
        .disabled(store.journalFrozen)
        .opacity(store.journalFrozen ? 0.4 : 1)
        .sheet(item: $exportedBackup) { file in
            ShareSheet(url: file.url) { exportedBackup = nil }
        }
        .alert(String(localized: "Couldn't build the backup file."), isPresented: $exportFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    /// A frozen launch shows an empty history everywhere and disables both
    /// backup rows, and said so nowhere in the app.
    private var frozenNote: some View {
        Text("""
             Your history couldn't be read on this launch, so it can't be \
             backed up. Unlock the phone and open Dredfit again.
             """)
            .dredfitFont(12.5)
            .foregroundStyle(Theme.ink2)
    }

    /// The one setting with no way back from inside the app: after a refusal
    /// iOS never asks again, so without this the switch just bounces.
    private var reminderDeniedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notifications are off for Dredfit, so the reminder can't be set from here.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    backupRow(icon: "bell", title: String(localized: "Open iOS Settings"))
                }
            }
        }
    }
}

// MARK: - The share sheet

/// `.sheet(item:)` needs an `Identifiable`, and a URL is not one.
private struct ExportedBackup: Identifiable {
    let url: URL
    var id: URL { url }
}

/// `ShareLink` cannot be raised from code, and the file exists only once the
/// row has been tapped — so the activity sheet is presented directly. It is
/// the very same controller `ShareLink` would have shown.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url],
                                                  applicationActivities: nil)
        // Embedded in a SwiftUI sheet the controller cannot dismiss itself:
        // cancelling would leave an empty sheet standing.
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
