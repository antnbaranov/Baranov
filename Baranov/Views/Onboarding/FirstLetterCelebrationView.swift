//
//  FirstLetterCelebrationView.swift
//  Baranov
//
//  The moment right after the very first letter is dispatched — the one
//  point where the app has just kept its promise and the person feels it.
//  It does two things, in order:
//
//    1. Pays it off: the ram is running, a success haptic lands, and the
//       person is shown, truthfully, what happens next (a real alert
//       preview, an honest walking estimate) so they can picture the
//       recipient's face.
//    2. Only then mentions the limit they just felt — one ram carries one
//       letter at a time — and offers "Expand the Pasture" once, with a
//       plain "Maybe Later". No countdown, no fake scarcity, and it never
//       comes back: the flag that gates it is set when it first appears.
//

import SwiftUI

struct FirstLetterMoment: Identifiable, Sendable {
    let id = UUID()
    let recipient: String
    let ramName: String
    let targetCity: String
    let meters: Int
}

extension Notification.Name {
    /// Posted by the compose sheet each time a letter is dispatched;
    /// `RootView` decides whether it's the first.
    static let firstLetterDispatched = Notification.Name("com.baranov.firstLetterDispatched")
    /// A tracked letter just left; `userInfo["message"]` is the tracking
    /// message for the recipient. `RootView` offers the share sheet.
    static let letterReadyToShare = Notification.Name("com.baranov.letterReadyToShare")
}

struct FirstLetterCelebrationView: View {
    let moment: FirstLetterMoment
    /// False when the person already has more than one slot.
    let canUpsell: Bool
    let onExpand: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(MissedPerson.storageKey) private var missedRaw = ""
    @State private var successTick = 0
    @State private var appeared = false

    /// Steps walked per day the estimate assumes; 1 step = 1 metre.
    private static let assumedStepsPerDay = 8_000

    private var missedPerson: MissedPerson? { MissedPerson(rawValue: missedRaw) }

    private var recipient: String { moment.recipient.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Anna", or "Grandma" from onboarding, or a neutral fallback.
    private var who: String {
        if !recipient.isEmpty { return recipient }
        return missedPerson?.label ?? String(localized: "them", bundle: .appLanguage, locale: .appLanguage)
    }

    private var gateOwner: String {
        if !recipient.isEmpty { return String(localized: "\(recipient)'s", bundle: .appLanguage, locale: .appLanguage) }
        return missedPerson?.possessive ?? String(localized: "their", bundle: .appLanguage, locale: .appLanguage)
    }

    private var distanceText: String {
        Measurement(value: Double(moment.meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(.appLanguage))
    }

    private var days: Int {
        max(1, Int((Double(moment.meters) / Double(Self.assumedStepsPerDay)).rounded(.up)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RamSpriteLoopView(frameNames: RamSpriteFrameSets.gallopRunningStride, frameDuration: .milliseconds(60))
                    .frame(height: 120)
                    .padding(.top, 28)

                VStack(spacing: 10) {
                    Text("It's on its way.")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("A letter is walking \(distanceText) to \(who). Nobody else sent that today.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What happens next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    NotificationPreviewCard(
                        title: String(localized: "\(moment.ramName) is at \(gateOwner) gate", bundle: .appLanguage, locale: .appLanguage),
                        message: String(localized: "The seal is waiting. Share the ear tag and let them break it.", bundle: .appLanguage, locale: .appLanguage),
                        time: String(localized: "in about \(days) days", bundle: .appLanguage, locale: .appLanguage),
                        fill: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                    )

                    Text("An estimate at \(Self.assumedStepsPerDay.formatted(.number.locale(.appLanguage))) steps a day. Every step you take moves \(moment.ramName) one metre closer.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                if canUpsell {
                    upsell
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.wax)
                        .controlSize(.large)
                        .buttonBorderShape(.roundedRectangle(radius: 16))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.success, trigger: successTick)
        .task {
            successTick += 1
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.15)) {
                appeared = true
            }
        }
    }

    private var upsell: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("One ram, one letter at a time", systemImage: "square.stack.3d.up.fill")
                .font(.headline)

            Text("\(moment.ramName) is busy now. Expand the Pasture and up to \(FlockViewModel.pastureCapacity) rams can walk at once — one for each person you keep meaning to write to.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onExpand()
                dismiss()
            } label: {
                Text("Expand the Pasture")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 16))

            Button("Maybe later") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text("Your first ram stays free, always.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    FirstLetterCelebrationView(
        moment: FirstLetterMoment(recipient: "", ramName: "Klaus", targetCity: "Lisbon", meters: 42_000),
        canUpsell: true,
        onExpand: {}
    )
}
