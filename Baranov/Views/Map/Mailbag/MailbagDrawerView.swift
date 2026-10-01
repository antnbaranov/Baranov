//
//  MailbagDrawerView.swift
//  Baranov
//
//  The mailbag: the first page of the docked panel on the main map, in the
//  spirit of Find My's floating drawer. Everything that is in transit —
//  letters coming to you, letters you sent, and the archive — lives here,
//  and nowhere else (Pasture is only the shepherd's screen, Profile is only
//  your identity).
//
//  - Collapsed: the most urgent courier on one line (a letter at the gate
//    first, else the closest walker) with a badge and progress, plus the
//    "break the seal" button once it has arrived.
//  - Expanded: Incoming / Outgoing / Archive as a native inset list, one row
//    per courier with its route and progress. Tapping a row opens the ram's
//    bag; writing a letter is the other page of the panel, receiving one is
//    the code field below — so the list carries no buttons for either.
//
//  The panel's detents and sheet chrome belong to `JourneyView`; this view
//  only fills the page and reports what the person tapped.
//

import SwiftUI
import UniformTypeIdentifiers

/// Where the mailbag's own navigation can go. Pushed inside the sheet, so
/// a ram's letters are followed without a second sheet opening over it.
enum MailbagRoute: Hashable {
    /// A ram's bag: progress, route and every letter aboard.
    case bag(UUID)
    /// The ram's letter itself, including the wax-seal ritual at the gate.
    case letter(UUID)
    /// The person's own ram at rest: an empty bag with a way to fill it.
    case idleBag
}

struct MailbagDrawerView: View {
    @Environment(FlockViewModel.self) private var flockViewModel

    let isCollapsed: Bool
    /// The shortest sheet: one line for the most urgent courier, no picker.
    let isCompact: Bool
    /// The very smallest: the same single courier row, nothing else.
    var isTiny = false
    /// The pushed screens (see `MailbagRoute`), owned by `JourneyView`.
    @Binding var path: [MailbagRoute]
    /// Starts the shake handoff from inside an opened letter.
    var onShakeHandoff: (() -> Void)? = nil
    /// Letters sent by Shepherd ID or ear tag, held until the recipient's gate is known.
    private var heldLetters: [LetterTracker.Record] { LetterTracker.shared.heldRecords }
    /// Name of the person's own ram, shown while nothing is out.
    let idleName: String
    let onExpand: () -> Void
    /// Sends the person to the compose page (the CTA in the resting ram's bag).
    var onWriteLetter: (() -> Void)? = nil
    /// Folds the sheet back down, like the close button on the letter page.
    var onClose: () -> Void = {}
    let onCancelJourney: (Ram) -> Void

    @AppStorage("com.baranov.carrierDisplayName") private var carrierName = ""
    /// The file picker for a letter that came by AirDrop or Files.
    @State private var isImportingFile = false
    /// Letters the person was told are coming (a shared link), until the
    /// ram itself lands here.
    private let expectedStore = ExpectedLetterStore.shared

    private var expectedLetters: [ExpectedLetter] {
        let arrived = Set(flockViewModel.activeRams.flatMap { ram in
            [ram.letter?.id].compactMap { $0 } + ram.passengerLetters.map(\.id)
        })
        return expectedStore.pending(excluding: arrived)
    }
    /// Owned by `JourneyView`, whose bottom strip changes with the tab:
    /// the code field under Incoming, search under Archive.
    @Binding var section: MailbagSection
    @Binding var searchText: String

    // MARK: - Data

    private func isOutgoing(_ ram: Ram) -> Bool {
        guard let sender = ram.letter?.senderName else { return false }
        // Compose stamps "A Shepherd" when no name was ever saved, so an
        // empty name must match that too — otherwise the person's own
        // letters would show up under Incoming.
        let mine = carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = mine.isEmpty ? String(localized: "A Shepherd", bundle: .appLanguage, locale: .appLanguage) : mine
        return sender.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(effective) == .orderedSame
    }

    /// A sent letter that has reached the recipient's gate is finished as
    /// far as the sender is concerned: it belongs in the archive.
    private func isFinished(_ ram: Ram) -> Bool {
        ram.status == .delivered || ram.wasDeliveredInPerson
            || (ram.status == .arrivedAtGate && isOutgoing(ram))
    }

    /// Everything that still has somewhere to go. A letter this person
    /// sent and handed on stays under Outgoing — that's where "Take it
    /// back" lives — while someone else's handed-on letter is gone.
    private var inTransit: [Ram] {
        flockViewModel.activeRams.filter {
            $0.letter != nil && ($0.status != .handedOff || isOutgoing($0)) && !isFinished($0)
        }
    }

    /// What this phone is actually walking or waiting on.
    private var carriedHere: [Ram] {
        inTransit.filter { $0.status != .handedOff }
    }

    private var rams: [Ram] {
        let source: [Ram]
        switch section {
        case .incoming: source = inTransit.filter { !isOutgoing($0) }
        case .outgoing: source = inTransit.filter { isOutgoing($0) }
        case .archive:
            source = flockViewModel.activeRams.filter { $0.letter != nil && isFinished($0) }
        }
        let query = activeQuery
        let matching = query.isEmpty ? source : source.filter { ram in
            let haystack = [ram.name, ram.currentCity, ram.targetCity,
                            ram.routeHistory.first?.cityName ?? "",
                            ram.letter?.senderName ?? "", ram.letter?.recipientName ?? ""]
            return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        // A letter waiting at the gate is always first.
        return matching.sorted { lhs, rhs in
            (lhs.status == .arrivedAtGate ? 0 : 1) < (rhs.status == .arrivedAtGate ? 0 : 1)
        }
    }

    /// Search lives under Archive only; Incoming and Outgoing are never filtered.
    private var showsSearch: Bool { section == .archive }

    private var activeQuery: String {
        showsSearch ? searchText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// The most urgent courier: a letter at my gate, else the closest walker, else anything in transit.
    private var featured: Ram? {
        carriedHere.first { $0.status == .arrivedAtGate && !isOutgoing($0) }
            ?? carriedHere.filter { $0.status == .walking }.min { $0.remainingSteps < $1.remainingSteps }
            ?? carriedHere.first
    }

    /// Whatever is out on the road, in any tab: the featured courier, or a
    /// ram without a letter record. "Ready for a letter" is only true when
    /// this is nil.
    private var onTheRoad: Ram? {
        featured ?? flockViewModel.activeRams.first {
            $0.status != .delivered && $0.status != .handedOff && $0.status != .grazing
        }
    }

    // MARK: - Body

    /// The picker sits above both forms of the drawer, so the same three
    /// choices are one tap away at the smallest detent too — and switching
    /// tabs never moves the sheet.
    var body: some View {
        // The stack's own bar stays hidden on the list itself (the page has
        // no title of its own); pushed screens bring their native bar with
        // a back button.
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if isCompact || isTiny {
                    compactContent
                } else {
                    if !isCollapsed { mailbagHeader }
                    sectionPicker
                    if isCollapsed {
                        collapsedContent
                    } else {
                        expandedContent
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MailbagRoute.self) { route in
                Group {
                switch route {
                case .bag(let id):
                    RamBagView(ramId: id, onShakeHandoff: onShakeHandoff, isEmbedded: true)
                case .idleBag:
                    IdleRamBagView(name: idleName, onWriteLetter: { onWriteLetter?() })
                case .letter(let id):
                    if let ram = flockViewModel.activeRams.first(where: { $0.id == id }) {
                        LetterDetailView(ram: ram, onShakeHandoff: onShakeHandoff, isEmbedded: true)
                    } else {
                        ContentUnavailableView("This ram is no longer in the pasture", systemImage: "bag")
                    }
                }
                }
                // Let the sheet's own glass show through pushed screens.
                .containerBackground(.clear, for: .navigation)
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.baranovPackage, .data]) { result in
            if case .success(let url) = result {
                NotificationCenter.default.post(name: .importTransitFile, object: url)
            }
        }
    }

    /// Adds a `.ram` file (AirDropped, or saved to Files) to the mailbag.
    private var importFileButton: some View {
        Button { isImportingFile = true } label: {
            Label("Import a file", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
        .accessibilityHint("Adds a letter file you received by AirDrop")
    }

    /// Opens a ram's bag right here in the sheet, growing it if needed.
    private func openBag(_ ram: Ram) {
        onExpand()
        path.append(.bag(ram.id))
    }

    /// Opens the bag of the person's own resting ram.
    private func openIdleBag() {
        onExpand()
        path.append(.idleBag)
    }

    /// The resting ram as a tappable row: its bag is empty, but it is still a bag.
    private var idleBarButton: some View {
        Button { openIdleBag() } label: {
            MailbagIdleBar(name: idleName)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the bag")
    }

    /// Opens the ram's letter right here in the sheet.
    private func openLetter(_ ram: Ram) {
        onExpand()
        path.append(.letter(ram.id))
    }

    /// The shortest sheet: just the most urgent courier, one row.
    private var compactContent: some View {
        VStack(spacing: 10) {
            Text("Mailbag")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let ram = collapsedRam ?? onTheRoad {
                Button { openLetter(ram) } label: {
                    MailbagRamRow(ram: ram, isOutgoing: isOutgoing(ram), isSlim: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the letter")
            } else {
                idleBarButton
            }
        }
        .padding(.horizontal, 16)
        // Clear of the grabber: the title used to sit right under it.
        .padding(.top, 18)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Title shown once the sheet is open large, matching the composer's
    /// header on the neighbouring page (grabber clearance included).
    private var mailbagHeader: some View {
        ZStack {
            Text("Mailbag")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                GlassCloseButton(label: "Close", action: onClose)
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .padding(.top, 14)
    }

    private var sectionPicker: some View {
        Picker("Mailbag", selection: $section) {
            ForEach(MailbagSection.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        // Middle sheet: the picker sits a little lower, clear of the grabber,
        // and the ram row hugs it so it stays above the code field.
        .padding(.top, isCollapsed ? 16 : 4)
        .padding(.bottom, isCollapsed ? 0 : 10)
        .sensoryFeedback(.selection, trigger: section)
    }

    // MARK: Collapsed

    /// One row for whichever tab is selected: its most urgent courier, or a
    /// quiet line when there is none.
    private var collapsedContent: some View {
        VStack {
            if let ram = collapsedRam {
                MailbagCollapsedBar(
                    ram: ram,
                    canBreakSeal: !isOutgoing(ram),
                    onExpand: { openLetter(ram) },
                    onBreakSeal: { openLetter(ram) }
                )
            } else if section == .incoming, let expected = expectedLetters.first {
                ExpectedLetterRow(letter: expected)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if section == .outgoing, onTheRoad == nil {
                // Only Outgoing has a resting ram to show as the row
                // itself; Incoming has the code field below, Archive has
                // its search — both still get the plain "nothing yet"
                // line below so this height never reads as empty.
                idleBarButton
            } else {
                // A plain "nothing yet" line rather than leaving this
                // whole middle height looking like just the segmented
                // picker with nothing under it — previously shown on iPad
                // only, but an empty Incoming/Archive tab reads exactly as
                // broken on iPhone too.
                Text(emptyLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var emptyLine: LocalizedStringKey {
        switch section {
        case .incoming: "No letters on the road to you"
        case .outgoing: "Nothing on the road"
        case .archive: "Nothing here yet"
        }
    }

    /// The featured courier within the selected tab.
    private var collapsedRam: Ram? {
        if section == .incoming, let featured, !isOutgoing(featured) {
            return featured
        }
        return rams.first
    }

    // MARK: Expanded

    private var expandedContent: some View {
        let showsPublished = section == .outgoing && !heldLetters.isEmpty
        let showsExpected = section == .incoming && !expectedLetters.isEmpty
        let isSearching = !activeQuery.isEmpty
        return Group {
            if rams.isEmpty, !showsPublished, !showsExpected, !isSearching {
                // An empty tab still shows the ram below the note: the
                // courier out on the road, or the one at rest.
                ScrollView {
                  VStack(spacing: 12) {
                    emptyState
                    if section == .incoming {
                        importFileButton
                            .padding(.horizontal, 16)
                    }
                    // Only the courier that belongs to this tab; never
                    // an outgoing ram under Incoming or vice versa.
                    if section == .outgoing, onTheRoad == nil {
                        idleBarButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                  }
                  // Clear of the code field / dots strip along the bottom.
                  .padding(.bottom, 56)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                List {
                    // The letters as a deck: swipe through, tap to open.
                    if !rams.isEmpty {
                        Section {
                            MailbagSwipeDeck(
                                rams: rams,
                                isOutgoing: { isOutgoing($0) },
                                carrierName: carrierName,
                                onOpen: { openLetter($0) },
                                onOpenBag: { openBag($0) },
                                onCancel: { onCancelJourney($0) }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }

                    // Search is offered under Archive only.
                    Section {
                        if showsSearch {
                            NativeFieldRow(symbol: "magnifyingglass") {
                                TextField("Search Letters", text: $searchText)
                                    .submitLabel(.search)
                                if isSearching {
                                    Button { searchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, -8)
                                    .accessibilityLabel("Clear")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        if rams.isEmpty, isSearching {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }

                    if section == .incoming {
                        Section {
                            importFileButton
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    }

                    if showsExpected {
                        Section("On the way to you") {
                            ForEach(expectedLetters) { letter in
                                ExpectedLetterRow(letter: letter)
                                    .swipeActions {
                                        // A letter the post office is following
                                        // arrives on its own; only a link-only
                                        // card can be put away.
                                        if !letter.isTracked {
                                            Button(role: .destructive) {
                                                expectedStore.remove(letterID: letter.letterID)
                                            } label: {
                                                Label("Remove", systemImage: "trash")
                                            }
                                        }
                                    }
                            }
                        }
                    }

                    if showsPublished {
                        Section("Waiting for their gate") {
                            ForEach(heldLetters) { record in
                                MailbagHeldRow(record: record)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            LetterTracker.shared.cancelHeld(record.letterID)
                                        } label: {
                                            Label("Take it back", systemImage: "arrow.uturn.backward")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                // Clear of the page dots along the bottom (they sit low on
                // small phones and overlapped the last rows).
                .contentMargins(.bottom, 32, for: .scrollContent)
            }
        }
        .animation(.snappy, value: section)
    }

    @ViewBuilder private var emptyState: some View {
        switch section {
        case .incoming:
            ContentUnavailableView("No letters on the road to you", systemImage: "tray",
                                   description: Text("When a friend sends one, it will wait here. Got an ear tag from them? Type it below."))
        case .outgoing:
            ContentUnavailableView("Nothing on the road", systemImage: "paperplane",
                                   description: Text("Swipe to New Letter and a ram sets off with it."))
        case .archive:
            if activeQuery.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "archivebox",
                                       description: Text("Letters you have read rest here."))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

extension Notification.Name {
    /// A `.ram` file the person picked in the mailbag; `object` is its URL.
    static let importTransitFile = Notification.Name("com.baranov.importTransitFile")
}
