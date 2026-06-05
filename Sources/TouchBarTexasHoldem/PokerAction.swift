import Foundation

enum PokerAction {
    case check
    case call
    case raise(Int)
    case allIn
    case fold

    var displayText: String {
        switch self {
        case .check:
            return "checks"
        case .call:
            return "calls"
        case .raise(let amount):
            return "raises \(amount)"
        case .allIn:
            return "goes all-in"
        case .fold:
            return "folds"
        }
    }
}

enum ActionOption: Int, CaseIterable {
    case check
    case call
    case raise
    case allIn
    case fold

    var title: String {
        switch self {
        case .check: return "Check"
        case .call: return "Call"
        case .raise: return "Raise"
        case .allIn: return "All-in"
        case .fold: return "Fold"
        }
    }
}
