//
//  Every accessibility identifier the UI suite reaches for, in one place, and
//  the two named ways it is allowed to set launch arguments.
//
//  Both halves answer the same defect: what each call site spells for itself
//  drifts. Identifiers exist so a test does not depend on an English string,
//  and a test that reaches for the string anyway is drift nothing catches — a
//  renamed identifier lights up no compiler error inside a string literal,
//  and without one place for the names the only guard is a grep somebody has
//  to remember to run.
//
//  A constant is not a stronger guard than a literal by itself — it is
//  stronger because there is exactly ONE of it, so the grep is a rename and
//  the next reader can see every name the suite depends on without walking
//  ten files.
//

import XCTest

/// Identifiers, grouped by the screen that carries them. Names match the
/// production `accessibilityIdentifier` verbatim, which is the whole point:
/// the pair is meant to be greppable in one step.
enum AX {

    // MARK: - Today

    static let startWorkout = "start-workout"
    static let trainAnyway = "train-anyway"
    static let planLength = "plan-length"
    static let settings = "settings"
    static let settingsDone = "settings-done"
    /// The row is per pattern (`plan-row-squat`, `plan-row-push_h`, …); the
    /// prefix is what a test that does not care WHICH movement asks for.
    static let planRowPrefix = "plan-row-"
    /// The ONE name here that matches nothing in production, and deliberately:
    /// the per-movement handle lives in the technique sheet, not on the plan,
    /// and the test that proves it asks for this prefix precisely so a handle
    /// that comes back is a red test rather than a silently restored row.
    static let easierHandlePrefix = "easier-"
    static let techniqueHint = "technique-hint"
    static let nextWorkoutDone = "next-workout-done"

    // MARK: - Onboarding, resume and the comeback card

    static let onboardingPrimary = "onboarding-primary"
    static let onboardingSkip = "onboarding-skip"
    static let resumeContinue = "resume-continue"
    static let resumeRestart = "resume-restart"
    static let comebackAccept = "comeback-accept"
    static let comebackDecline = "comeback-decline"
    static let comebackFresh = "comeback-fresh"

    // MARK: - Work screen

    /// The exit control, and the hidden twin that only balances the header.
    /// Both are named so a query cannot pick the placeholder — a name is a
    /// stronger guard than `.firstMatch` and an ordering assumption.
    static let workoutExit = "workout-exit"
    static let workoutExitSpacer = "workout-exit-spacer"
    static let exerciseDone = "exercise-done"
    /// The tap that buys the WHOLE hold exercise — the control a hold opens
    /// on. `holdStart` below re-arms ONE set and is a different screen state:
    /// a Stop inside the mis-tap grace, or the probe, which the auto-run
    /// deliberately does not start for you. Two names because they are two
    /// controls; a query that resolved either would hide the difference.
    static let holdStartExercise = "hold-start-exercise"
    static let holdStart = "hold-start"
    static let holdStop = "hold-stop"
    static let holdSetsAndRest = "hold-sets-and-rest"
    static let holdAutorunPromise = "hold-autorun-promise"
    /// The one entry a hold takes BEFORE the effort: how long it will run.
    static let holdSetTime = "hold-set-time"

    // MARK: - Exercise summary

    /// The cards are 1-based, like the captions they carry.
    static func summarySet(_ number: Int) -> String { "summary-set-\(number)" }
    /// The one sentence under the cards, about the past.
    static let summaryCounted = "summary-counted"
    /// The "next time" block: the sentence that names the plan the engine
    /// will set, and the stepper that raises it. The sentence is what a test
    /// reads — it changes with every tap on the stepper, which is the whole
    /// promise of the block.
    static let summaryNextPlan = "summary-next-plan"
    static let raisePlus = "raise-plus"
    static let raiseMinus = "raise-minus"
    static let raiseValue = "raise-value"
    /// The addition, listed on the rating screen per movement.
    static func feedbackRaised(_ pattern: String) -> String { "feedback-raised-\(pattern)" }
    /// The kicker. Named because `.textCase(.uppercase)` folds the string the
    /// tree carries — a query for "Held" as written matches nothing.
    static let summaryHeld = "summary-held"
    static let exerciseAdjust = "exercise-adjust"
    static let exerciseSkip = "exercise-skip"
    static let exerciseSkipSet = "exercise-skip-set"
    static let exerciseSkipRest = "exercise-skip-rest"
    static let technique = "technique"
    static let techniqueDone = "technique-done"
    static let techniqueLife = "technique-life"
    /// The sheet's own headline, and the block under the variation tag that
    /// offers the rung below it. The headline is identified because the
    /// step-down test reads it: what the block promises is that this title
    /// becomes the movement it named.
    static let techniqueTitle = "technique-title"
    static let techniqueStepDown = "technique-step-down"
    static let timeLeft = "time-left"
    static let adjustMinus = "minus"
    static let adjustPlus = "plus"
    static let adjustConfirm = "adjust-confirm"

    // MARK: - Rest

    static let skipRest = "skip-rest"
    static let extendRest = "extend-rest"

    // MARK: - Blocks (warm-up, cool-down, transitions)

    static let warmupStart = "warmup-start"
    static let warmupIntroSkip = "warmup-intro-skip"
    static let warmupCountdown = "warmup-countdown"
    static let skipWarmup = "skip-warmup"
    static let cooldownStart = "cooldown-start"
    static let cooldownIntroSkip = "cooldown-intro-skip"
    static let cooldownCountdown = "cooldown-countdown"
    static let skipCooldown = "skip-cooldown"
    static let getReadyCountdown = "getready-countdown"
    static let getReadyStart = "get-ready-start"
    static let reentryCountdown = "reentry-countdown"
    static let blockPause = "block-pause"
    static let blockResume = "block-resume"
    static let positionTechniqueDone = "position-technique-done"

    // MARK: - Rating and what follows it

    /// The three cards are `rating-<FeedbackResult.rawValue>`.
    static let ratingLess = "rating-less"
    static let ratingPlan = "rating-plan"
    static let ratingMore = "rating-more"
    static let milestoneDone = "milestone-done"
    static let jubileeRetro = "jubilee-retro"
    static let milestoneLife = "milestone-life"

    // MARK: - Progress, calendar, settings

    static let totalSteps = "total-steps"
    static let historyDone = "history-done"
    /// The first group's kicker — the anchor for "Settings opened". By
    /// identifier: the words are localized and uppercased by `Kicker`, and
    /// the group has been renamed before (Rest days → Weekly rhythm), which
    /// turned four tests red for a label.
    static let settingsRhythm = "settings-rhythm"
    static let howItWorks = "how-it-works"
    static let howItWorksDone = "how-it-works-done"
    static let hasBarToggle = "hasbar-toggle"
    /// Calendar's weekday chips and day cells are indexed —
    /// `weekday-2` is Monday, `day-17` the seventeenth.
    static func weekday(_ index: Int) -> String { "weekday-\(index)" }
    static func day(_ number: Int) -> String { "day-\(number)" }
}

/// The locale a launch is pinned to. Pinned rather than inherited because the
/// English suite asserts on English strings, and the S7 smoke row exists to
/// catch English leaking into the Russian build.
enum UILocale {
    case english, russian

    var arguments: [String] {
        switch self {
        case .english: return ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        case .russian: return ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        }
    }
}

extension XCUIApplication {

    /// The ONE way this suite starts from a clean state. `--uitest-reset` and
    /// the locale are added here rather than spelled at the call site, because
    /// spelling them is how they get lost: a test that assigns
    /// `launchArguments` outright to add a seed drops the reset with it and
    /// runs on whatever the previous test left behind. A seed such as
    /// `--uitest-session2` can keep it green regardless — its hook clears the
    /// engine state and the journal, side effects invisible from the test —
    /// which is exactly the kind of accident that survives until the day
    /// somebody touches settings.
    func seedLaunchArguments(_ seeds: String..., locale: UILocale = .english) {
        seedLaunchArguments(seeds, locale: locale)
    }

    /// The same thing for a caller that BUILDS its seed list — an arrange
    /// helper that takes extra flags from its own caller cannot splat a
    /// variadic. One body, so the reset cannot be present in one form and
    /// missing from the other.
    func seedLaunchArguments(_ seeds: [String], locale: UILocale = .english) {
        launchArguments = ["--uitest-reset"] + seeds + locale.arguments
    }

    /// The deliberate exception, and it has a name so that dropping the reset
    /// is always a decision rather than an omission: these launches read back
    /// the state a walk has just written, so resetting would erase the subject.
    func storedStateLaunchArguments(_ seeds: String..., locale: UILocale = .english) {
        launchArguments = seeds + locale.arguments
    }

    /// A second app object on the state the first one wrote. `terminate()`
    /// first: `launch()` alone relaunches a running app, and the callers
    /// assert about a COLD start.
    @MainActor
    static func launchedOnStoredState(_ seeds: String...,
                                      locale: UILocale = .english) -> XCUIApplication {
        let relaunch = XCUIApplication()
        // The seeds are forwarded, the RESET is still not: these launches read
        // back what a walk has just written, and a reset would erase the
        // subject. A flag that shortens a countdown is not state.
        relaunch.launchArguments = seeds + locale.arguments
        relaunch.terminate()
        relaunch.launch()
        return relaunch
    }

    /// The rating cards are custom-labelled buttons whose title also stands in
    /// the tree as a static text of its own, so a query by element type has
    /// to guess which of the two to ask for. Asked for by identifier across
    /// every element type, the query resolves whichever of the two carries the
    /// identifier, so it cannot go stale on a SwiftUI change of that detail.
    func element(withIdentifier identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
