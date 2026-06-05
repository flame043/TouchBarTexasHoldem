import Foundation

enum HandCategory: Int, Comparable {
    case highCard = 1
    case onePair = 2
    case twoPair = 3
    case threeOfAKind = 4
    case straight = 5
    case flush = 6
    case fullHouse = 7
    case fourOfAKind = 8
    case straightFlush = 9
    case royalFlush = 10

    static func < (lhs: HandCategory, rhs: HandCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayText: String {
        switch self {
        case .highCard: return "High Card"
        case .onePair: return "One Pair"
        case .twoPair: return "Two Pair"
        case .threeOfAKind: return "Three of a Kind"
        case .straight: return "Straight"
        case .flush: return "Flush"
        case .fullHouse: return "Full House"
        case .fourOfAKind: return "Four of a Kind"
        case .straightFlush: return "Straight Flush"
        case .royalFlush: return "Royal Flush"
        }
    }
}

struct HandRank: Comparable {
    let category: HandCategory
    let tiebreakers: [Int]
    let cards: [Card]

    var description: String {
        category.displayText
    }

    static func < (lhs: HandRank, rhs: HandRank) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category < rhs.category
        }
        return lhs.tiebreakers.lexicographicallyPrecedes(rhs.tiebreakers)
    }
}

enum HandEvaluator {
    static func evaluate(_ cards: [Card]) -> HandRank {
        precondition(cards.count >= 5, "Need at least 5 cards to evaluate a poker hand.")

        let combos = combinations(cards, choose: 5)
        let ranks = combos.map { evaluateFiveCards($0) }
        return ranks.max()!
    }

    private static func evaluateFiveCards(_ cards: [Card]) -> HandRank {
        let sorted = cards.sorted { $0.rank.rawValue > $1.rank.rawValue }
        let values = sorted.map { $0.rank.rawValue }
        let isFlush = Set(cards.map { $0.suit }).count == 1
        let straightHigh = straightHighCard(values)

        if isFlush, let high = straightHigh {
            if high == 14 {
                return HandRank(category: .royalFlush, tiebreakers: [14], cards: sorted)
            }
            return HandRank(category: .straightFlush, tiebreakers: [high], cards: sorted)
        }

        let groups = Dictionary(grouping: values, by: { $0 })
            .map { (rank: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.rank > $1.rank
            }

        if let four = groups.first(where: { $0.count == 4 }) {
            let kicker = groups.first(where: { $0.rank != four.rank })!.rank
            return HandRank(category: .fourOfAKind, tiebreakers: [four.rank, kicker], cards: sorted)
        }

        if let three = groups.first(where: { $0.count == 3 }),
           let pair = groups.first(where: { $0.count == 2 }) {
            return HandRank(category: .fullHouse, tiebreakers: [three.rank, pair.rank], cards: sorted)
        }

        if isFlush {
            return HandRank(category: .flush, tiebreakers: values, cards: sorted)
        }

        if let high = straightHigh {
            return HandRank(category: .straight, tiebreakers: [high], cards: sorted)
        }

        if let three = groups.first(where: { $0.count == 3 }) {
            let kickers = groups.filter { $0.rank != three.rank }.map { $0.rank }.sorted(by: >)
            return HandRank(category: .threeOfAKind, tiebreakers: [three.rank] + kickers, cards: sorted)
        }

        let pairs = groups.filter { $0.count == 2 }.map { $0.rank }.sorted(by: >)
        if pairs.count >= 2 {
            let kicker = groups.filter { !pairs.prefix(2).contains($0.rank) }.map { $0.rank }.max() ?? 0
            return HandRank(category: .twoPair, tiebreakers: Array(pairs.prefix(2)) + [kicker], cards: sorted)
        }

        if let pair = groups.first(where: { $0.count == 2 }) {
            let kickers = groups.filter { $0.rank != pair.rank }.map { $0.rank }.sorted(by: >)
            return HandRank(category: .onePair, tiebreakers: [pair.rank] + kickers, cards: sorted)
        }

        return HandRank(category: .highCard, tiebreakers: values, cards: sorted)
    }

    private static func straightHighCard(_ values: [Int]) -> Int? {
        var unique = Array(Set(values)).sorted(by: >)
        if unique.contains(14) {
            unique.append(1) // A can be low in A-2-3-4-5
        }

        guard unique.count >= 5 else { return nil }

        for i in 0...(unique.count - 5) {
            let window = Array(unique[i..<(i + 5)])
            if window[0] - window[4] == 4 && Set(window).count == 5 {
                return window[0] == 1 ? 5 : window[0]
            }
        }
        return nil
    }

    private static func combinations<T>(_ array: [T], choose k: Int) -> [[T]] {
        if k == 0 { return [[]] }
        if array.count < k { return [] }
        if array.count == k { return [array] }

        var result: [[T]] = []
        for i in 0...(array.count - k) {
            let head = array[i]
            let tail = Array(array[(i + 1)...])
            for combo in combinations(tail, choose: k - 1) {
                result.append([head] + combo)
            }
        }
        return result
    }
}
