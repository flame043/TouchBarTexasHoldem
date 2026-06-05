import Foundation

protocol GameEngineDelegate: AnyObject {
    func gameEngineDidUpdate(_ engine: GameEngine)
    func gameEngine(_ engine: GameEngine, didShowTouchBarMessage message: String)
}

enum GamePhase: String {
    case preFlop = "Pre-Flop"
    case flop = "Flop"
    case turn = "Turn"
    case river = "River"
    case showdown = "Showdown"
    case gameOver = "Game Over"
}

enum GameOverReason {
    case humanOutOfChips
    case allAIOutOfChips
}

final class GameEngine {
    weak var delegate: GameEngineDelegate?

    let players: [PokerPlayer] = [
        PokerPlayer(name: "You", type: .human),
        PokerPlayer(name: "AI 1", type: .ai),
        PokerPlayer(name: "AI 2", type: .ai),
        PokerPlayer(name: "AI 3", type: .ai)
    ]

    private let deck = Deck()
    var communityCards: [Card] = []
    var pot: Int = 0
    var highestBet: Int = 0
    var minimumRaise: Int = 50
    var phase: GamePhase = .preFlop
    var currentPlayerIndex: Int = 0
    var actionLog: [String] = []
    var gameOverReason: GameOverReason?

    var human: PokerPlayer { players[0] }

    var boardText: String {
        communityCards.isEmpty ? "Board: --" : "Board: " + communityCards.map { $0.displayText }.joined(separator: " ")
    }

    var callAmountForHuman: Int {
        max(0, highestBet - human.currentBet)
    }

    func startNewGame() {
        players.forEach { $0.resetForNewGame() }
        pot = 0
        highestBet = 0
        communityCards = []
        actionLog = []
        phase = .preFlop
        gameOverReason = nil
        startNewHand()
    }

    func startNewHand() {
        if checkGameOver() { return }

        deck.reset()
        communityCards = []
        pot = 0
        highestBet = 0
        phase = .preFlop
        actionLog = []
        players.forEach { $0.resetForNewHand() }
        dealHoleCards()
        currentPlayerIndex = 0
        actionLog.append("New hand started.")
        notifyTouchBar("New Hand | \(boardText) | You: \(human.handText)")
        delegate?.gameEngineDidUpdate(self)
    }

    private func dealHoleCards() {
        for _ in 0..<2 {
            for player in players where player.chips > 0 {
                if let card = deck.draw() {
                    player.hand.append(card)
                }
            }
        }
    }

    func availableActionsForHuman() -> [ActionOption] {
        let callAmount = callAmountForHuman
        if callAmount == 0 {
            return [.check, .raise, .allIn, .fold]
        } else {
            return [.call, .raise, .allIn, .fold]
        }
    }

    func performHumanAction(_ action: PokerAction) {
        guard phase != .gameOver else { return }
        apply(action, to: human)
        notifyTouchBar("You \(action.displayText) | Pot: \(pot)")
        delegate?.gameEngineDidUpdate(self)
        advanceAfterHumanAction()
    }

    private func advanceAfterHumanAction() {
        runAIPlayers()
        endBettingRoundOrShowdown()
    }

    private func runAIPlayers() {
        for player in players where player.type == .ai && player.canAct {
            let action = decideAIAction(for: player)
            apply(action, to: player)
            notifyTouchBar("\(boardText) | \(player.name) \(action.displayText)")
        }
        delegate?.gameEngineDidUpdate(self)
    }

    private func decideAIAction(for player: PokerPlayer) -> PokerAction {
        let callAmount = max(0, highestBet - player.currentBet)
        let strength = estimateStrength(for: player)
        let random = Double.random(in: 0...1)
        let bluffChance: Double

        switch player.name {
        case "AI 1": bluffChance = 0.12
        case "AI 2": bluffChance = 0.25
        default: bluffChance = 0.08
        }

        if callAmount == 0 {
            if random < bluffChance || strength > 0.70 {
                return .raise(min(minimumRaise, player.chips))
            }
            if random > 0.96 {
                return .allIn
            }
            return .check
        }

        if callAmount >= player.chips {
            if strength > 0.65 || random < bluffChance {
                return .allIn
            }
            return .fold
        }

        if strength > 0.75 && random < 0.45 {
            return .raise(min(minimumRaise, player.chips))
        }
        if random < bluffChance {
            return .raise(min(minimumRaise, player.chips))
        }
        if strength < 0.35 && random < 0.60 {
            return .fold
        }
        return .call
    }

    private func estimateStrength(for player: PokerPlayer) -> Double {
        if communityCards.count >= 3 {
            let rank = HandEvaluator.evaluate(player.hand + communityCards)
            return Double(rank.category.rawValue) / 10.0
        }

        let ranks = player.hand.map { $0.rank.rawValue }.sorted(by: >)
        guard ranks.count == 2 else { return 0.3 }
        if ranks[0] == ranks[1] { return ranks[0] >= 10 ? 0.85 : 0.65 }
        if ranks[0] >= 14 && ranks[1] >= 10 { return 0.72 }
        if ranks[0] >= 12 && ranks[1] >= 10 { return 0.60 }
        if abs(ranks[0] - ranks[1]) == 1 { return 0.45 }
        return Double(ranks[0] + ranks[1]) / 30.0
    }

    private func apply(_ action: PokerAction, to player: PokerPlayer) {
        switch action {
        case .check:
            actionLog.append("\(player.name) checks.")

        case .call:
            let need = max(0, highestBet - player.currentBet)
            let paid = min(need, player.chips)
            player.chips -= paid
            player.currentBet += paid
            pot += paid
            if player.chips == 0 { player.status = .allIn }
            actionLog.append("\(player.name) calls \(paid).")

        case .raise(let amount):
            let callAmount = max(0, highestBet - player.currentBet)
            let total = min(callAmount + amount, player.chips)
            player.chips -= total
            player.currentBet += total
            pot += total
            highestBet = max(highestBet, player.currentBet)
            if player.chips == 0 { player.status = .allIn }
            actionLog.append("\(player.name) raises to \(player.currentBet).")

        case .allIn:
            let amount = player.chips
            player.chips = 0
            player.currentBet += amount
            pot += amount
            highestBet = max(highestBet, player.currentBet)
            player.status = .allIn
            actionLog.append("\(player.name) goes all-in with \(amount).")

        case .fold:
            player.status = .folded
            actionLog.append("\(player.name) folds.")
        }
    }

    private func endBettingRoundOrShowdown() {
        if players.filter({ $0.isInHand }).count == 1 {
            awardPotToLastStanding()
            return
        }

        resetBetsForNextStreet()

        switch phase {
        case .preFlop:
            dealFlop()
            phase = .flop
            notifyTouchBar("\(boardText) | Flop dealt")
        case .flop:
            dealTurn()
            phase = .turn
            notifyTouchBar("\(boardText) | Turn dealt")
        case .turn:
            dealRiver()
            phase = .river
            notifyTouchBar("\(boardText) | River dealt")
        case .river:
            showdown()
            return
        case .showdown, .gameOver:
            return
        }

        delegate?.gameEngineDidUpdate(self)
    }

    private func resetBetsForNextStreet() {
        highestBet = 0
        for player in players {
            player.currentBet = 0
        }
    }

    private func dealFlop() {
        deck.burnCard()
        for _ in 0..<3 {
            if let card = deck.draw() { communityCards.append(card) }
        }
        actionLog.append("Flop: \(communityCards.map { $0.displayText }.joined(separator: " ")).")
    }

    private func dealTurn() {
        deck.burnCard()
        if let card = deck.draw() { communityCards.append(card) }
        actionLog.append("Turn: \(communityCards.last?.displayText ?? "--").")
    }

    private func dealRiver() {
        deck.burnCard()
        if let card = deck.draw() { communityCards.append(card) }
        actionLog.append("River: \(communityCards.last?.displayText ?? "--").")
    }

    private func awardPotToLastStanding() {
        guard let winner = players.first(where: { $0.isInHand }) else { return }
        winner.chips += pot
        actionLog.append("\(winner.name) wins \(pot).")
        notifyTouchBar("\(winner.name) wins pot \(pot) | R: Next Hand")
        pot = 0
        if !checkGameOver() {
            delegate?.gameEngineDidUpdate(self)
        }
    }

    private func showdown() {
        phase = .showdown
        let activePlayers = players.filter { $0.isInHand }
        let results = activePlayers.map { player in
            (player: player, rank: HandEvaluator.evaluate(player.hand + communityCards))
        }

        guard let winner = results.max(by: { $0.rank < $1.rank }) else { return }
        winner.player.chips += pot

        let revealText = results.map { "\($0.player.name): \($0.player.handText)" }.joined(separator: " | ")
        notifyTouchBar("\(boardText) | \(revealText)")

        actionLog.append("Showdown.")
        for result in results {
            actionLog.append("\(result.player.name): \(result.player.handText) -> \(result.rank.description)")
        }
        actionLog.append("Winner: \(winner.player.name), pot won: \(pot).")
        pot = 0

        _ = checkGameOver()
        delegate?.gameEngineDidUpdate(self)
    }

    private func checkGameOver() -> Bool {
        if human.chips <= 0 {
            phase = .gameOver
            gameOverReason = .humanOutOfChips
            notifyTouchBar("Game Over | You are out of chips | R: Restart | Q: Quit")
            delegate?.gameEngineDidUpdate(self)
            return true
        }

        let aiPlayers = players.filter { $0.type == .ai }
        if aiPlayers.allSatisfy({ $0.chips <= 0 }) {
            phase = .gameOver
            gameOverReason = .allAIOutOfChips
            notifyTouchBar("You Win | All AI players are out | R: Restart | Q: Quit")
            delegate?.gameEngineDidUpdate(self)
            return true
        }
        return false
    }

    private func notifyTouchBar(_ message: String) {
        delegate?.gameEngine(self, didShowTouchBarMessage: message)
    }

    func mainScreenText() -> String {
        let playersText = players.map { player -> String in
            let status: String
            switch player.status {
            case .active: status = "Active"
            case .folded: status = "Folded"
            case .allIn: status = "All-in"
            case .busted: status = "Busted"
            }

            let hand = player.type == .human || phase == .showdown || phase == .gameOver ? player.handText : "?? ??"
            return "\(player.name): \(player.chips) chips | Bet: \(player.currentBet) | \(status) | Hand: \(hand)"
        }.joined(separator: "\n")

        let lastLog = actionLog.suffix(10).joined(separator: "\n")

        if phase == .gameOver {
            let title = gameOverReason == .allAIOutOfChips ? "You Win!" : "Game Over"
            return """
            \(title)

            Final Chips:
            \(players.map { "\($0.name): \($0.chips)" }.joined(separator: "\n"))

            Press R to restart or Q to quit.
            """
        }

        return """
        TouchBar Texas Holdem

        Phase: \(phase.rawValue)
        \(boardText)
        Pot: \(pot)
        Highest Bet: \(highestBet)

        \(playersText)

        Controls:
        ← / → Select Action     ↑ / ↓ Change Raise Amount
        Enter Confirm           R New Hand / Restart
        Esc Fold                Q Quit

        Log:
        \(lastLog)
        """
    }
}
