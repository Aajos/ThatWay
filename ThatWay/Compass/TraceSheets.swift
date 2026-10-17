//
//  TraceSheets.swift
//  ThatWay
//
//  The two conversations of a trace. The rule for both: the important information comes BEFORE the choices (mandatory), and
//  while someone is making choices it is only a tap away under an ⓘ (optional). Nobody is bombarded while deciding.
//
//    TraceRequestSheet   the TRACER asks for a length of time. Whether it is once or ongoing is the traced person's decision.
//    GrantConsentSheet   the TRACED person: first the full safety information (I understand / Cancel), then a short screen
//                        with the kind, a slider and an unticked box, a second confirmation, and the owner check.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

/// A small ⓘ that shows or hides the detail under it.
struct InfoToggle<Detail: View>: View {
    let theme: AppTheme
    let label: String
    @ViewBuilder var detail: () -> Detail
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                Image(systemName: open ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 20)).foregroundStyle(theme.accent).frame(minWidth: 44, minHeight: 32, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(open ? .isSelected : [])
            if open { detail().transition(.opacity) }
        }
    }
}

// MARK: - Asking

struct TraceRequestSheet: View {
    let friend: Friend
    let theme: AppTheme
    let send: (Double) -> Void
    let cancel: () -> Void

    @State private var hours: Double = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Trace \(friend.username)").font(.nunito(24, .black)).foregroundStyle(theme.ink)
                Text(TraceCopy.requestIntro(name: friend.username)).font(.nunito(14, .semibold)).foregroundStyle(theme.ink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ASK FOR UP TO").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(TraceWindow.presets, id: \.self) { value in
                            Button { hours = value } label: {
                                Text(TraceWindow.label(hours: value)).font(.nunito(13, .extraBold))
                                    .foregroundStyle(hours == value ? theme.onAccent : theme.ink)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(Capsule().fill(hours == value ? theme.accent : theme.ink.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(hours == value ? .isSelected : [])
                        }
                    }
                }

                InfoToggle(theme: theme, label: "What to expect") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(friend.username) decides the length (never more than you ask) and whether it is a one-off or ongoing.")
                            .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                        ForEach(TraceCopy.requestDisclosure, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(theme.accent).padding(.top, 6)
                                Text(line).font(.nunito(12, .semibold)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Button { send(hours) } label: {
                    Text("Ask \(friend.username)").font(.nunito(15, .black)).foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                }
                .buttonStyle(.plain)
                Button("Not now", action: cancel).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Answering

struct GrantConsentSheet: View {
    @ObservedObject var trace: TraceManager
    @ObservedObject var owner: OwnerAuthCoordinator
    let email: EmailVerifying
    let request: IncomingTrace
    let theme: AppTheme
    let close: () -> Void

    @State private var understood = false
    @State private var hours: Double
    @State private var choice: GrantKindChoice = .once
    @State private var ticked = false
    @State private var confirming = false
    @State private var working = false

    init(trace: TraceManager, owner: OwnerAuthCoordinator, email: EmailVerifying, request: IncomingTrace, theme: AppTheme, close: @escaping () -> Void) {
        self.trace = trace; self.owner = owner; self.email = email; self.request = request; self.theme = theme; self.close = close
        _hours = State(initialValue: min(TraceWindow.clamp(request.requestedHours), 1))     // starts SHORT: the person lengthens it on purpose
    }

    private var name: String { request.friend.username }
    private var maxHours: Double { min(TraceWindow.maxHours, max(TraceWindow.minHours, request.requestedHours)) }
    private var endsAt: Date { Date().addingTimeInterval(hours * 3600) }
    private var endText: String {
        endsAt.formatted(date: .omitted, time: .shortened) + (Calendar.current.isDateInToday(endsAt) ? "" : " tomorrow")
    }

    var body: some View {
        Group { if understood { choices } else { safety } }
            .background(theme.screen.ignoresSafeArea())
            .presentationDetents([.large])
            .alert("Allow \(name) to trace you for \(TraceWindow.label(hours: hours))?", isPresented: $confirming) {
                Button("Cancel", role: .cancel) {}
                Button("Allow") { allow() }
            } message: {
                Text("They will be able to see where you are until \(endText). You’ll be asked to confirm it’s you.")
            }
            // The owner check can need its own screen (an app passcode); it sits on top of this one.
            .sheet(item: Binding(get: { owner.prompt }, set: { _ in })) { prompt in
                OwnerPromptSheet(owner: owner, prompt: prompt, email: email, theme: theme)
            }
    }

    // MARK: Step 1: everything, before any choice (mandatory)

    private var safety: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(name) wants to trace you").font(.nunito(24, .black)).foregroundStyle(theme.ink)
                    Text("Before you decide, please read this. It is about your safety.").font(.nunito(14, .extraBold)).foregroundStyle(theme.ink)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ConsentCopy.points, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(theme.accent).padding(.top, 6)
                                Text(ConsentCopy.fill(point, name: name)).font(.nunito(13, .semibold)).foregroundStyle(theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
                }
                .padding(24)
            }
            VStack(spacing: 10) {
                Button { understood = true } label: {
                    Text("I understand").font(.nunito(15, .black)).foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                }
                .buttonStyle(.plain)
                Button("Cancel", action: close).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary).frame(minHeight: 36)
            }
            .padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 8)
        }
    }

    // MARK: Step 2: the choices (short; detail under ⓘ)

    private var choices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Let \(name) see where you are?").font(.nunito(24, .black)).foregroundStyle(theme.ink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("HOW").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                    Picker("How", selection: $choice) { ForEach(GrantKindChoice.allCases) { Text($0.allowTitle).tag($0) } }
                        .pickerStyle(.segmented)
                    InfoToggle(theme: theme, label: "What these mean") {
                        Text(TraceCopy.kindExplanation(choice, name: name)).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("FOR").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                    Text("\(TraceWindow.label(hours: hours)), until \(endText)").font(.nunito(18, .black)).foregroundStyle(theme.ink)
                    if maxHours > TraceWindow.minHours {
                        Slider(value: $hours, in: TraceWindow.minHours...maxHours, step: TraceWindow.sliderStepHours)
                            .tint(theme.accent)
                            .accessibilityLabel("How long to allow").accessibilityValue(TraceWindow.label(hours: hours))
                    }
                    InfoToggle(theme: theme, label: "More about this") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(name) asked for up to \(TraceWindow.label(hours: request.requestedHours)). You can allow less, and stop it any time from the banner or the You tab.")
                            Text("It ends at the time shown even if you forget.")
                        }
                        .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                    }
                }

                Button { ticked.toggle() } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: ticked ? "checkmark.square.fill" : "square").font(.system(size: 22)).foregroundStyle(ticked ? theme.accent : theme.ink.opacity(0.5))
                        Text(ConsentCopy.fill(ConsentCopy.tick, name: name, time: endText)).font(.nunito(13, .extraBold)).foregroundStyle(theme.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ticked ? .isSelected : [])

                if let message = trace.errorMessage { Text(message).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed) }

                Button { confirming = true } label: {
                    let ready = ticked && !working
                    Text(working ? "Checking…" : (ticked ? "Allow for \(TraceWindow.label(hours: hours))" : "Tick the box to allow"))
                        .font(.nunito(15, .black)).foregroundStyle(ready ? theme.onAccent : theme.ink.opacity(0.55))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(ready ? theme.accent : theme.ink.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .disabled(!ticked || working)

                Button { Task { await trace.decline(request); close() } } label: {
                    Text("No, decline").font(.nunito(15, .extraBold)).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(working)
                Button("Decide later", action: close).font(.nunito(13, .extraBold)).foregroundStyle(theme.textSecondary).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private func allow() {
        working = true
        Task {
            let outcome = await trace.grant(request, hours: hours, kind: choice == .once ? .oneoff : .window)
            working = false
            if outcome == .granted { close() }
        }
    }
}
