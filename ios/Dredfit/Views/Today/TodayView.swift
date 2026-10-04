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
                // weekday would meet "come back on Tuesday" as its very first
                // screen. `WidgetBridge`'s `widgetStatus` branches on the same
                // predicate for TODAY, or the widget would answer "Rest day"
                // to the person Today is telling to train. `isRestDay` keeps
                // the marked weekdays for the calendar grid, the reminders and
                // every day after today, which ask a different question.
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
                // done, so the sheet carries the step below each of them.
                TechniqueSheet(target: ex, planned: true)
            case .nextWorkout:
                NextWorkoutSheet()
            case .history(let record):
                // Today's own record, from the screen that is about today: the
                // done state's other prominent control answers "what is next",
                // and this one answers "what did I just do".
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
            // An alert also keeps its cancel action, which a popover suppresses
            // because tapping outside IS the cancel: measured on iPhone 17
            // Pro / iOS 26.5, the node is `Alert` with no `Popover` beside it,
            // and the `.cancel` button stands in the accessibility tree. So
            // the escape is one button, carrying the role AND the name that
            // says what it does. "Cancel" answers "cancel what?"; this one
            // does not.
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
        // reader (a handle pulled, a comeback accepted, a finished workout) is
        // the new showing it is.
        .task(id: planShowing) {
            guard let showing = planShowing else { return }
            store.recordPlanShown(showing.session)
        }
    }

    /// What makes a showing a showing: the plan on screen, and nothing else.
    /// Whatever this screen does to `cut` it does as part of a new position —
    /// an easier variation, a comeback — which changes the plan, and the skip
    /// inside the workout lands its cut with the rating, which regenerates
    /// the session anyway. `nil` on the two days the plan is not on screen at
    /// all.
    private var planShowing: PlanShowing? {
        guard !store.doneToday, !store.restAppliesToday else { return nil }
        return PlanShowing(session: store.nextSession)
    }

    private struct PlanShowing: Equatable {
        let session: Session
    }
}
