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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // A fact about rest, not a warning: the movement is in today's
            // plan at the level it was, and it stays there for a while.
            if !store.restingPatterns.isEmpty {
                Text("Resting for now: \(restingNames)")
                    .dredfitFont(13.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("resting-line")
            }

            if store.shouldOfferComeback() {
                ComebackCard(offersFreshStart: store.offersFreshStart(),
                             onAccept: { store.acceptComeback() },
                             onDecline: { store.declineComeback() },
                             onFreshStart: { freshStartConfirmShown = true })
                    .padding(.top, 10)
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

    /// Movement names rather than exercise names: the rest belongs to the
    /// pattern, and it outlives the variation on screen today.
    private var restingNames: String {
        ListFormatter.localizedString(byJoining: store.restingPatterns.map(\.displayName))
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
                        .foregroundStyle(.white)
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
        case .more: return String(localized: "Rating: easy — progressing twice as fast")
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
