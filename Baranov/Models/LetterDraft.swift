//
//  LetterDraft.swift
//  Baranov
//
//  A letter that was written but couldn't leave yet. The one case this
//  exists for: the sender carried "Slide to Dispatch" all the way across
//  with every field filled in, and the pasture had no free ram for it.
//  Rather than losing a finished letter behind a paywall, the whole form
//  is kept here and put back exactly as it was the next time Compose
//  opens — including straight after "Expand the Pasture" is dismissed.
//
//  Plain text on purpose: a draft has not been sealed yet (sealing and
//  encryption happen in `Letter.write` at the moment of dispatch), so
//  this is the sender's own unsent note on their own device, the same as
//  the text sitting in the field before they slid. Nothing here ever
//  travels.
//

import CoreLocation
import Foundation

struct LetterDraft: Codable, Equatable, Sendable {
    /// How the sender had closed the letter when it was set aside —
    /// mirrors Compose's own private closure state so the envelope comes
    /// back sealed (or open) the way they left it.
    enum Closure: String, Codable, Sendable {
        case sealed
        case postcard
    }

    var targetCity: String
    var targetLatitude: Double?
    var targetLongitude: Double?
    var ramName: String
    var usesCustomRamName: Bool
    var recipientName: String
    var messageBody: String
    var sealColor: SealColor
    var closure: Closure?
    /// `true` when the draft exists because "Slide to Dispatch" was
    /// completed with no ram free (the case that shows the "Saved to
    /// Drafts" notice), `false` for a quiet autosave of a form in
    /// progress.
    var wasSetAsideAtDispatch: Bool
    var savedAt: Date

    var targetCoordinate: CLLocationCoordinate2D? {
        guard let targetLatitude, let targetLongitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: targetLatitude, longitude: targetLongitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    /// Whether there is anything worth restoring at all — an empty form
    /// is never saved as a draft.
    var hasContent: Bool {
        !targetCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
