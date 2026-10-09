//
//  Every testTag the UI suite reaches for, in one place — the same names as
//  `enum AX` in ios/DredfitUITests/AccessibilityID.swift, because testTag is
//  this platform's accessibilityIdentifier and one name per control keeps the
//  two suites greppable in one step. A renamed tag lights up no compiler
//  error inside a string literal; one constant per name is the guard.
//
//  Absent on purpose: `easierHandlePrefix`, which on iOS names a handle that
//  must NOT come back.
//

package com.dredfit

object AX {
    // Today
    const val startWorkout = "start-workout"
    const val trainAnyway = "train-anyway"
    const val planLength = "plan-length"
    const val settings = "settings"
    const val settingsDone = "settings-done"
    const val planRowPrefix = "plan-row-"
    const val techniqueHint = "technique-hint"
    const val nextWorkoutDone = "next-workout-done"

    // Onboarding
    const val onboardingPrimary = "onboarding-primary"
    const val onboardingSkip = "onboarding-skip"

    // Resume and the comeback card
    const val resumeContinue = "resume-continue"
    const val resumeRestart = "resume-restart"
    const val comebackAccept = "comeback-accept"
    const val comebackDecline = "comeback-decline"
    const val comebackFresh = "comeback-fresh"

    // Work screen
    const val workoutExit = "workout-exit"
    const val exerciseDone = "exercise-done"
    const val holdStartExercise = "hold-start-exercise"
    const val holdStart = "hold-start"
    const val holdStop = "hold-stop"
    const val holdSetsAndRest = "hold-sets-and-rest"
    const val holdAutorunPromise = "hold-autorun-promise"
    const val holdSetTime = "hold-set-time"

    // Exercise summary
    fun summarySet(number: Int) = "summary-set-$number"
    const val summaryCounted = "summary-counted"
    const val summaryNextPlan = "summary-next-plan"
    const val raisePlus = "raise-plus"
    const val raiseMinus = "raise-minus"
    const val raiseValue = "raise-value"
    fun feedbackRaised(pattern: String) = "feedback-raised-$pattern"
    const val summaryHeld = "summary-held"
    const val exerciseAdjust = "exercise-adjust"
    const val exerciseSkip = "exercise-skip"
    const val exerciseSkipSet = "exercise-skip-set"
    const val exerciseSkipRest = "exercise-skip-rest"
    const val technique = "technique"
    const val techniqueDone = "technique-done"
    const val techniqueLife = "technique-life"
    const val techniqueTitle = "technique-title"
    const val techniqueStepDown = "technique-step-down"
    const val timeLeft = "time-left"
    const val adjustMinus = "minus"
    const val adjustPlus = "plus"
    const val adjustConfirm = "adjust-confirm"

    // Rest
    const val skipRest = "skip-rest"
    const val extendRest = "extend-rest"

    // Blocks
    const val warmupStart = "warmup-start"
    const val warmupIntroSkip = "warmup-intro-skip"
    const val warmupCountdown = "warmup-countdown"
    const val skipWarmup = "skip-warmup"
    const val cooldownStart = "cooldown-start"
    const val cooldownIntroSkip = "cooldown-intro-skip"
    const val cooldownCountdown = "cooldown-countdown"
    const val skipCooldown = "skip-cooldown"
    const val getReadyCountdown = "getready-countdown"
    const val getReadyStart = "get-ready-start"
    const val reentryCountdown = "reentry-countdown"
    const val blockPause = "block-pause"
    const val blockResume = "block-resume"
    const val positionTechniqueDone = "position-technique-done"

    // Rating and what follows it
    const val ratingLess = "rating-less"
    const val ratingPlan = "rating-plan"
    const val ratingMore = "rating-more"
    const val milestoneDone = "milestone-done"
    const val jubileeRetro = "jubilee-retro"
    const val milestoneLife = "milestone-life"

    // Progress, calendar, settings
    const val totalSteps = "total-steps"
    const val historyDone = "history-done"
    const val settingsRhythm = "settings-rhythm"
    const val howItWorks = "how-it-works"
    const val howItWorksDone = "how-it-works-done"
    const val hasBarToggle = "hasbar-toggle"
    fun weekday(index: Int) = "weekday-$index"
    fun day(number: Int) = "day-$number"

    // Android-only: the alerts' buttons carry names here (an iOS alert
    // button has no identifier, so the iOS suite taps them by label).
    const val skipConfirm = "skip-confirm"
    const val exitFinishLater = "exit-finish-later"
    const val exitFinishNow = "exit-finish-now"
    const val exitDiscard = "exit-discard"
    const val nextWorkout = "next-workout"
    const val changeRating = "change-rating"

    // Android-only: the tab bar (iOS taps its tabs by label), the controls
    // the iOS suite reaches by label, and the history sheet's walk.
    fun tab(name: String) = "tab-$name"
    const val onboardingCare = "onboarding-care"
    const val todayRecord = "today-record"
    const val historyEarlier = "history-earlier"
    const val historyLater = "history-later"
    const val showAll = "show-all"
    fun progressRow(pattern: String) = "progress-row-$pattern"
    const val progressMilestone = "progress-milestone"
    const val shareProgress = "share-progress"
    const val monthPrevious = "month-previous"
    const val soundsToggle = "sounds-toggle"
    const val silentModeToggle = "silent-mode-toggle"
    const val exportHistory = "export-history"
    fun appearance(raw: String) = "appearance-$raw"
}
