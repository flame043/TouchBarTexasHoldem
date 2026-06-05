import Foundation

final class Deck {
    private var cards: [Card] = []

    init() {
        reset()
    }

    func reset() {
        cards = []
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                cards.append(Card(rank: rank, suit: suit))
            }
        }
        cards.shuffle()
    }

    func draw() -> Card? {
        guard !cards.isEmpty else { return nil }
        return cards.removeFirst()
    }

    func burnCard() {
        _ = draw()
    }
}
