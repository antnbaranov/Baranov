//
//  ContactPickerRepresentable.swift
//  Baranov
//
//  Presents the system's own `CNContactPickerViewController` — the exact
//  native "choose from all your contacts" screen Messages and Mail use,
//  full name-and-photo browsing included. Presenting the SYSTEM picker
//  like this needs no Contacts permission at all: Apple runs it in a
//  separate process and only ever hands this app the one contact
//  actually tapped, never the address book itself. That makes it the
//  reliable fallback for "choose a contact" even when
//  `ContactSuggestionService`'s live typeahead has no Contacts access to
//  draw suggestions from.
//
//  This is presented IMPERATIVELY via plain UIKit (`present`/`dismiss`
//  on an invisible anchor `UIViewController`), never through a SwiftUI
//  `.sheet`. `ContactSuggestionField` (this view's only caller) lives
//  inside `ComposeLetterView`, which is itself the content of
//  `JourneyView`'s own always-on, never-dismissed docked `.sheet`. A
//  second SwiftUI `.sheet` presented from content that's already inside
//  another `.sheet`'s hierarchy is exactly the "two presentations
//  competing for the same slot" problem already documented — and fixed
//  the same way, with a plain overlay instead of a second SwiftUI
//  presentation — for the Look Around cover in `JourneyView`: SwiftUI/
//  UIKit can't cleanly run two presentations from the same hierarchy at
//  once, and it's the *outer* one (this app's always-on docked panel)
//  that loses that fight and gets silently dismissed. Because
//  `JourneyView` treats the docked panel closing as "the sender must
//  have meant to go to Pasture" (see `isDockedPanelPresented`), that
//  silent dismissal is exactly what made picking a contact look like it
//  randomly kicked the sender to Pasture. Presenting the picker as a
//  plain UIKit modal from an anchor `UIViewController` sidesteps
//  SwiftUI's own sheet machinery entirely — UIKit itself has no trouble
//  presenting one real modal on top of another.
//

@preconcurrency import Contacts
@preconcurrency import ContactsUI
import SwiftUI
import UIKit

struct ContactPickerRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (CNContact) -> Void
    var onCancel: () -> Void = {}

    /// Every `CNContact` property this app reads once a contact is picked
    /// — `CNContactFormatter`'s own required-keys descriptor (needed
    /// internally just to safely produce a full display name, name
    /// prefix/suffix/nickname/phonetic spellings included) plus the
    /// organization name, postal addresses, and thumbnail image this app
    /// actually displays afterward.
    fileprivate static let requiredContactKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    /// A plain, otherwise-invisible view controller that exists only to
    /// host `present`/`dismiss` calls — it never shows any content of its
    /// own. The SwiftUI side embeds this at zero size (see
    /// `ContactSuggestionField`'s `.background(...)` call site).
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Present (and dismiss) from the app's actual topmost presented
        // view controller — walked explicitly from the key window's root
        // — rather than calling `present`/`dismiss` on this anchor
        // directly and trusting UIKit to walk `uiViewController.parent`
        // up to the right place on its own. This anchor sits zero-sized,
        // several SwiftUI view layers deep, inside content that's itself
        // the always-on docked `.sheet`; if that implicit parent chain
        // is ever a beat behind (SwiftUI re-hosts representables across
        // view updates), `present` resolves to the wrong host and it's
        // the *outer* docked sheet that visibly gets dismissed instead —
        // exactly what read as "picking a contact kicks me to Pasture."
        // Resolving the real topmost controller from the window itself
        // removes that ambiguity entirely.
        guard let topMost = Self.topMostViewController() else { return }

        if isPresented {
            // Already presenting (e.g. a redundant state update while the
            // picker is on screen) — don't double-present. The real bug
            // this used to miss: once the picker itself IS topmost (it has
            // nothing presented on top of IT), `topMost.presentedViewController
            // == nil` is true again, so the old guard let every unrelated
            // SwiftUI re-render (typing a message, any state change
            // elsewhere in the compose form) call `present` a second,
            // third, fourth... time, stacking a fresh picker on top of the
            // one already on screen. Checking whether `topMost` itself
            // already IS the picker closes that hole.
            guard topMost.presentedViewController == nil, !(topMost is CNContactPickerViewController) else { return }
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            topMost.present(picker, animated: true)
        } else if topMost is CNContactPickerViewController {
            topMost.dismiss(animated: true)
        } else if topMost.presentedViewController is CNContactPickerViewController {
            topMost.dismiss(animated: true)
        }
    }

    /// Walks from the key window's root view controller down through
    /// `presentedViewController` to whatever is actually on screen right
    /// now — the correct place to present one more modal on top of, no
    /// matter how many `.sheet`s are already stacked (the docked panel
    /// included).
    @MainActor
    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? scenes.first?.windows.first

        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick, onCancel: onCancel)
    }

    /// `@MainActor`-isolated (all its work — reading the binding, calling
    /// back into SwiftUI state — needs to happen there), with its
    /// `CNContactPickerDelegate` conformance methods left `nonisolated`
    /// and hopping over via `Task { @MainActor in ... }`, the same
    /// pattern `LocationService`'s `CLLocationManagerDelegate`
    /// conformance already uses in this project: `CNContactPickerDelegate`
    /// itself isn't `@MainActor`-annotated, but UIKit always calls these
    /// delegate methods on the main thread in practice.
    @MainActor
    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let isPresented: Binding<Bool>
        private let onPick: (CNContact) -> Void
        private let onCancel: () -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.isPresented = isPresented
            self.onPick = onPick
            self.onCancel = onCancel
        }

        nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            Task { @MainActor in
                // The contact the system picker hands back here only
                // carries an undocumented, minimal set of fetched
                // properties — accessing anything this app reads
                // afterward (a postal address, the thumbnail, even a
                // formatted full name) can throw an uncaught
                // `CNPropertyNotFetchedException` (an Objective-C
                // exception, not a catchable Swift error) and crash
                // outright the moment a contact is selected.
                //
                // Re-fetching by the contact's own identifier, with the
                // exact keys this app needs, stays safe *without*
                // Contacts permission: a contact identifier that came
                // back from the system's own picker is treated as
                // already authorized for that one contact, regardless of
                // this app's own Contacts access state — the same
                // guarantee that lets this picker be presented with no
                // permission prompt at all.
                let store = CNContactStore()
                let resolved: CNContact
                if let fullContact = try? store.unifiedContact(
                    withIdentifier: contact.identifier,
                    keysToFetch: ContactPickerRepresentable.requiredContactKeys
                ) {
                    resolved = fullContact
                } else {
                    resolved = contact
                }
                isPresented.wrappedValue = false
                onPick(resolved)
            }
        }

        nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            Task { @MainActor in
                isPresented.wrappedValue = false
                onCancel()
            }
        }
    }
}
