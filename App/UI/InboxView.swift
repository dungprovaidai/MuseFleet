import SwiftUI

private enum InboxPeriod: String, CaseIterable {
    case anytime = "Any time", day = "Last 24 hours", week = "Last 7 days", month = "Last 30 days"

    var start: Date? {
        switch self {
        case .anytime: nil
        case .day: Date().addingTimeInterval(-86_400)
        case .week: Date().addingTimeInterval(-7 * 86_400)
        case .month: Date().addingTimeInterval(-30 * 86_400)
        }
    }
}

@MainActor
struct InboxView: View {
    @Environment(FleetStore.self) private var store
    @Environment(BrowserPool.self) private var pool
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(NavigationState.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var accountID: UUID?
    @State private var kind: EventKind?
    @State private var period = InboxPeriod.anytime
    @State private var groupByAccount = false
    @State private var showingFilters = false
    @State private var detail: FleetEvent?
    @State private var pendingEvent: FleetEvent?

    private var hasFilters: Bool { accountID != nil || kind != nil || period != .anytime || groupByAccount }

    private var events: [FleetEvent] {
        let cutoff = period.start
        return store.events.filter { event in
            let matchesScope: Bool
            switch navigation.inboxScope {
            case .all: matchesScope = true
            case .unread: matchesScope = !event.isRead
            case .attention: matchesScope = !event.isRead && event.type.needsAttention
            }
            let searchable = [event.accountName, event.type.title, event.source.title,
                              store.settings.hideNotificationPreviews ? "" : (event.preview ?? "")].joined(separator: " ")
            return matchesScope && (accountID == nil || event.accountID == accountID) &&
                (kind == nil || event.type == kind) && (cutoff.map { event.timestamp >= $0 } ?? true) &&
                (search.isEmpty || searchable.localizedStandardContains(search))
        }.sorted { $0.timestamp > $1.timestamp }
    }

    private var accountGroups: [(id: UUID, events: [FleetEvent])] {
        Dictionary(grouping: events, by: \.accountID)
            .map { (id: $0.key, events: $0.value) }
            .sorted {
                let first = $0.events.first?.timestamp ?? .distantPast
                let second = $1.events.first?.timestamp ?? .distantPast
                return first == second ? $0.id.uuidString < $1.id.uuidString : first > second
            }
    }

    var body: some View {
        @Bindable var navigation = navigation

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if typeSize.isAccessibilitySize {
                        Picker("Activity", selection: $navigation.inboxScope) {
                            ForEach(InboxScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.menu)
                    } else {
                        Picker("Activity", selection: $navigation.inboxScope) {
                            ForEach(InboxScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    Button("Filters", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
                        showingFilters = true
                    }
                    .labelStyle(.iconOnly).font(.title2).frame(minWidth: 44, minHeight: 44)
                    .accessibilityValue(hasFilters ? "Active filters" : "No filters")
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                if events.isEmpty {
                    ScrollView {
                        EmptyFleetView(symbol: store.events.isEmpty ? "tray" : "checkmark.circle",
                                       title: store.events.isEmpty ? "A little quiet here" : "You’re all caught up",
                                       message: store.events.isEmpty
                                       ? "Supported events will appear here with the account they belong to. Check Settings for current detection limits."
                                       : "There are no events matching this view.",
                                       actionTitle: store.events.isEmpty ? "View detection status" : "Show all activity") {
                            if store.events.isEmpty { navigation.selectedTab = 3 } else { resetFilters() }
                        }
                    }
                } else {
                    List {
                        if groupByAccount {
                            let groups = accountGroups
                            ForEach(groups, id: \.id) { group in
                                Section {
                                    ForEach(group.events) { eventRow($0) }
                                } header: {
                                    Text(store.account(id: group.id)?.name ?? group.events.first?.accountName ?? "Unknown account")
                                } footer: {
                                    if group.id == groups.last?.id { privacyFooter }
                                }
                            }
                        } else {
                            Section {
                                ForEach(events) { eventRow($0) }
                            } header: {
                                Text("\(events.count) \(events.count == 1 ? "event" : "events")")
                            } footer: {
                                privacyFooter
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(FleetStyle.canvas)
            .navigationTitle("Inbox")
            .searchable(text: $search, prompt: "Search activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Read all", systemImage: "checkmark.circle") {
                        for event in store.events where !event.isRead { notifications.clearDelivered(eventID: event.id) }
                        store.markAllRead()
                        notifications.syncBadge()
                    }
                    .disabled(store.unreadCount() == 0 || store.persistenceUnavailable)
                }
            }
            .sheet(isPresented: $showingFilters) { filtersSheet }
            .sheet(item: $detail, onDismiss: {
                if let event = pendingEvent {
                    pendingEvent = nil
                    openFleetEvent(event, store: store, pool: pool, navigation: navigation, notifications: notifications)
                }
            }) { event in
                EventDetailView(event: event, openAccount: { pendingEvent = $0 })
            }
        }
    }

    private func eventRow(_ event: FleetEvent) -> some View {
        Button {
            if store.account(id: event.accountID) != nil {
                openFleetEvent(event, store: store, pool: pool, navigation: navigation, notifications: notifications)
            } else {
                detail = event
            }
        } label: {
            EventRow(event: event, hidePreview: store.settings.hideNotificationPreviews)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the account and marks this event as read")
        .contextMenu {
            Button("Details", systemImage: "info.circle") { detail = event }
            if !event.isRead {
                Button("Mark read", systemImage: "checkmark") { markRead(event) }
                    .disabled(store.persistenceUnavailable)
            }
            Button("Delete event", systemImage: "trash", role: .destructive) { delete(event) }
                .disabled(store.persistenceUnavailable)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(event) }
                .disabled(store.persistenceUnavailable)
            Button("Details", systemImage: "info.circle") { detail = event }.tint(.gray)
        }
        .swipeActions(edge: .leading) {
            if !event.isRead {
                Button("Read", systemImage: "checkmark") { markRead(event) }
                    .tint(FleetStyle.accent).disabled(store.persistenceUnavailable)
            }
        }
    }

    @ViewBuilder private var privacyFooter: some View {
        if store.settings.hideNotificationPreviews {
            Label("Previews are hidden. You can reveal an individual preview in event details.", systemImage: "eye.slash")
        }
    }

    private var filtersSheet: some View {
        NavigationStack {
            Form {
                Section("Narrow your inbox") {
                    Picker("Account", selection: $accountID) {
                        Text("All accounts").tag(UUID?.none)
                        ForEach(store.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Category", selection: $kind) {
                        Text("All categories").tag(EventKind?.none)
                        ForEach(EventKind.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    Picker("Time", selection: $period) {
                        ForEach(InboxPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Display") {
                    Toggle("Group by account", isOn: $groupByAccount)
                }
                Section {
                    Button("Reset filters") { accountID = nil; kind = nil; period = .anytime; groupByAccount = false }
                }
            }
            .navigationTitle("Inbox filters").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func resetFilters() {
        search = ""; accountID = nil; kind = nil; period = .anytime; groupByAccount = false; navigation.inboxScope = .all
    }

    private func markRead(_ event: FleetEvent) {
        store.markRead(event.id)
        notifications.clearDelivered(eventID: event.id)
        notifications.syncBadge()
    }

    private func delete(_ event: FleetEvent) {
        store.deleteEvent(event)
        notifications.clearDelivered(eventID: event.id)
        notifications.syncBadge()
    }
}

@MainActor
private struct EventDetailView: View {
    @Environment(FleetStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    let event: FleetEvent
    let openAccount: (FleetEvent) -> Void
    @State private var revealPreview = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EventRow(event: event, hidePreview: true)
                    LabeledContent("Received", value: event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Source", value: event.source.title)
                    LabeledContent("Status", value: (store.events.first { $0.id == event.id }?.isRead ?? event.isRead) ? "Read" : "Unread")
                }
                if let preview = event.preview, !preview.isEmpty {
                    Section("Preview") {
                        if !store.settings.hideNotificationPreviews || revealPreview {
                            Text(preview).textSelection(.enabled)
                        } else {
                            Button("Show preview", systemImage: "eye") { revealPreview = true }
                        }
                    }
                }
                Section {
                    Button("Open account", systemImage: "arrow.up.right.square") {
                        openAccount(event)
                        dismiss()
                    }
                    .disabled(store.account(id: event.accountID) == nil)
                    Button("Mark read", systemImage: "checkmark") {
                        store.markRead(event.id)
                        notifications.clearDelivered(eventID: event.id)
                        notifications.syncBadge()
                    }
                    .disabled(store.persistenceUnavailable || (store.events.first { $0.id == event.id }?.isRead ?? true))
                }
            }
            .navigationTitle("Event details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
