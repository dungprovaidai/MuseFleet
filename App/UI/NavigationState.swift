import Observation
import Foundation

enum InboxScope: String, CaseIterable {
    case all = "All", unread = "Unread", attention = "Attention"
}

@MainActor @Observable
final class NavigationState {
    var selectedAccountID: UUID?
    var selectedTab = 0
    var inboxScope = InboxScope.all
    private(set) var previousAccountID: UUID?
    @ObservationIgnored private var lastOpenedAccountID: UUID?

    func openAccount(_ id: UUID) {
        switchTo(accountID: id)
    }

    func switchTo(_ account: AccountProfile) {
        switchTo(accountID: account.id)
    }

    func switchTo(accountID: UUID) {
        guard selectedAccountID != accountID else { return }
        if let previous = selectedAccountID ?? lastOpenedAccountID, previous != accountID {
            previousAccountID = previous
        } else if previousAccountID == accountID {
            previousAccountID = nil
        }
        selectedAccountID = accountID
        lastOpenedAccountID = accountID
        assert(previousAccountID != selectedAccountID)
    }

    func switchToPrevious() {
        guard let previousAccountID else { return }
        switchTo(accountID: previousAccountID)
    }

    func closeBrowser() {
        selectedAccountID = nil
    }
}
