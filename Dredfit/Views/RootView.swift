//
//  The settings icon overlays the TabView so it is reachable from any tab,
//  not owned by one screen.
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: Hashable { case today, calendar, progress }
    @State private var tab: Tab = .today
    @State private var settingsShown = false
    @State private var onboardingShown = false
    /// Whether the audio session has been told the silent-mode choice at least
    /// once this launch. `CountdownSounds` generates every tone the moment it
    /// is first touched, and it starts at the category the default choice
    /// wants — so a launch that never turns the option on must not build it
    /// (finding 53, UX review 05.09.2026).
    @State private var silentModeApplied = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.inset.filled") }
                .tag(Tab.today)
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
        }
        .tint(Theme.ink)
        // The tab screens are transparent stacks: this is the one ground
        // they all sit on, in place of the implicit system white.
        .background(Theme.bg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                settingsShown = true
            } label: {
                Image(systemName: "gearshape")
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("settings")
            .accessibilityLabel(Text("Settings"))
            .padding(.top, 4)
            .padding(.trailing, 11)
        }
        .sheet(isPresented: $settingsShown) {
            SettingsSheet()
        }
        .fullScreenCover(isPresented: $onboardingShown) {
            OnboardingView {
                store.completeOnboarding()
                onboardingShown = false
            }
        }
        .onAppear {
            // A cold launch renders already `.active`, so the phase change
            // below never fires for it — without this call a comeback after
            // 7–13 days away would train on pre-break levels.
            store.activate()
            onboardingShown = store.shouldShowOnboarding
        }
        // A cold start never has a live workout: anything still alive belongs
        // to a killed process and must leave the lock screen now, not at the
        // system's hours-long cap.
        .task { WorkoutActivityController.endOrphans() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // An active scene proves the device is unlocked: the journal
                // gets its second read, the day re-anchors with the
                // blind-zone decay, and the reminder window is rebuilt so it
                // never runs dry while the app is in use.
                store.activate()
            case .background:
                store.refreshWidgetSnapshot()
            default:
                break
            }
        }
        // The audio category is PROCESS state, not a setting: a choice saved
        // yesterday configures nothing by itself, and the switch in Settings
        // has to be audible on the very next countdown. One observer covers
        // both, plus the third writer nobody would remember — importing a
        // backup replaces the whole settings block (finding 53).
        //
        // The guard is what keeps a launch on the default free: a `false` that
        // has never been contradicted asks for exactly the category
        // `CountdownSounds` starts at, so touching the singleton to say so
        // would only pay for six tone buffers nobody has asked to hear yet.
        .onChange(of: store.settings.playsTonesInSilentMode, initial: true) { _, on in
            guard on || silentModeApplied else { return }
            silentModeApplied = true
            CountdownSounds.shared.setPlaysInSilentMode(on)
        }
        // The ONE place the theme is applied, and the reason it is here rather
        // than in the Settings sheet that offers it: from the root of the
        // window it also covers the workout's full-screen cover, every sheet
        // and every alert. A picker that leaves the workout on the system
        // theme would be worse than no picker (finding 54).
        //
        // Widgets and the Live Activity are drawn by another process, which
        // never sees this — which is what the caption under the picker says.
        .preferredColorScheme(store.settings.appearance.colorScheme)
    }
}

private extension AppearanceChoice {
    /// `nil` is not "no answer" here — it is how `preferredColorScheme` spells
    /// "follow the system", which is why the mapping lives beside its one
    /// caller instead of in `AppSettings` (which imports no SwiftUI).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
