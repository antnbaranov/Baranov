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
    /// Letters this person published by code (waiting to be claimed, or claimed).
    let publishedLetters: [PublishedLetter]
    /// Name of the person's own ram, shown while nothing is out.
    let idleName: String
    let onExpand: () -> Void
    /// Sends the person to the compose page (the CTA in the resting ram's bag).
    var onWriteLetter: (() -> Void)? = nil
    /// Folds the sheet back down, like the close button on the letter page.
    var onClose: () -> Void = {}
    let onCancelJourney: (Ram) -> Void

    @AppStorage("com.baranov.carrierDisplayName") private var carrierName = ""
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
        let effective = mine.isEmpty ? "A Shepherd" : mine
        return sender.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(effective) == .orderedSame
    }

    /// Everything that still has somewhere to go.
    private var inTransit: [Ram] {
        flockViewModel.activeRams.filter {
            $0.letter != nil && $0.status != .delivered && $0.status != .handedOff
        }
    }

    private var rams: [Ram] {
        let source: [Ram]
        switch section {
        case .incoming: source = inTransit.filter { !isOutgoing($0) }
        case .outgoing: source = inTransit.filter { isOutgoing($0) }
        case .archive:
            source = flockViewModel.activeRams.filter { $0.letter != nil && $0.status == .delivered }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// The most urgent courier: a letter at my gate, else the closest walker, else anything in transit.
    private var featured: Ram? {
        inTransit.first { $0.status == .arrivedAtGate && !isOutgoing($0) }
            ?? inTransit.filter { $0.status == .walking }.min { $0.remainingSteps < $1.remainingSteps }
            ?? inTransit.first
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
        }
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
            if let ram = collapsedRam {
                Button { openLetter(ram) } label: {
                    MailbagRamRow(ram: ram, isOutgoing: isOutgoing(ram))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
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
            } else if section == .outgoing {
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
        let showsPublished = section == .outgoing && !publishedLetters.isEmpty
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Group {
            if rams.isEmpty, !showsPublished, !isSearching {
                // An empty tab still shows the ram below the note: the
                // courier out on the road, or the one at rest.
                ScrollView {
                  VStack(spacing: 12) {
                    emptyState
                    Group {
                        if let ram = featured {
                            MailbagRamRow(ram: ram, isOutgoing: isOutgoing(ram), isSlim: true)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            idleBarButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
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
                                onOpen: { openLetter($0) }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }

                    // Below it: every letter in the tab, with search.
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search Letters", text: $searchText)
                                .submitLabel(.search)
                            if isSearching {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear")
                            }
                        }
                        if rams.isEmpty, isSearching {
                            ContentUnavailableView.search(text: searchText)
                        }
                        ForEach(rams) { ram in
                            MailbagCourierRow(
                                ram: ram,
                                isOutgoing: isOutgoing(ram),
                                carrierName: carrierName,
                                onOpenBag: { openBag(ram) },
                                onOpenLetter: { openLetter(ram) },
                                onCancel: { onCancelJourney(ram) }
                            )
                        }
                    }

                    if showsPublished {
                        Section("Sent by Ear Tag") {
                            ForEach(publishedLetters.prefix(5)) { MailbagPublishedRow(published: $0) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
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
            if searchText.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "archivebox",
                                       description: Text("Letters you have read rest here."))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
