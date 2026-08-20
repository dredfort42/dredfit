//
//  TodayView.swift
//  Dredfit
//
//  Three states: plan + Start, rest day, or completed with a preview of the
//  next workout under its honest date.
//

import SwiftUI
import DredfitCore

/// The session is snapshotted at tap time, not read live inside the cover
/// closure: completeWorkout advances the engine before the cover dismisses,
/// and a live read would flip the rating screen to the NEXT session's data.
private struct ActiveWorkout: Identifiable {
    let session: Session
    var resume: WorkoutSnapshot?
    /// nil is the full session. Resolved at tap time like the session itself.
    var shortPlan: Set<Pattern>?
    var id: Int { session.sessionNumber }
}

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeWorkout: ActiveWorkout?
    @State private var techniqueFor: SessionExercise?
    @State private var nextPreviewShown = false
    @State private var freshStartConfirmShown = false
    @State private var howItWorksShown = false

    var body: some View {
        Group {
            if store.doneToday {
                doneView
            } else if store.isRestDay(store.today) {
                // Must agree with the widget and nextTrainingDate.
                restView
            } else {
                planView
            }
        }
        .padding(.horizontal, 24)
        .fullScreenCover(item: $activeWorkout) { active in
            WorkoutFlowView(session: active.session, resume: active.resume,
                            shortPlan: active.shortPlan)
        }
        .sheet(item: $techniqueFor) { ex in
            TechniqueSheet(exercise: ex)
        }
        .sheet(isPresented: $nextPreviewShown) {
            NextWorkoutSheet()
        }
        .sheet(isPresented: $howItWorksShown) {
            HowItWorksView()
        }
        .confirmationDialog(String(localized: "Start from scratch?"),
                            isPresented: $freshStartConfirmShown,
                            titleVisibility: .visible) {
            Button(String(localized: "Reset levels"), role: .destructive) {
                store.resetProgress()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Levels go back to the beginning. Your history stays.")
        }
    }

    // MARK: - Plan state

    private var planView: some View {
        let session = store.nextSession
        let debuts = store.debutPatterns
        // Derived from the session this view already holds: store.nextSession
        // generates a fresh one on every access, and store.restingPatterns
        // generates another inside itself.
        let resting = restingRows(in: session)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    .capitalized)
                Text("Workout \(session.sessionNumber)")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("≈ \(Int(session.estimatedTotalMin.rounded())) min · \(session.exercises.count) exercises")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                    // A quiet way into the existing explainer for everyone who
                    // skipped onboarding and can't interpret "+1 step".
                    Button {
                        howItWorksShown = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .dredfitFont(13)
                            Text("Why this plan?")
                                .dredfitFont(13, weight: .medium)
                                .underline(color: Theme.ink3)
                        }
                        .foregroundStyle(Theme.ink2)
                    }
                    .accessibilityIdentifier("why-this-plan")
                }
            }
            .padding(.top, 18)

            List(session.exercises) { ex in
                Button {
                    techniqueFor = ex
                } label: {
                    ExerciseRow(exercise: ex,
                                badge: debuts.contains(ex.pattern)
                                    ? String(localized: "new variation") : nil)
                }
                .listRowSeparatorTint(Theme.hairline)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // A fact about the plan, not a warning: the movement is in today's
            // workout at the level it was, and it stays at that level for a
            // known number of its own appearances.
            if !resting.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not getting harder")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .accessibilityIdentifier("resting-line")
                    ForEach(resting) { row in
                        restingRow(row)
                    }
                    // The trend the freeze alone cannot say (#100): the same
                    // movement hurting appearance after appearance. Derived
                    // from the journal on every render — the first clean
                    // appearance takes the line down with it.
                    if let trend = painTrendLine(rows: resting) {
                        Text(trend)
                            .dredfitFont(12.5)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                            .accessibilityIdentifier("pain-trend-line")
                    }
                }
                .padding(.top, 6)
            }

            // v2.24 (spec §35.3): the one-off line about the 45-minute default.
            // Existing installs had "no limit" whether they chose it or not, so
            // the change gets one sentence, once. No notification, no repeat.
            if store.shouldShowBudgetDefaultNotice {
                HStack(alignment: .top, spacing: 12) {
                    Text("Workouts now fit into 45 minutes by default — you can change that in Settings.")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Got it") { store.markBudgetDefaultNoticeSeen() }
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("budget-notice-dismiss")
                }
                .padding(.top, 6)
                .accessibilityIdentifier("budget-default-notice")
            }

            // An offer of rest, not a warning (#98) — and never a number to
            // beat: the count appears only here, in the suggestion to break
            // the run. "Train anyway" and the Start button stay untouched.
            if store.todayWouldExtendALongRun {
                Text("A workout today would be training day \(store.wouldBeConsecutiveDay) in a row — a rest day lets the load settle.")
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("long-run-line")
            }

            if store.shouldOfferComeback() {
                ComebackCard(offersFreshStart: store.offersFreshStart(),
                             preview: store.comebackPreview(),
                             onAccept: { store.acceptComeback() },
                             onDecline: { store.declineComeback() },
                             onFreshStart: { freshStartConfirmShown = true },
                             // Spec §22.4: the comeback lands first, the lens
                             // goes on top of the landing.
                             onSick: { store.acceptComeback(); store.markIllness() })
                    .padding(.top, 10)
            }

            // v2.12 (#133): the window the engine cannot see — a short gap
            // below the comeback. One quiet tap, no questionnaire.
            // One quiet offer at a time: the weak-link question is the more
            // specific of the two, so it takes precedence over the illness tap.
            if store.shouldOfferIllnessTap() && !store.shouldAskAboutSuspect() {
                Button { store.markIllness() } label: {
                    Text("Been sick? Take two gentler weeks")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("illness-offer")
                .padding(.top, 6)
            }

            // v2.15 (#135): the journal keeps finding the same movement under
            // an unnamed "tough". One contextual question — never a
            // questionnaire — routing into the pain path that already exists.
            if store.shouldAskAboutSuspect(), let suspect = store.unnamedLessSuspect() {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tough sessions keep landing on \(suspect.displayName).")
                        .dredfitFont(13.5)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Button("It hurts") { store.confirmSuspectHurts(suspect) }
                            .accessibilityIdentifier("weak-link-hurts")
                        // v2.22 (spec §33): the third answer — "just hard" —
                        // armed a hold, and the hold is cancelled. The case it
                        // served is exactly what the sub-step fixes without
                        // asking anyone anything.
                        Button("It's fine") { store.dismissSuspectPrompt() }
                            .accessibilityIdentifier("weak-link-fine")
                    }
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .accessibilityIdentifier("weak-link-prompt")
            }

            // While the lens runs, say so — a plan that quietly got easier
            // reads as a glitch without the reason on screen.
            if store.illnessSessionsLeft > 0 {
                Text("Recovery: \(store.illnessSessionsLeft) gentler workouts left")
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)
                    .accessibilityIdentifier("illness-lens-line")
            }

            // The card replaces Start — its own two actions already are
            // "continue" and "start over".
            if let snap = store.resumableWorkout() {
                resumeCard(snap)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            } else {
                PrimaryButton(title: String(localized: "Start")) {
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                }
                    .padding(.top, 10)

                // Secondary by design: the full workout stays the default
                // every day, and the choice is never remembered.
                if let plan = ShortWorkout.plan(session: session,
                                                counter: store.engineState.counter,
                                                levels: store.engineState.levels) {
                    Button {
                        activeWorkout = ActiveWorkout(session: store.nextSession,
                                                      shortPlan: plan)
                    } label: {
                        Text("Short on time? Short version · ≈ \(ShortWorkout.estimatedMin(session: session, plan: plan)) min")
                            .dredfitFont(15, weight: .medium)
                            .foregroundStyle(Theme.ink2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("start-short")
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0).frame(height: 14)   // breathing room above the tab bar
        }
    }

    private struct RestingRow: Identifiable {
        let id: Pattern
        let name: String
        let remaining: Int
    }

    /// Named the way the list above names them: the freeze belongs to the
    /// movement, but the row the reader is looking at says "Y-T-W raises".
    /// A frozen movement cannot change variation, so the name holds for as
    /// long as the block is up. The horizon is per movement, not a constant:
    /// a fresh report refreshes that one counter while the others keep
    /// counting down.
    private func restingRows(in session: Session) -> [RestingRow] {
        let resting = Set(store.restingPatterns(in: session))
        return session.exercises
            .filter { resting.contains($0.pattern) }
            .map { RestingRow(id: $0.pattern, name: $0.name,
                              remaining: store.engineState.freezeRemaining($0.pattern)) }
    }

    /// One sentence, not one per row: the first resting movement whose last
    /// appearances all ended in a pain report. The wording escalates at
    /// three — a repeat report means it hurt, rested, and hurt again.
    private func painTrendLine(rows: [RestingRow]) -> String? {
        for row in rows {
            let streak = store.discomfortStreak(row.id)
            guard streak >= AppStore.painTrendThreshold else { continue }
            return streak >= AppStore.painSpecialistThreshold
                ? String(localized: "\(row.name) keeps hurting, appearance after appearance. Pain that stays is a reason to see a specialist.")
                : String(localized: "\(row.name) has hurt both of its recent appearances — a smaller number takes the load down.")
        }
        return nil
    }

    /// The pill rides inline after the name and wraps with it, the same way
    /// the debut badge does in ExerciseRow — a sibling HStack would push it
    /// off screen on the longest catalog names.
    private func restingRow(_ row: RestingRow) -> some View {
        let horizon = String(localized: "\(row.remaining) more times")
        var text = Text(row.name)
        if let pill = BadgePill.image(text: horizon, scale: displayScale,
                                      typeSize: dynamicTypeSize) {
            text = text + Text(verbatim: " ")
                + Text(Image(uiImage: pill)).baselineOffset(-3)
        }
        return text
            .dredfitFont(13.5)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            // One phrase for VoiceOver: name, state, horizon — the pill is an
            // image and would otherwise be read as nothing at all.
            .accessibilityLabel(Text("\(row.name), not getting harder — \(horizon)"))
    }

    // MARK: - Interrupted workout

    private func resumeCard(_ snap: WorkoutSnapshot) -> some View {
        // The card must count in the list the person was walking through.
        let total = snap.shortPlan?.count ?? store.nextSession.exercises.count
        let position = min(snap.exIndex + 1, total)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Continue the workout?")
                .dredfitFont(20, weight: .heavy)
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)

            Group {
                if snap.atFeedback == true {
                    // Say that, not a misleading exercise position.
                    Text("The workout is done — only the rating is left.")
                } else {
                    Text("You stopped at exercise \(position) of \(total) — everything done so far is still in place.")
                }
            }
            .dredfitFont(14.5)
            .foregroundStyle(Theme.ink2)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            HStack(spacing: 10) {
                Button {
                    activeWorkout = ActiveWorkout(session: store.nextSession,
                                                  resume: snap,
                                                  shortPlan: snap.shortPlan.map(Set.init))
                } label: {
                    Text(String(localized: "resume.continue", defaultValue: "Continue"))
                        .dredfitFont(15.5, weight: .semibold)
                        .foregroundStyle(Theme.bg)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("resume-continue")

                Button {
                    store.clearWorkoutSnapshot()
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                } label: {
                    Text("Start over")
                        .dredfitFont(15.5, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.hairline, lineWidth: 1.5))
                }
                .accessibilityIdentifier("resume-restart")
            }
            .padding(.top, 16)
        }
        .padding(18)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Rest day

    /// Rest is a plan, not a lockout: training anyway stays available.
    private var restView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: store.today.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    .capitalized)
                Text("Rest day")
                    .dredfitFont(32, weight: .heavy)
                    .tracking(-0.5)
                Text("Next workout \(store.nextTrainingDateLabel)")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, 18)

            // ink2, not ink3: this sentence is the rest day's whole argument.
            Text("Recovery is part of the plan — the load only sticks if you let it settle.")
                .dredfitFont(15.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Spacer()

            // A "train anyway" session interrupted mid-way comes back here
            // too — the rest day must not eat it.
            if let snap = store.resumableWorkout() {
                resumeCard(snap)
                    .padding(.bottom, 14)
            } else {
                Button {
                    activeWorkout = ActiveWorkout(session: store.nextSession)
                } label: {
                    Text("Train anyway")
                        .dredfitFont(17, weight: .medium)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Theme.hairline, lineWidth: 1.5))
                }
                .accessibilityIdentifier("train-anyway")
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Completed state

    private var doneView: some View {
        VStack(spacing: 0) {
            HStack {
                Kicker(text: store.today.formatted(.dateTime.weekday(.wide).day().month(.wide))
                    .capitalized)
                Spacer()
            }
            .padding(.top, 18)

            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.cardBG)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .dredfitFont(44, weight: .bold, cap: 66)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
            }

            Text("Workout \(store.lastRecord?.sessionNumber ?? 0) completed")
                .dredfitFont(24, weight: .heavy)
                .tracking(-0.4)
                .padding(.top, 24)

            Text(resultCaption)
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 6)

            Spacer()

            Button {
                nextPreviewShown = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker(text: String(localized: "Next"))
                        Text("Workout \(store.nextSession.sessionNumber) · \(store.nextTrainingDateLabel)")
                            .dredfitFont(16.5, weight: .semibold)
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .dredfitFont(14, weight: .semibold)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.bottom, 24)
        }
    }

    private var resultCaption: String {
        switch store.lastRecord?.result {
        case .less: return String(localized: "Rating: tough — the next one will be easier")
        case .plan: return String(localized: "Rating: on plan — the next asks a little more")
        case .more: return String(localized: "Rating: easy — progressing as fast as each movement allows")
        case nil:   return ""
        }
    }
}

// MARK: - Exercise row (shared with NextWorkoutSheet)

struct ExerciseRow: View {
    let exercise: SessionExercise
    /// The pill rides INLINE at the end of the name and wraps with it as a
    /// unit: the longest catalog name is wider than the content column by
    /// itself, so a sibling HStack pill would push the load off screen. Not
    /// an ellipsis either — sibling variations differ at the END of the name.
    var badge: String?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            nameWithBadge
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(shortLoad)
                .dredfitFont(15.5)
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
            Image(systemName: "chevron.right")
                .dredfitFont(12, weight: .semibold)
                .foregroundStyle(Theme.ink3.opacity(0.7))
        }
        .padding(.vertical, 4)
    }

    /// Text concatenation is the only SwiftUI flow that lets the pill follow
    /// the last word and wrap with it, so it travels as an inline image.
    private var nameWithBadge: some View {
        var name = Text(exercise.name)
        if let badge,
           let pill = BadgePill.image(text: badge, scale: displayScale,
                                      typeSize: dynamicTypeSize) {
            name = name + Text(verbatim: " ")
                + Text(Image(uiImage: pill)).baselineOffset(-4)
        }
        return name
            .dredfitFont(16.5, weight: .medium)
            .foregroundStyle(Theme.ink)
            .accessibilityLabel(badge.map { Text(verbatim: "\(exercise.name), \($0)") }
                ?? Text(verbatim: exercise.name))
    }

    private var shortLoad: String {
        let side = exercise.perSide ? String(localized: " /side") : ""
        // v2.22 (spec §33): an uneven plan spells its sets out — "9-8-8". This
        // is where the sub-step becomes visible: a third of the sessions used
        // to read as "nothing changed", and the row is what says otherwise.
        // Explicit keys, not the bare "%@%@" a plain interpolation would mint.
        if let loads = exercise.loads {
            let spelled = loads.map(String.init).joined(separator: "-")
            switch exercise.unit {
            case .reps: return String(localized: "plan.perSet",
                                      defaultValue: "\(spelled)\(side)")
            case .hold: return String(localized: "plan.perSetHold",
                                      defaultValue: "\(spelled) s\(side)")
            }
        }
        switch exercise.unit {
        case .reps: return String(localized: "\(exercise.sets) × \(exercise.load)\(side)")
        case .hold: return String(localized: "\(exercise.sets) × \(exercise.load) s\(side)")
        }
    }
}

/// Cached per text, display scale and Dynamic Type size. accentText on
/// accentSoft — accent itself is 2.91:1 on that fill.
@MainActor
private enum BadgePill {
    private static var cache: [String: UIImage] = [:]

    static func image(text: String, scale: CGFloat,
                      typeSize: DynamicTypeSize) -> UIImage? {
        let key = "\(text)|\(scale)|\(typeSize)"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content:
            Text(text)
                .dredfitFont(11, weight: .semibold)
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.accentSoft, in: Capsule())
                .environment(\.dynamicTypeSize, typeSize)
        )
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }
}
