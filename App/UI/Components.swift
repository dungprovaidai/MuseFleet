import SwiftUI
import UIKit

enum FleetStyle {
    static let accent = Color(hex: "7665E9")
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let colors = ["7665E9", "407AC9", "278578", "B46C32", "BF5278", "7D67A6", "537949", "686F7A"]
    static let symbols = [
        "sparkles", "person.crop.circle", "moon.stars", "sun.max", "leaf", "bolt",
        "paintbrush.pointed", "camera", "film", "music.note", "pencil.and.outline",
        "cube", "globe", "paperplane", "book", "heart", "star", "briefcase",
        "hammer", "lightbulb", "cloud", "mountain.2", "gamecontroller", "graduationcap"
    ]
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            self = FleetStyle.accentFallback
            return
        }
        self.init(.sRGB, red: Double((number >> 16) & 255) / 255,
                  green: Double((number >> 8) & 255) / 255,
                  blue: Double(number & 255) / 255, opacity: 1)
    }
}

private extension FleetStyle {
    static let accentFallback = Color(red: 0.46, green: 0.40, blue: 0.91)
}

struct AccountAvatar: View {
    let name: String
    let symbol: String
    let colorHex: String
    var data: Data? = nil
    var size: CGFloat = 48

    init(account: AccountProfile, size: CGFloat = 48) {
        name = account.name
        symbol = account.symbol
        colorHex = account.colorHex
        data = account.avatarData
        self.size = size
    }

    init(name: String, symbol: String, colorHex: String, data: Data? = nil, size: CGFloat = 48) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.data = data
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(Color(hex: colorHex).gradient)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol.isEmpty ? "person.crop.circle" : symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct EmptyFleetView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(FleetStyle.accent)
                .frame(width: 80, height: 80)
                .background(FleetStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 26))
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Spacer()
            trailing.font(.subheadline.weight(.semibold))
        }
    }
}

struct UnreadPill: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption.bold()).monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(.white)
                .background(FleetStyle.accent, in: Capsule())
                .accessibilityLabel("\(count) unread events")
        }
    }
}

struct EventRow: View {
    let event: FleetEvent
    let hidePreview: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AccountAvatar(name: event.accountName, symbol: event.accountSymbol,
                          colorHex: event.accountColorHex, size: 42)
                .overlay(alignment: .bottomTrailing) {
                    if !event.isRead {
                        Circle().fill(FleetStyle.accent).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(FleetStyle.surface, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.accountName).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 6)
                    Text(event.timestamp, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                Label(event.type.title, systemImage: event.type.symbol)
                    .font(.subheadline).foregroundStyle(.secondary)
                if !hidePreview, let preview = event.preview, !preview.isEmpty {
                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityValue(event.isRead ? "Read" : "Unread")
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
func openFleetEvent(_ event: FleetEvent, store: FleetStore, pool: BrowserPool,
                    navigation: NavigationState, notifications: NotificationCoordinator) {
    store.markRead(event.id)
    notifications.clearDelivered(eventID: event.id)
    notifications.syncBadge()
    guard let account = store.account(id: event.accountID) else { return }
    if let url = URLPolicy.safeConversation(event.conversationURL) {
        pool.session(for: account).load(url)
    }
    navigation.switchTo(account)
}
