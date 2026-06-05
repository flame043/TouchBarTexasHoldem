import Foundation

enum Suit: String, CaseIterable {
    case spades = "♠"
    case hearts = "♥"
    case diamonds = "♦"
    case clubs = "♣"
}

enum Rank: Int, CaseIterable, Comparable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13
    case ace = 14

    static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayText: String {
        switch self {
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }
}

struct Card: Equatable, Hashable {
    let rank: Rank
    let suit: Suit

    var displayText: String {
        "\(rank.displayText)\(suit.rawValue)"
    }
}
