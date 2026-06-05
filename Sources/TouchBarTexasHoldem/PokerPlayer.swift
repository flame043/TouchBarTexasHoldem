import Foundation

enum PlayerType {
    case human
    case ai
}

enum PlayerStatus {
    case active
    case folded
    case allIn
    case busted
}

final class PokerPlayer {
    let name: String
    let type: PlayerType
    var chips: Int
    var currentBet: Int = 0
    var hand: [Card] = []
    var status: PlayerStatus = .active

    init(name: String, type: PlayerType, chips: Int = 1000) {
        self.name = name
        self.type = type
        self.chips = chips
    }

    var canAct: Bool {
        status == .active && chips > 0
    }

    var isInHand: Bool {
        status == .active || status == .allIn
    }

    var handText: String {
        hand.map { $0.displayText }.joined(separator: " ")
    }

    func resetForNewHand() {
        currentBet = 0
        hand = []
        if chips > 0 {
            status = .active
        } else {
            status = .busted
        }
    }

    func resetForNewGame() {
        chips = 1000
        currentBet = 0
        hand = []
        status = .active
    }
}
