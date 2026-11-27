import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

@MainActor
struct AccountEditorView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool
    @State private var draft: AccountProfile
    @State private var tagsText: String
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var errorMessage: String?

    init(account: AccountProfile? = nil) {
        isNew = account == nil
        _draft = State(initialValue: account ?? AccountProfile())
        _tagsText = State(initialValue: account?.tags.joined(separator: ", ") ?? "")
    }

    private var validColor: Bool {
        let hex = draft.colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return hex.count == 6 && UInt32(hex, radix: 16) != nil
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.name.count <= 80 && validColor && !loadingPhoto && !store.persistenceUnavailable
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        AccountAvatar(account: draft, size: 88)
                        PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                            Label(loadingPhoto ? "Preparing photo…" : "Choose photo", systemImage: "photo")
                        }
                        .disabled(loadingPhoto)
                        if draft.avatarData != nil {
                            Button("Remove photo", role: .destructive) {
                                photo = nil
                                draft.avatarData = nil
                            }
                            .disabled(loadingPhoto)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    TextField("Account name", text: $draft.name).textContentType(.nickname)
                        .accessibilityLabel("Account name, required")
                        .accessibilityIdentifier("account.name")
                    Toggle("Favorite", isOn: $draft.isFavorite)
                } footer: {
                    Text("A local profile label, not your Muse credentials. Names can contain up to 80 characters.")
                }

                Section("Identity") {
                    Text("Symbol").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(FleetStyle.symbols, id: \.self) { symbol in
                            Button { draft.symbol = symbol } label: {
                                Image(systemName: symbol).font(.title3)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(draft.symbol == symbol ? FleetStyle.accent.opacity(0.16) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(draft.symbol == symbol ? .isSelected : [])
                        }
                    }
                    Text("Accent color").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(FleetStyle.colors, id: \.self) { hex in
                            Button { draft.colorHex = hex } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                    .overlay {
                                        if draft.colorHex.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "#")) == hex {
                                            Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(.white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(colorName(hex))
                            .accessibilityAddTraits(draft.colorHex.uppercased() == hex ? .isSelected : [])
                        }
                    }
                    TextField("Hex color, for example 7665E9", text: $draft.colorHex)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityLabel("Custom accent hex color")
                    if !validColor { Text("Enter six hexadecimal digits.").font(.caption).foregroundStyle(.red) }
                }

                Section("Organization") {
                    TextField("Role", text: $draft.role)
                    TextField("Project", text: $draft.project)
                    TextField("Group", text: $draft.group)
                    TextField("Tags, separated by commas", text: $tagsText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                }

                Section {
                    Toggle("Notifications for this account", isOn: $draft.notificationsEnabled)
                } footer: {
                    Text("Alerts require notification permission and a supported event source. This does not turn on background monitoring.")
                }

                if !isNew {
                    Section("Last activity") {
                        if let date = draft.lastVisitedAt {
                            LabeledContent("Last opened", value: date.formatted(date: .abbreviated, time: .shortened))
                        } else {
                            Text("This account has not been opened yet.").foregroundStyle(.secondary)
                        }
                        if let url = URLPolicy.safeConversation(draft.lastURL), let host = url.host {
                            LabeledContent("Website", value: host)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.10))
                }
            }
            .navigationTitle(isNew ? "New account" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave).accessibilityIdentifier("account.save")
                }
            }
            .task(id: photo) { await loadPhoto() }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.colorHex = draft.colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        draft.role = draft.role.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.project = draft.project.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.group = draft.group.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        draft.tags = tagsText.split(separator: ",").compactMap { part in
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag.lowercased()).inserted ? tag : nil
        }
        guard canSave else { return }
        if let current = store.account(id: draft.id) {
            draft.lastURL = current.lastURL
            draft.lastVisitedAt = current.lastVisitedAt
            draft.sortOrder = current.sortOrder
            store.updateAccount(draft)
        } else if isNew {
            store.addAccount(draft)
        } else {
            errorMessage = "This profile no longer exists. Your edits have not been saved."
            return
        }
        if let error = store.storageError { errorMessage = error } else { dismiss() }
    }

    private func loadPhoto() async {
        guard let photo else { return }
        loadingPhoto = true
        defer { loadingPhoto = false }
        do {
            guard let imported = try await photo.loadTransferable(type: PickedAvatar.self) else { throw AvatarError.unreadable }
            try Task.checkCancellation()
            draft.avatarData = imported.data
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func colorName(_ hex: String) -> String {
        switch hex {
        case "7665E9": "Violet"
        case "407AC9": "Blue"
        case "278578": "Teal"
        case "B46C32": "Copper"
        case "BF5278": "Rose"
        case "7D67A6": "Lavender"
        case "537949": "Green"
        default: "Slate"
        }
    }
}

private enum AvatarError: LocalizedError {
    case tooLarge, unreadable

    var errorDescription: String? {
        switch self {
        case .tooLarge: "Choose a photo smaller than 30 MB."
        case .unreadable: "This photo could not be prepared. Try a different image."
        }
    }
}

private struct PickedAvatar: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let url = received.file
            return try await Task.detached(priority: .userInitiated) {
                PickedAvatar(data: try AvatarProcessor.resize(url))
            }.value
        }
    }
}

private enum AvatarProcessor {
    static func resize(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size <= 30 * 1_024 * 1_024 else { throw AvatarError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw AvatarError.unreadable }
        for quality in [0.82, 0.65, 0.45, 0.25] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw AvatarError.unreadable
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), output.length <= 256 * 1_024 {
                assert(image.width <= 512 && image.height <= 512)
                return output as Data
            }
        }
        throw AvatarError.unreadable
    }
}
