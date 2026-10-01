//
//  HoofbeatOverlayWindow.swift
//  Baranov
//
//  Hosts the hoofbeat HUD and the incoming handover request in their own
//  transparent window above the app's window — the same approach as
//  `ReelOverlayWindow`. Handing over is usually started from Profile, which
//  is a sheet: attached to the root view, the HUD sat underneath it, so the
//  sender never saw "Waiting…" and the receiver never saw the request.
//  Touches that miss the HUD or the card fall through to the app below.
//

import SwiftUI
import UIKit

/// Where the HUD and the request card currently are, in window
/// coordinates. The overlay window uses it to decide which touches it owns.
@MainActor
final class HoofbeatHitRegion {
    var frame: CGRect = .zero
}

@MainActor
final class HoofbeatOverlayWindow {
    static let shared = HoofbeatOverlayWindow()

    private var window: UIWindow?

    /// Safe to call more than once; installs the window the first time a
    /// scene is available.
    func install(
        relay: HoofbeatRelay,
        nearby: NearbyCourierService,
        onRetry: @escaping @MainActor () -> Void,
        onConfirm: @escaping @MainActor () -> Void = {},
        onAccept: @escaping @MainActor (HandoverRequest) -> Void,
        directionHint: @escaping @MainActor (HandoverRequest) -> Bool? = { _ in nil },
        onSuggestion: @escaping @MainActor (CourierSuggestion) -> Void = { _ in }
    ) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }

        let region = HoofbeatHitRegion()
        let overlay = HoofbeatPassThroughWindow(windowScene: scene)
        overlay.region = region
        overlay.windowLevel = UIWindow.Level.normal + 2
        overlay.backgroundColor = .clear

        let host = UIHostingController(rootView: HoofbeatOverlayRoot(
            relay: relay,
            nearby: nearby,
            onRetry: onRetry,
            onConfirm: onConfirm,
            onAccept: onAccept,
            directionHint: directionHint,
            onSuggestion: onSuggestion,
            region: region
        ))
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.isHidden = false
        window = overlay
    }
}

/// Owns only the touches that land on the HUD or the request card; every
/// other touch reaches the window underneath. This checks the content's
/// real frame instead of asking whether the hosting view was hit: on iOS 18
/// the hosting view is the hit view for SwiftUI buttons too, so the old
/// "hit the root view means pass through" rule swallowed taps on Accept and
/// Not now and sent them to the sheet below.
private final class HoofbeatPassThroughWindow: UIWindow {
    var region: HoofbeatHitRegion?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let frame = region?.frame, !frame.isEmpty,
              frame.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
        return super.hitTest(point, with: event) ?? rootViewController?.view
    }
}

private struct HoofbeatOverlayRoot: View {
    let relay: HoofbeatRelay
    let nearby: NearbyCourierService
    let onRetry: @MainActor () -> Void
    let onConfirm: @MainActor () -> Void
    let onAccept: @MainActor (HandoverRequest) -> Void
    let directionHint: @MainActor (HandoverRequest) -> Bool?
    let onSuggestion: @MainActor (CourierSuggestion) -> Void
    let region: HoofbeatHitRegion

    @AppStorage(AppLanguagePickerView.storageKey) private var languageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    /// A request stays answerable while this phone is idle or only waiting
    /// for a shake; it is hidden only once a transfer is really under way.
    private var isTransferRunning: Bool {
        switch relay.phase {
        case .connecting, .exchanging: true
        case .idle, .searching, .finished, .failed: false
        }
    }

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if let request = nearby.incomingRequest, !isTransferRunning {
                        HandoverRequestCard(
                            request: request,
                            goingMyWay: directionHint(request),
                            onAccept: { onAccept(request) },
                            onDecline: { nearby.dismissIncomingRequest() }
                        )
                    }

                    if let suggestion = nearby.suggestion, nearby.incomingRequest == nil, !relay.phase.isActive {
                        CourierSuggestionCard(
                            suggestion: suggestion,
                            onAccept: {
                                nearby.dismissSuggestion()
                                onSuggestion(suggestion)
                            },
                            onDismiss: { nearby.dismissSuggestion() }
                        )
                    }

                    if nearby.isAskingForAccess {
                        NearbyDiscoveryPrompt(
                            onTurnOn: { nearby.grantAccess() },
                            onNotNow: { nearby.declineAccess() }
                        )
                    }

                    HoofbeatOverlay(
                        phase: relay.phase,
                        successTick: relay.successTick,
                        partnerName: relay.partnerName,
                        awaitingAcceptance: relay.isAwaitingAcceptance,
                        answeringRequest: relay.isByRequest && !relay.isAwaitingAcceptance,
                        onDismiss: { relay.reset() },
                        onRetry: { onRetry() },
                        onConfirm: { onConfirm() },
                        isConfirmed: relay.isManuallyConfirmed,
                        failure: relay.failure,
                        onOpenSettings: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                }
                .padding(.top, 4)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    region.frame = frame
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: nearby.incomingRequest)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: nearby.suggestion)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: nearby.isAskingForAccess)
            }
            .environment(\.locale, Locale(identifier: languageCode))
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}
