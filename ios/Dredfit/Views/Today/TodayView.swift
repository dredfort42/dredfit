//
//  Three states: plan + Start, rest day, or completed with a preview of the
//  next workout under its honest date.
//

import SwiftUI
import DredfitCore

/// The session is snapshotted at tap time, not read live inside the cover
/// closure: completeWorkout advances the engine before the cover dismisses,
/// and a live read would flip the rating screen to the NEXT session's data.
struct ActiveWorkout: Identifiable {
    let session: Session
    var resume: WorkoutSnapshot?
    /// Straight to the rating: the card's answer to "keep this workout?".
    var settleImmediately = false
    var id: Int { session.sessionNumber }
}

/// The movement the suspect question is about and the name of what sits below
/// it — together, because the alert has to NAME the movement it is about, and
/// the name comes from the engine's answer rather than from the question.
struct SuspectStepDown: Identifiable {
    let pattern: Pattern
    let name: String
    var id: String { pattern.rawValue }
}

struct TodayView: View {
    /// Every sheet this screen raises, behind one `.sheet(item:)`.
    enum Destination: Identifiable {
        case technique(TechniqueTarget)
        case nextWorkout
        case history(WorkoutRecord)

        var id: String {
            switch self {
            case .technique(let target): "technique-\(target.id)"
            case .nextWorkout: "nextWorkout"
            case .history(let record): "history-\(record.id)"
            }
        }
    }

    @Environment(AppStore.self) private var store
    @State private var activeWorkout: ActiveWorkout?
    @State private var destination: Destination?
    @State private var freshStartConfirmShown = false
    /// The questions this screen asks before it acts. Each stands in
    /// FRONT of a change that cannot be taken back — the rule the four skips
    /// and the technique sheet already follow (SkipConfirmation.swift).
    ///
    /// They live here, not in the views that ask them: those come and go as
    /// the day moves between plan, rest and completed, and a question raised
    /// across that switch must not be forgotten with the view.
    @State private var startOverConfirmShown = false
    @State private var pendingSuspect: SuspectStepDown?
    @State private var ratingChangeShown = false

    var body: some View {
        Group {
            if store.doneToday {
                DoneView(destination: $destination,
                         ratingChangeShown: $ratingChangeShown)
            } else if store.restAppliesToday {
                // `restApplies`, not `isRestDay`: rest is rest FROM something,
                // and an install whose onboarding happened to end on a marked
                // weekday met "come back on Tuesday" as its very first screen
                // (UX review 05.09.2026, finding 7). `WidgetBridge`'s
                // `widgetStatus` must — and now does — branch on the same
                // predicate for TODAY, or the two disagree on day one: this
                // note stated the guarantee as a fact while the snapshot writer
                // still asked `isRestDay`, so the widget answered "Rest day"
                // to the person Today was telling to train (review 06.09.2026).
                // `isRestDay` keeps the marked weekdays for the settings rows,
                // the calendar grid and nextTrainingDate, which ask a different
                // question.
                RestView(activeWorkout: $activeWorkout,
                         destination: $destination,
                         freshStartConfirmShown: $freshStartConfirmShown,
                         startOverConfirmShown: $startOverConfirmShown)
            } else {
                PlanView(activeWorkout: $activeWorkout,
                         destination: $destination,
                         freshStartConfirmShown: $freshStartConfirmShown,
                         startOverConfirmShown: $startOverConfirmShown,
                         pendingSuspect: $pendingSuspect)
            }
        }
        .padding(.horizontal, 24)
        // The settings gear floats over the top-trailing corner.
        .saveFailureBanner(store, trailingClearance: 44)
        .fullScreenCover(item: $activeWorkout) { active in
            WorkoutFlowView(session: active.session, resume: active.resume,
                            settleImmediately: active.settleImmediately, store: store)
        }
        .sheet(item: $destination) { destination in
            switch destination {
            case .technique(let ex):
                // `planned: true` — these six movements are the workout about to be
                // done, so the sheet carries the step below each of them. It is the
                // handle that used to stand under this very row (R30).
                TechniqueSheet(target: ex, planned: true)
            case .nextWorkout:
                NextWorkoutSheet()
            case .history(let record):
                // Today's own record, from the screen that is about today. It was
                // drawn, complete, and reachable only through the Calendar tab and an
                // unmarked black circle — while both prominent controls of both
                // screens answered "what is next" and neither answered "what did I
                // just do" (UX review 05.09.2026).
                HistorySheet(record: record)
            }
        }
        .alert(String(localized: "Start from scratch?"),
               isPresented: $freshStartConfirmShown) {
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
            Button(String(localized: "Keep my progress"), role: .cancel) { }
            Button(String(localized: "Reset progress"), role: .destructive) {
                store.resetProgress()
            }
        } message: {
            Text("Every movement goes back to the beginning. Your history stays.")
        }
        // The plan reached a pair of eyes — the engine is told. Keyed on the
        // showing, so a scroll, a rotation or a Dynamic Type change is the
        // same showing and costs nothing, while a plan that changed under the
        // reader (a budget moved in Settings, an "I was sick" tap, a finished
        // workout) is the new showing it is.
        .task(id: planShowing) {
            guard let showing = planShowing else { return }
            store.recordPlanShown(showing.session)
        }
    }

    /// What makes a showing a showing: the plan on screen.
    ///
    /// The budget it was drawn under used to be part of the identity, because
    /// a budget could move WITHOUT moving the plan and still lift the repair's
    /// cap for one transition. Nothing on this screen writes `cut` any more,
    /// and what does — the skip inside the workout — lands with the rating,
    /// which regenerates the session anyway. `nil` on the two days the plan is
    /// not on screen at all.
    private var planShowing: PlanShowing? {
        guard !store.doneToday, !store.restAppliesToday else { return nil }
        return PlanShowing(session: store.nextSession)
    }

    private struct PlanShowing: Equatable {
        let session: Session
    }
}
