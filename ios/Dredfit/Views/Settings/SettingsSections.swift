//
//  The smaller groups of the settings screen: the week, the equipment,
//  sounds, the theme and the footer.
//

import SwiftUI
import UIKit
import DredfitCore

struct RhythmSection: SettingsGroup {
    @Environment(AppStore.self) private var store

    /// Whether the reminder switch was just asked to turn ON. It is the only
    /// way to tell a refusal from an ordinary turn-off — see `reminderField`.
    @State private var reminderRequested = false
    @State private var reminderDenied = false

    /// Respects the locale's first day.
    private var weekdaysInDisplayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    /// The rest days and the reminder under one name — the one "How it
    /// works" gives this rule (`Weekly rhythm`, glossary): the reminder is
    /// about the same week, fires on training days only, and toggling a
    /// rest day reschedules it. It used to stand three groups lower with no
    /// kicker, where the eye attached it to Appearance.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsKicker(String(localized: "Weekly rhythm"), id: "settings-rhythm")
            VStack(alignment: .leading, spacing: 6) {
                // A titled field, like the reminder under it: the chips are
                // the control and this is what they set.
                Text("Rest days")
                    .dredfitFont(16, weight: .medium)
                    .padding(.bottom, 4)
                HStack(spacing: 8) {
                    ForEach(weekdaysInDisplayOrder, id: \.self) { wd in
                        dayChip(wd)
                    }
                }
                caption(String(localized: "Highlighted days are rest days"))
                // The second sentence names the rule `toggleRestDay` enforces by
                // refusing the seventh chip. Worth saying now that the chip which
                // cannot act is dimmed rather than silent (UX review 05.09.2026)
                // — and it belongs under the chips, not under the reminder that
                // follows them, or it reads as the reminder's rule.
                caption(String(localized: "3–4 rest days a week is the recommended rhythm. At least one training day always stays."))
            }
            reminderField
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

    // MARK: - Reminder

    private var reminderField: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
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
                // The rule was written nowhere a person could read it — not
                // here, not in How it works, not in the notification itself —
                // and it is the objection reminders get refused over (UX
                // review 05.09.2026).
                caption(String(localized: "On training days only — never on a rest day, and never after you have trained."))
            }
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
                // Today's date under the time: hour and minute alone make a
                // year-0001 date, where historical time-zone offsets skew the
                // shown time. Not `date(bySettingHour:)`, which can shift on
                // a DST day.
                var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                c.hour = store.settings.reminderHour
                c.minute = store.settings.reminderMinute
                return Calendar.current.date(from: c) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                store.setReminderTime(hour: c.hour ?? 9, minute: c.minute ?? 0)
            })
    }

    /// The one setting with no way back from inside the app: after a refusal
    /// iOS never asks again, so without this the switch just bounces.
    private var reminderDeniedNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption(String(localized: "Notifications are off for Dredfit, so the reminder can't be set from here."))
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    backupRow(icon: "bell", title: String(localized: "Open iOS Settings"))
                }
            }
        }
    }
}

// MARK: - Equipment

struct EquipmentSection: SettingsGroup {
    @Environment(AppStore.self) private var store

    /// What the pull-up bar switch was ASKED to become, while the question
    /// about the workout that answer would discard is on screen — and nil
    /// whenever there is no question. See `body`.
    @State private var pendingBarToggle: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsKicker(String(localized: "Equipment"), id: "settings-equipment")
                .padding(.bottom, 8)
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
            caption(String(localized: "Every other workout swaps the horizontal pull for a vertical one"))
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
}

// MARK: - Sounds

struct SoundsSection: SettingsGroup {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Named like every other group: without a kicker the switch read
            // as the last row of Equipment.
            settingsKicker(String(localized: "Sounds"), id: "settings-sounds")
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
            caption(store.settings.playsTonesInSilentMode
                    ? String(localized: "The tones play even with the ringer switch off.")
                    : String(localized: "In Silent mode the tones go quiet — the vibration keeps going."))
        }
    }
}

// MARK: - Appearance

struct AppearanceSection: SettingsGroup {
    @Environment(AppStore.self) private var store

    /// A theme of its own, applied by the single `.preferredColorScheme` on
    /// `RootView` (finding 54). Three chips rather than a menu, and the same
    /// chips the rest days use: the choice is small, always visible, and worth
    /// no more room than a week of weekdays.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsKicker(String(localized: "Appearance"), id: "settings-appearance")
                .padding(.bottom, 8)
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
            caption(String(localized: "Widgets and the Lock Screen keep following the system."))
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
}

// MARK: - About

struct AboutSection: SettingsGroup {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsKicker(String(localized: "About"), id: "settings-about")
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
            caption(versionLine)
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
}
