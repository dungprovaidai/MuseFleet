import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(FleetStore.self) private var store
    @Environment(BrowserPool.self) private var pool
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(NavigationState.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var addingAccount = false

    private var quickAccounts: [AccountProfile] {
        Array(store.accounts.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            if $0.lastVisitedAt != $1.lastVisitedAt {
                return ($0.lastVisitedAt ?? .distantPast) > ($1.lastVisitedAt ?? .distantPast)
            }
            return $0.sortOrder < $1.sortOrder
        }.prefix(6))
    }

    private var recentEvents: [FleetEvent] {
        Array(store.events.sorted { $0.timestamp > $1.timestamp }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    counts
                    VStack(spacing: 16) {
                        SectionHeading(title: "Your accounts") {
                            Button("View all") { navigation.selectedTab = 1 }
                        }
                        if store.accounts.isEmpty {
                            EmptyFleetView(symbol: "person.crop.circle.badge.plus", title: "A place for every account",
                                           message: "Add your first profile, then sign in to Muse in its own browser space.",
                                           actionTitle: "Add account", action: { addingAccount = true })
                                .disabled(store.persistenceUnavailable)
                                .background(FleetStyle.surface, in: RoundedRectangle(cornerRadius: 24))
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 152))], spacing: 12) {
                                ForEach(quickAccounts) { account in
                                    Button { navigation.switchTo(account) } label: {
                                        QuickAccountCard(account: account, unreadCount: store.unreadCount(accountID: account.id))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Opens this account’s Muse browser")
                                }
                            }
                        }
                    }
                    VStack(spacing: 16) {
                        SectionHeading(title: "Recent activity") {
                            Button("Inbox") { navigation.selectedTab = 2 }
                        }
                        if recentEvents.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "tray").font(.title2).foregroundStyle(FleetStyle.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Nothing here yet").font(.subheadline.bold())
                                    Text("Events appear when a supported source is available. An open account alone does not guarantee detection.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(FleetStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(recentEvents) { event in
                                    Button {
                                        openFleetEvent(event, store: store, pool: pool, navigation: navigation, notifications: notifications)
                                    } label: {
                                        EventRow(event: event, hidePreview: store.settings.hideNotificationPreviews)
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.account(id: event.accountID) == nil)
                                    if event.id != recentEvents.last?.id {
                                        Divider().padding(.leading, 70)
                                    }
                                }
                            }
                            .background(FleetStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                    Label("Web activity pauses when MuseFleet is in the background.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
                }
                .padding(20)
                .frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
            }
            .background(FleetStyle.canvas)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add account", systemImage: "plus") { addingAccount = true }
                        .disabled(store.persistenceUnavailable)
                }
            }
            .sheet(isPresented: $addingAccount) { AccountEditorView() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(FleetStyle.accent)
                Text("MUSEFLEET").font(.caption.weight(.bold)).tracking(3)
            }
            Text("Many spaces.\nOne clear view.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Your accounts, conversations, and next steps. Together, with room to focus.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(FleetStyle.surface.gradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 94, weight: .ultraLight))
                        .foregroundStyle(FleetStyle.accent.opacity(0.08))
                        .padding(18).accessibilityHidden(true)
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(FleetStyle.accent.opacity(0.10)))
    }

    private var counts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { countTiles }
            VStack(spacing: 10) { countTiles }
        }
    }

    @ViewBuilder private var countTiles: some View {
        StatTile(title: "Accounts", value: store.accounts.count, symbol: "person.2") {
            navigation.selectedTab = 1
        }
        StatTile(title: "Unread", value: store.unreadCount(), symbol: "tray") {
            navigation.inboxScope = .unread
            navigation.selectedTab = 2
        }
        StatTile(title: "Attention", value: store.events.filter { !$0.isRead && $0.type.needsAttention }.count,
                 symbol: "hand.raised") {
            navigation.inboxScope = .attention
            navigation.selectedTab = 2
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: Int
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(FleetStyle.accent).font(.subheadline)
                Text(value, format: .number).font(.title.bold()).monospacedDigit()
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(FleetStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct QuickAccountCard: View {
    let account: AccountProfile
    let unreadCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                AccountAvatar(account: account)
                Spacer(minLength: 0)
                UnreadPill(count: unreadCount)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(account.name).font(.headline).lineLimit(2)
                    if account.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(account.project.isEmpty ? (account.role.isEmpty ? "Open Muse" : account.role) : account.project)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FleetStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color(hex: account.colorHex).opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}
