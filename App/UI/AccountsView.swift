import SwiftUI

@MainActor
struct AccountsView: View {
    @Environment(FleetStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var group: String?
    @State private var listLayout = false
    @State private var addingAccount = false
    @State private var editingAccount: AccountProfile?
    @State private var deletingAccount: AccountProfile?

    private var orderedAccounts: [AccountProfile] {
        store.accounts.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var filteredAccounts: [AccountProfile] {
        orderedAccounts.filter { account in
            (!favoritesOnly || account.isFavorite) && (group == nil || account.group == group) &&
            (search.isEmpty || ([account.name, account.role, account.project, account.group, account.notes] + account.tags)
                .joined(separator: " ").localizedStandardContains(search))
        }
    }

    private var groups: [String] {
        Set(store.accounts.map(\.group).filter { !$0.isEmpty }).sorted()
    }

    private var canReorder: Bool { search.isEmpty && !favoritesOnly && group == nil && !store.persistenceUnavailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !store.accounts.isEmpty { filters }
                if store.accounts.isEmpty {
                    ScrollView {
                        EmptyFleetView(symbol: "square.stack.3d.up", title: "Make space for your work",
                                       message: "Create an account profile for each Muse identity. Sign in on the official website after opening a profile.",
                                       actionTitle: "Add account", action: { addingAccount = true })
                            .disabled(store.persistenceUnavailable)
                    }
                } else if filteredAccounts.isEmpty {
                    ScrollView {
                        EmptyFleetView(symbol: "magnifyingglass", title: "No matching accounts",
                                       message: "Try another name, project, tag, or group.", actionTitle: "Reset filters") {
                            search = ""; favoritesOnly = false; group = nil
                        }
                    }
                } else if listLayout {
                    List {
                        if !canReorder {
                            Text("Clear filters to reorder all accounts.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(filteredAccounts) { account in
                            Button { navigation.switchTo(account) } label: {
                                AccountListRow(account: account, unreadCount: store.unreadCount(accountID: account.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("account.row.\(account.id.uuidString)")
                            .contextMenu { accountActions(account) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) { deletingAccount = account }
                                Button("Edit", systemImage: "pencil") { editingAccount = account }.tint(FleetStyle.accent)
                            }
                            .disabled(store.persistenceUnavailable)
                            .swipeActions(edge: .leading) {
                                Button(account.isFavorite ? "Unfavorite" : "Favorite", systemImage: account.isFavorite ? "star.slash" : "star") {
                                    toggleFavorite(account)
                                }.tint(.orange)
                            }
                            .moveDisabled(!canReorder)
                        }
                        .onMove(perform: reorder)
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 152))], spacing: 14) {
                            ForEach(filteredAccounts) { account in
                                VStack(spacing: 0) {
                                    Button { navigation.switchTo(account) } label: {
                                        QuickAccountCard(account: account, unreadCount: store.unreadCount(accountID: account.id))
                                    }.buttonStyle(.plain)
                                        .accessibilityIdentifier("account.row.\(account.id.uuidString)")
                                    HStack {
                                        Button {
                                            toggleFavorite(account)
                                        } label: {
                                            Image(systemName: account.isFavorite ? "star.fill" : "star")
                                                .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .accessibilityLabel(account.isFavorite ? "Unfavorite \(account.name)" : "Favorite \(account.name)")
                                        .disabled(store.persistenceUnavailable)
                                        Spacer()
                                        Menu { accountActions(account) } label: {
                                            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                                        }
                                        .accessibilityLabel("Actions for \(account.name)")
                                    }
                                    .padding(.horizontal, 8)
                                }
                                .background(FleetStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                                .contextMenu { accountActions(account) }
                            }
                        }
                        .padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
                    }
                }
            }
            .background(FleetStyle.canvas)
            .navigationTitle("Accounts")
            .searchable(text: $search, prompt: "Name, project, tag, or group")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if listLayout && !store.accounts.isEmpty { EditButton().disabled(!canReorder) }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(listLayout ? "Show grid" : "Show list", systemImage: listLayout ? "square.grid.2x2" : "list.bullet") {
                        listLayout.toggle()
                    }
                    Button("Add account", systemImage: "plus") { addingAccount = true }
                        .accessibilityIdentifier("account.add")
                        .disabled(store.persistenceUnavailable)
                }
            }
            .sheet(isPresented: $addingAccount) { AccountEditorView() }
            .sheet(item: $editingAccount) { AccountEditorView(account: $0) }
            .sheet(item: $deletingAccount) { account in
                DeleteAccountView(account: account)
            }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { favoritesOnly.toggle() } label: {
                    Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 11)
                        .background(favoritesOnly ? FleetStyle.accent.opacity(0.14) : FleetStyle.surface, in: Capsule())
                }
                .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
                Menu {
                    Button("All groups") { group = nil }
                    ForEach(groups, id: \.self) { value in
                        Button { group = value } label: {
                            if group == value { Label(value, systemImage: "checkmark") } else { Text(value) }
                        }
                    }
                } label: {
                    Label(group ?? "All groups", systemImage: "folder")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 11)
                        .background(group != nil ? FleetStyle.accent.opacity(0.14) : FleetStyle.surface, in: Capsule())
                }
                Text("\(filteredAccounts.count) accounts").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    @ViewBuilder private func accountActions(_ account: AccountProfile) -> some View {
        Button("Open Muse", systemImage: "arrow.up.right.square") { navigation.switchTo(account) }
        Button("Edit profile", systemImage: "pencil") { editingAccount = account }.disabled(store.persistenceUnavailable)
        Button(account.isFavorite ? "Remove favorite" : "Add favorite", systemImage: "star") { toggleFavorite(account) }
            .disabled(store.persistenceUnavailable)
        Button("Delete account", systemImage: "trash", role: .destructive) { deletingAccount = account }
            .disabled(store.persistenceUnavailable)
    }

    private func toggleFavorite(_ account: AccountProfile) {
        var updated = account
        updated.isFavorite.toggle()
        store.updateAccount(updated)
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        guard canReorder else { return }
        var accounts = orderedAccounts
        accounts.move(fromOffsets: source, toOffset: destination)
        for (index, account) in accounts.enumerated() where account.sortOrder != index {
            var updated = account
            updated.sortOrder = index
            store.updateAccount(updated)
        }
    }
}

struct AccountListRow: View {
    let account: AccountProfile
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 12) {
            AccountAvatar(account: account)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(account.name).font(.headline)
                    if account.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange).accessibilityLabel("Favorite") }
                }
                if !account.project.isEmpty || !account.role.isEmpty {
                    Text([account.project, account.role].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if !account.group.isEmpty { Text(account.group).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            UnreadPill(count: unreadCount)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Muse")
    }
}

@MainActor
struct DeleteAccountView: View {
    @Environment(FleetStore.self) private var store
    @Environment(BrowserPool.self) private var pool
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    let account: AccountProfile
    @State private var clearData = true
    @State private var deleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        AccountAvatar(account: account)
                        Text(account.name).font(.headline)
                    }
                    Text("Delete this profile and its activity from MuseFleet? This does not delete your Muse account or conversations.")
                    Toggle("Also clear website data", isOn: $clearData)
                } footer: {
                    Text(clearData ? "You will be signed out of this profile’s browser." : "Sign-in data stays on this device after the profile is removed. Clear it now to remove that saved sign-in.")
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                Section {
                    Button(role: .destructive) { Task { await deleteAccount() } } label: {
                        HStack {
                            Text(deleting ? "Deleting…" : "Delete account")
                            Spacer()
                            if deleting { ProgressView() }
                        }
                    }
                    .disabled(deleting || store.persistenceUnavailable)
                }
            }
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(deleting) } }
            .disabled(deleting)
            .interactiveDismissDisabled(deleting)
        }
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            if clearData { try await pool.clearWebsiteData(accountID: account.id) }
            pool.remove(accountID: account.id)
            store.deleteAccountMetadata(id: account.id)
            notifications.removeNotifications(accountID: account.id)
            notifications.syncBadge()
            if let error = store.storageError { errorMessage = error } else { dismiss() }
        } catch {
            errorMessage = "Website data could not be cleared. The profile has been kept. \(error.localizedDescription)"
        }
    }
}
