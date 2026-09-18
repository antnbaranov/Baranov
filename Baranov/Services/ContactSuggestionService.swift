//
//  ContactSuggestionService.swift
//  Baranov
//
//  Live "who is this going to?" suggestions from the device's Contacts,
//  mirroring `PlaceSearchCompleter`'s pattern: results refresh as the
//  query text changes, and picking one just fills in a display name —
//  nothing about the contact itself is ever attached to the letter or
//  sent anywhere.
//
//  Contacts access is requested lazily, the first time this field is
//  actually focused, never at app launch. Denial, restriction, or any
//  fetch failure simply leaves `results` empty: the recipient field
//  always still works as a plain text field either way, so a permission
//  refusal can never block sending a letter — offline-first resilience
//  extends to "no-contacts-access-first" too.
//
//  `CNContactStore`'s fetch/enumerate calls are synchronous and can block
//  for a noticeable moment — especially with `CNContactThumbnailImageDataKey`
//  in the fetch keys — so every actual Contacts-store lookup here runs
//  inside a detached background task, never on the main actor. Typing
//  also debounces (a short delay before a lookup actually fires, and any
//  still-in-flight lookup is cancelled the moment newer text arrives), so
//  a fast typist never queues up a pile of overlapping fetches. Without
//  both of those, a burst of keystrokes could each block the main thread
//  in turn long enough to trip iOS's watchdog and have the app killed —
//  which would look, from the sender's side, exactly like the whole app
//  suddenly relaunching back to the Pasture tab mid-letter.
//

@preconcurrency import Contacts
import Foundation
import Observation

@Observable
@MainActor
final class ContactSuggestionService {
    private(set) var results: [CNContact] = []
    private(set) var isAuthorized = false

    private let store = CNContactStore()

    /// How long to wait after the last keystroke before actually hitting
    /// the Contacts store — short enough to still feel live, long enough
    /// that normal typing only ever fires one real lookup.
    private static let debounceDelay: Duration = .milliseconds(220)

    /// The in-flight (possibly still debouncing) lookup, if any. Cancelled
    /// and replaced every time a newer query comes in, so a slow, stale
    /// fetch can never land after a faster, newer one and clobber what's
    /// on screen.
    private var fetchTask: Task<Void, Never>?

    /// The in-progress recipient text. An empty fragment surfaces a short
    /// "interesting" starter list instead of an empty dropdown, exactly
    /// like Apple Maps suggests nearby places before you've typed
    /// anything.
    func updateQuery(_ fragment: String) {
        scheduleFetch(matching: fragment, debounced: true)
    }

    func clearResults() {
        fetchTask?.cancel()
        fetchTask = nil
        results = []
    }

    /// Requests Contacts access if it hasn't been decided yet, and loads
    /// an initial suggestion list on success. Safe to call every time the
    /// field gains focus — a already-decided authorization state just
    /// re-fetches (or does nothing, if previously denied).
    func requestAccessIfNeeded() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            isAuthorized = true
            scheduleFetch(matching: "", debounced: false)
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.isAuthorized = granted
                    if granted {
                        self?.scheduleFetch(matching: "", debounced: false)
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    // MARK: - Fetching

    private func scheduleFetch(matching fragment: String, debounced: Bool) {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: Self.debounceDelay)
                guard !Task.isCancelled else { return }
            }
            await self?.performFetch(matching: fragment)
        }
    }

    private func performFetch(matching fragment: String) async {
        guard isAuthorized, !Task.isCancelled else { return }

        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStarterList = trimmed.isEmpty
        // Apple Maps shows a short "nearby" starter list before you've
        // typed anything, then opens up to full search results once you
        // start typing — mirrored here as just 3 starter contacts vs. up
        // to 8 once there's an actual search fragment to match against.
        let limit = isStarterList ? 3 : 8

        let store = store
        let fetched = await Task.detached(priority: .userInitiated) {
            await Self.fetchContacts(store: store, trimmedName: trimmed, isStarterList: isStarterList, limit: limit)
        }.value

        guard !Task.isCancelled else { return }
        results = fetched
    }

    /// The actual blocking Contacts-store work, kept fully off the main
    /// actor: this runs inside a detached task, never touches any of this
    /// class's `@MainActor`-isolated state directly, and only its plain
    /// `[CNContact]` return value crosses back over.
    private static func fetchContacts(
        store: CNContactStore,
        trimmedName trimmed: String,
        isStarterList: Bool,
        limit: Int
    ) -> [CNContact] {
        // `CNContactFormatter.descriptorForRequiredKeys(for:)` is
        // Apple's own way of guaranteeing every key `CNContactFormatter`
        // might touch internally — name prefix/suffix, nickname, phonetic
        // spellings, and so on, not just given/family name — is actually
        // fetched. Without it, `suggestedDisplayName` below can throw an
        // uncaught `CNPropertyNotFetchedException` (an Objective-C
        // exception, not a catchable Swift error) the moment it's asked
        // to format a contact that happens to need one of those keys.
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]

        var matches: [CNContact] = []
        do {
            if isStarterList {
                let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                request.sortOrder = .givenName
                var count = 0
                try store.enumerateContacts(with: request) { contact, stop in
                    matches.append(contact)
                    count += 1
                    if count >= limit {
                        stop.pointee = true
                    }
                }
            } else {
                let predicate = CNContact.predicateForContacts(matchingName: trimmed)
                matches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            }
        } catch {
            matches = []
        }

        return Array(matches.prefix(limit))
    }
}

extension CNContact {
    /// A safe display name for suggestion rows — falls back to the
    /// organization name for a contact with no person name set, and
    /// never returns an empty string a tap could select into a blank
    /// recipient field.
    var suggestedDisplayName: String {
        let formatted = CNContactFormatter.string(from: self, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let formatted, !formatted.isEmpty {
            return formatted
        }
        let organization = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return organization.isEmpty ? "Unknown Contact" : organization
    }

    /// This contact's postal addresses as flat, single-line display
    /// strings — real delivery points, not just a city name. Each one
    /// keeps the label's own `identifier` so `ForEach` can diff them
    /// without needing `CNLabeledValue` itself to be `Identifiable`.
    var formattedPostalAddresses: [(id: String, text: String)] {
        postalAddresses.map { labeled in
            let multiline = CNPostalAddressFormatter.string(from: labeled.value, style: .mailingAddress)
            let singleLine = multiline
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return (id: labeled.identifier, text: singleLine)
        }
    }
}
