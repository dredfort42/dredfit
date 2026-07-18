//
//  OnboardingView.swift
//  Dredfit
//
//  First-run explainer (v1.4). Three cards, typography instead of
//  illustrations. The thermostat idea is the one thing a new user cannot
//  infer from the UI — without it a trained person sees 3×8 knee push-ups
//  and leaves before the regulator has had a chance to converge.
//

import SwiftUI

struct OnboardingView: View {
    /// Called on both "Start" and "Skip" — reaching the end and opting out
    /// are equally "seen".
    let onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            skipRow
            TabView(selection: $page) {
                card1.tag(0)
                card2.tag(1)
                card3.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            dots
            // "Continue", not "Next": TodayView already owns the key "Next"
            // for the *next workout* card, and one key cannot carry two
            // meanings across languages.
            PrimaryButton(title: page == pageCount - 1
                          ? String(localized: "Start")
                          : String(localized: "Continue")) {
                if page == pageCount - 1 {
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
                }
            }
            // Today sits behind the cover with its own "Start" button, so the
            // pager's primary control needs an identifier of its own.
            .accessibilityIdentifier("onboarding-primary")
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color.white)
    }

    // MARK: - Chrome

    private var skipRow: some View {
        HStack {
            Spacer()
            Button(String(localized: "Skip"), action: onFinish)
                .dredfitFont(15)
                .foregroundStyle(Theme.ink3)
                .accessibilityIdentifier("onboarding-skip")
                .accessibilityHint(Text("Skips the introduction"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(i == page ? Theme.accent : Theme.hairline)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 26)
        .accessibilityHidden(true)
    }

    // MARK: - Cards

    private func cardShell<Content: View>(title: String,
                                          body text: String,
                                          @ViewBuilder extra: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(title)
                .dredfitFont(32, weight: .heavy)
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .dredfitFont(16.5)
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)
            extra()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var card1: some View {
        cardShell(title: String(localized: "Training at home. No questionnaires."),
                  body: String(localized: """
                  No questions about your goal, your level or how much time you have. \
                  Open the app and train — the first workout is already waiting. \
                  About 33 minutes, no equipment.
                  """)) { EmptyView() }
    }

    private var card2: some View {
        cardShell(title: String(localized: "It adjusts like a thermostat."),
                  body: String(localized: """
                  Dredfit gives you a plan, you say how it went, and the next plan \
                  shifts. The first workout is deliberately easy — it is the starting \
                  point. Answer honestly afterwards and within two or three workouts \
                  the load becomes yours.
                  """)) {
            loopDiagram.padding(.top, 28)
        }
    }

    private var card3: some View {
        cardShell(title: String(localized: "One tap after the workout."),
                  body: String(localized: """
                  “Less · On plan · More” — that is enough. If you want to be exact, \
                  open the list and put in what you actually did.
                  """)) {
            careBlock.padding(.top, 28)
        }
    }

    // MARK: - Card 2 visual: plan → actual → plan

    private var loopDiagram: some View {
        HStack(spacing: 8) {
            chip(String(localized: "plan"), filled: false)
            arrow
            chip(String(localized: "actual"), filled: true)
            arrow
            chip(String(localized: "plan"), filled: false)
        }
        // One element for VoiceOver — three chips and two arrows read as noise.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Plan, then your actual result, then the next plan"))
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .dredfitFont(13, weight: .semibold)
            .foregroundStyle(filled ? Theme.accent : Theme.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(filled ? Theme.accentSoft : Theme.cardBG,
                        in: Capsule())
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .dredfitFont(11, weight: .semibold)
            .foregroundStyle(Theme.ink3)
    }

    // MARK: - Card 3: the quiet duty-of-care note

    private var careBlock: some View {
        Text(String(localized: """
        All your data stays on your device. If you have problems with your joints, \
        heart or blood pressure, talk to a doctor first. Sharp pain during an \
        exercise always means stop.
        """))
        .dredfitFont(12.5)
        .foregroundStyle(Theme.ink3)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}
