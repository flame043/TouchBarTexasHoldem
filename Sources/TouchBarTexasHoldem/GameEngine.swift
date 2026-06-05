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
        PokerPlayer(name: "You", type: .human, chips: 1000),
        PokerPlayer(name: "AI 1", type: .ai, chips: 1000),
        PokerPlayer(name: "AI 2", type: .ai, chips: 1000),
        PokerPlayer(name: "AI 3", type: .ai, chips: 1000)
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

    let smallBlindAmount: Int = 25
    let bigBlindAmount: Int = 50
    private var dealerIndex: Int = -1
    private var smallBlindIndex: Int?
    private var bigBlindIndex: Int?
    private var lastRaiseAmount: Int = 50

    private var actedThisRound: Set<Int> = []

    var human: PokerPlayer { players[0] }

    var isHumanTurn: Bool {
        phase != .gameOver && phase != .showdown && currentPlayerIndex == 0 && human.canAct
    }

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
        lastRaiseAmount = bigBlindAmount
        communityCards = []
        actionLog = []
        phase = .preFlop
        gameOverReason = nil
        dealerIndex = -1
        smallBlindIndex = nil
        bigBlindIndex = nil
        startNewHand()
    }

    func startNewHand() {
        if checkGameOver() { return }

        deck.reset()
        communityCards = []
        pot = 0
        highestBet = 0
        lastRaiseAmount = bigBlindAmount
        phase = .preFlop
        actionLog = []
        actedThisRound = []
        players.forEach { $0.resetForNewHand() }

        guard players.filter({ $0.chips > 0 }).count >= 2 else {
            _ = checkGameOver()
            return
        }

        advanceDealerButton()
        dealHoleCards()
        postBlinds()

        actionLog.append("New hand. Dealer: \(players[dealerIndex].name). SB: \(roleName(smallBlindIndex)). BB: \(roleName(bigBlindIndex)).")
        notifyTouchBar("Dealer: \(players[dealerIndex].name) | SB: \(roleName(smallBlindIndex)) \(smallBlindAmount) | BB: \(roleName(bigBlindIndex)) \(bigBlindAmount)")

        let startIndex = preFlopFirstActionIndex() ?? dealerIndex
        beginPreFlopBettingRound(startingAt: startIndex)
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

    private func advanceDealerButton() {
        dealerIndex = nextSeatedPlayerIndex(after: dealerIndex) ?? 0
    }

    private func postBlinds() {
        let seatedCount = players.filter { $0.chips > 0 }.count

        if seatedCount == 2 {
            smallBlindIndex = dealerIndex
            bigBlindIndex = nextSeatedPlayerIndex(after: dealerIndex)
        } else {
            smallBlindIndex = nextSeatedPlayerIndex(after: dealerIndex)
            if let sb = smallBlindIndex {
                bigBlindIndex = nextSeatedPlayerIndex(after: sb)
            }
        }

        if let sb = smallBlindIndex {
            let paid = payChips(from: players[sb], amount: smallBlindAmount)
            actionLog.append("\(players[sb].name) posts small blind \(paid).")
        }

        if let bb = bigBlindIndex {
            let paid = payChips(from: players[bb], amount: bigBlindAmount)
            highestBet = max(highestBet, players[bb].currentBet)
            actionLog.append("\(players[bb].name) posts big blind \(paid).")
        }

        highestBet = players.map { $0.currentBet }.max() ?? 0
        lastRaiseAmount = bigBlindAmount
    }

    private func preFlopFirstActionIndex() -> Int? {
        let seatedCount = players.filter { $0.chips > 0 }.count
        if seatedCount == 2 {
            return nextActionIndex(startingAt: smallBlindIndex ?? dealerIndex)
        }
        if let bb = bigBlindIndex {
            return nextActionIndex(startingAt: (bb + 1) % players.count)
        }
        return nextActionIndex(startingAt: 0)
    }

    private func postFlopFirstActionIndex() -> Int? {
        nextActionIndex(startingAt: (dealerIndex + 1) % players.count)
    }

    func availableActionsForHuman() -> [ActionOption] {
        guard isHumanTurn else { return [] }
        let callAmount = callAmountForHuman
        if callAmount == 0 {
            return [.check, .raise, .allIn, .fold]
        } else {
            return [.call, .raise, .allIn, .fold]
        }
    }

    func performHumanAction(_ action: PokerAction) {
        guard isHumanTurn else { return }
        apply(action, toPlayerAt: 0)
        currentPlayerIndex = nextActionIndex(after: 0) ?? 0
        delegate?.gameEngineDidUpdate(self)
        continueActionLoop()
    }

    private func beginPreFlopBettingRound(startingAt index: Int) {
        actedThisRound = []
        currentPlayerIndex = nextActionIndex(startingAt: index) ?? 0
        delegate?.gameEngineDidUpdate(self)
        continueActionLoop()
    }

    private func beginBettingRound(startingAt index: Int) {
        highestBet = 0
        lastRaiseAmount = bigBlindAmount
        actedThisRound = []
        for player in players {
            player.currentBet = 0
        }
        currentPlayerIndex = nextActionIndex(startingAt: index) ?? 0
        delegate?.gameEngineDidUpdate(self)
        continueActionLoop()
    }

    private func continueActionLoop() {
        while phase != .gameOver && phase != .showdown {
            if players.filter({ $0.isInHand }).count == 1 {
                awardPotToLastStanding()
                return
            }

            if shouldRunOutBoardToShowdown() {
                runOutBoardAndShowdown()
                return
            }

            if bettingRoundIsComplete() {
                finishBettingRound()
                return
            }

            guard let index = nextActionIndex(startingAt: currentPlayerIndex) else {
                finishBettingRound()
                return
            }

            currentPlayerIndex = index

            let player = players[index]
            if player.type == .human {
                notifyTouchBar(actionPromptText())
                delegate?.gameEngineDidUpdate(self)
                return
            }

            let action = decideAIAction(for: player)
            apply(action, toPlayerAt: index)
            currentPlayerIndex = nextActionIndex(after: index) ?? 0
            delegate?.gameEngineDidUpdate(self)
        }
    }

    private func shouldRunOutBoardToShowdown() -> Bool {
        let playersInHand = players.filter { $0.isInHand }
        let playersWhoCanStillBet = playersInHand.filter { $0.canAct }

        guard playersInHand.count >= 2 else { return false }
        guard playersWhoCanStillBet.count <= 1 else { return false }

        // Important:
        // If one player still needs to call an all-in or raise, they must still act.
        // Only run out the board when the remaining active player has already matched the current highest bet.
        return playersWhoCanStillBet.allSatisfy { $0.currentBet >= highestBet }
    }

    private func runOutBoardAndShowdown() {
        actionLog.append("No more betting action possible. Running out the board.")

        switch phase {
        case .preFlop:
            dealFlop()
            dealTurn()
            dealRiver()
        case .flop:
            dealTurn()
            dealRiver()
        case .turn:
            dealRiver()
        case .river:
            break
        case .showdown, .gameOver:
            return
        }

        showdown()
    }

    private func bettingRoundIsComplete() -> Bool {
        let activeIndexes = players.indices.filter { players[$0].canAct }
        if activeIndexes.isEmpty { return true }

        for index in activeIndexes {
            let player = players[index]
            if !actedThisRound.contains(index) { return false }
            if player.currentBet < highestBet { return false }
        }
        return true
    }

    private func nextSeatedPlayerIndex(after index: Int) -> Int? {
        guard !players.isEmpty else { return nil }
        for offset in 1...players.count {
            let candidate = (index + offset + players.count) % players.count
            if players[candidate].chips > 0 {
                return candidate
            }
        }
        return nil
    }

    private func nextActionIndex(startingAt start: Int) -> Int? {
        guard !players.isEmpty else { return nil }
        for offset in 0..<players.count {
            let index = (start + offset + players.count) % players.count
            if players[index].canAct { return index }
        }
        return nil
    }

    private func nextActionIndex(after index: Int) -> Int? {
        nextActionIndex(startingAt: (index + 1) % players.count)
    }

    private func decideAIAction(for player: PokerPlayer) -> PokerAction {
        let callAmount = max(0, highestBet - player.currentBet)
        let strength = estimateStrength(for: player)
        let random = Double.random(in: 0...1)
        let bluffChance: Double

        switch player.name {
        case "AI 1": bluffChance = 0.10
        case "AI 2": bluffChance = 0.22
        default: bluffChance = 0.07
        }

        if callAmount == 0 {
            if player.chips <= lastRaiseAmount {
                return random < 0.15 ? .allIn : .check
            }
            if strength > 0.78 && random < 0.50 {
                return .raise(preferredAIRaise(for: player, callAmount: 0))
            }
            if random < bluffChance {
                return .raise(preferredAIRaise(for: player, callAmount: 0))
            }
            if random > 0.985 {
                return .allIn
            }
            return .check
        }

        if callAmount >= player.chips {
            if strength > 0.70 || random < bluffChance {
                return .call
            }
            return .fold
        }

        if strength > 0.84 && random < 0.45 {
            return .raise(preferredAIRaise(for: player, callAmount: callAmount))
        }
        if random < bluffChance {
            return .raise(preferredAIRaise(for: player, callAmount: callAmount))
        }
        if strength < 0.34 && random < 0.55 {
            return .fold
        }
        return .call
    }

    private func preferredAIRaise(for player: PokerPlayer, callAmount: Int) -> Int {
        let minRaise = max(lastRaiseAmount, minimumRaise)
        let options = [minRaise, minRaise * 2, minRaise * 4]
        let affordable = options.filter { callAmount + $0 < player.chips }
        return affordable.randomElement() ?? max(0, player.chips - callAmount)
    }

    private func estimateStrength(for player: PokerPlayer) -> Double {
        if communityCards.count >= 3 {
            let rank = HandEvaluator.evaluate(player.hand + communityCards)
            return Double(rank.category.rawValue) / 10.0
        }

        let ranks = player.hand.map { $0.rank.rawValue }.sorted(by: >)
        guard ranks.count == 2 else { return 0.3 }
        let suited = player.hand[0].suit == player.hand[1].suit

        if ranks[0] == ranks[1] {
            return ranks[0] >= 10 ? 0.88 : 0.66
        }
        if ranks[0] >= 14 && ranks[1] >= 10 {
            return suited ? 0.78 : 0.72
        }
        if ranks[0] >= 12 && ranks[1] >= 10 {
            return suited ? 0.66 : 0.58
        }
        if abs(ranks[0] - ranks[1]) == 1 {
            return suited ? 0.52 : 0.44
        }
        return min(0.60, Double(ranks[0] + ranks[1]) / 32.0)
    }

    private func apply(_ action: PokerAction, toPlayerAt index: Int) {
        let player = players[index]
        guard player.canAct else { return }

        switch action {
        case .check:
            if highestBet > player.currentBet {
                let need = highestBet - player.currentBet
                let paid = payChips(from: player, amount: need)
                actionLog.append("\(player.name) calls \(paid).")
                notifyTouchBar("\(boardText) | \(player.name) calls \(paid) | Pot: \(pot)")
            } else {
                actionLog.append("\(player.name) checks.")
                notifyTouchBar("\(boardText) | \(player.name) checks | Pot: \(pot)")
            }
            actedThisRound.insert(index)

        case .call:
            let need = max(0, highestBet - player.currentBet)
            let paid = payChips(from: player, amount: need)
            if player.status == .allIn && paid < need {
                actionLog.append("\(player.name) calls all-in for \(paid).")
                notifyTouchBar("\(boardText) | \(player.name) calls all-in \(paid) | Pot: \(pot)")
            } else {
                actionLog.append("\(player.name) calls \(paid).")
                notifyTouchBar("\(boardText) | \(player.name) calls \(paid) | Pot: \(pot)")
            }
            actedThisRound.insert(index)

        case .raise(let raiseBy):
            let callAmount = max(0, highestBet - player.currentBet)
            let requiredRaise = max(lastRaiseAmount, minimumRaise)
            let raisePart = max(requiredRaise, raiseBy)
            let totalNeeded = callAmount + raisePart
            let previousHighest = highestBet
            let paid = payChips(from: player, amount: totalNeeded)

            if player.currentBet > highestBet {
                let actualRaise = player.currentBet - previousHighest
                highestBet = player.currentBet

                if actualRaise >= requiredRaise {
                    lastRaiseAmount = actualRaise
                    actedThisRound = [index]
                    actionLog.append("\(player.name) raises to \(player.currentBet).")
                    notifyTouchBar("\(boardText) | \(player.name) raises to \(player.currentBet) | Pot: \(pot)")
                } else {
                    actedThisRound.insert(index)
                    actionLog.append("\(player.name) goes all-in to \(player.currentBet).")
                    notifyTouchBar("\(boardText) | \(player.name) all-in to \(player.currentBet) | Pot: \(pot)")
                }
            } else {
                actionLog.append("\(player.name) calls all-in for \(paid).")
                notifyTouchBar("\(boardText) | \(player.name) calls all-in | Pot: \(pot)")
                actedThisRound.insert(index)
            }

        case .allIn:
            let requiredRaise = max(lastRaiseAmount, minimumRaise)
            let previousHighest = highestBet
            let paid = payChips(from: player, amount: player.chips)

            if player.currentBet > highestBet {
                let actualRaise = player.currentBet - previousHighest
                highestBet = player.currentBet

                if actualRaise >= requiredRaise {
                    lastRaiseAmount = actualRaise
                    actedThisRound = [index]
                    actionLog.append("\(player.name) goes all-in to \(player.currentBet).")
                    notifyTouchBar("\(boardText) | \(player.name) all-in to \(player.currentBet) | Pot: \(pot)")
                } else {
                    actedThisRound.insert(index)
                    actionLog.append("\(player.name) goes all-in to \(player.currentBet).")
                    notifyTouchBar("\(boardText) | \(player.name) all-in to \(player.currentBet) | Pot: \(pot)")
                }
            } else {
                actionLog.append("\(player.name) goes all-in for \(paid).")
                notifyTouchBar("\(boardText) | \(player.name) all-in for \(paid) | Pot: \(pot)")
                actedThisRound.insert(index)
            }

        case .fold:
            player.status = .folded
            actionLog.append("\(player.name) folds.")
            notifyTouchBar("\(boardText) | \(player.name) folds | Pot: \(pot)")
            actedThisRound.insert(index)
        }
    }

    @discardableResult
    private func payChips(from player: PokerPlayer, amount: Int) -> Int {
        let paid = min(max(0, amount), player.chips)
        player.chips -= paid
        player.currentBet += paid
        player.totalCommitted += paid
        pot += paid

        if player.chips == 0 && player.status == .active {
            player.status = .allIn
        }

        return paid
    }

    private func finishBettingRound() {
        if players.filter({ $0.isInHand }).count == 1 {
            awardPotToLastStanding()
            return
        }

        switch phase {
        case .preFlop:
            dealFlop()
            phase = .flop
            notifyTouchBar("\(boardText) | Flop dealt")
            beginBettingRound(startingAt: postFlopFirstActionIndex() ?? 0)

        case .flop:
            dealTurn()
            phase = .turn
            notifyTouchBar("\(boardText) | Turn dealt")
            beginBettingRound(startingAt: postFlopFirstActionIndex() ?? 0)

        case .turn:
            dealRiver()
            phase = .river
            notifyTouchBar("\(boardText) | River dealt")
            beginBettingRound(startingAt: postFlopFirstActionIndex() ?? 0)

        case .river:
            showdown()

        case .showdown, .gameOver:
            return
        }
    }

    private func dealFlop() {
        deck.burnCard()
        for _ in 0..<3 {
            if let card = deck.draw() {
                communityCards.append(card)
            }
        }
        actionLog.append("Flop: \(communityCards.map { $0.displayText }.joined(separator: " ")).")
    }

    private func dealTurn() {
        deck.burnCard()
        if let card = deck.draw() {
            communityCards.append(card)
        }
        actionLog.append("Turn: \(communityCards.last?.displayText ?? "--").")
    }

    private func dealRiver() {
        deck.burnCard()
        if let card = deck.draw() {
            communityCards.append(card)
        }
        actionLog.append("River: \(communityCards.last?.displayText ?? "--").")
    }

    private func awardPotToLastStanding() {
        guard let winner = players.first(where: { $0.isInHand }) else { return }
        winner.chips += pot
        actionLog.append("\(winner.name) wins \(pot).")
        notifyTouchBar("\(winner.name) wins pot \(pot) | R: Next Hand")
        pot = 0
        _ = checkGameOver()
        delegate?.gameEngineDidUpdate(self)
    }

    private func showdown() {
        phase = .showdown
        let activePlayers = players.filter { $0.isInHand }
        guard !activePlayers.isEmpty else { return }

        let ranksByName: [String: HandRank] = Dictionary(uniqueKeysWithValues: activePlayers.map {
            ($0.name, HandEvaluator.evaluate($0.hand + communityCards))
        })

        let revealText = activePlayers.map { "\($0.name): \($0.handText)" }.joined(separator: " | ")
        notifyTouchBar("\(boardText) | \(revealText)")

        actionLog.append("Showdown.")
        for player in activePlayers {
            if let rank = ranksByName[player.name] {
                actionLog.append("\(player.name): \(player.handText) -> \(rank.description)")
            }
        }

        distributePots(ranksByName: ranksByName)
        pot = 0

        _ = checkGameOver()
        delegate?.gameEngineDidUpdate(self)
    }

    private func distributePots(ranksByName: [String: HandRank]) {
        let contributionLevels = Array(Set(players.map { $0.totalCommitted }.filter { $0 > 0 })).sorted()
        var previousLevel = 0
        var totalAwarded = 0

        for level in contributionLevels {
            let contributors = players.filter { $0.totalCommitted >= level }
            let sidePot = (level - previousLevel) * contributors.count
            previousLevel = level
            guard sidePot > 0 else { continue }

            let contenders = contributors.filter { $0.isInHand && ranksByName[$0.name] != nil }
            guard !contenders.isEmpty else { continue }

            let bestRank = contenders.compactMap { ranksByName[$0.name] }.max()!
            let winners = contenders.filter { player in
                guard let rank = ranksByName[player.name] else { return false }
                return !(rank < bestRank) && !(bestRank < rank)
            }

            let share = sidePot / winners.count
            let remainder = sidePot % winners.count

            for (offset, winner) in winners.enumerated() {
                winner.chips += share + (offset < remainder ? 1 : 0)
            }

            totalAwarded += sidePot
            actionLog.append("Pot \(sidePot) won by \(winners.map { $0.name }.joined(separator: ", ")).")
        }

        if totalAwarded == 0, let winner = players.filter({ $0.isInHand }).first {
            winner.chips += pot
            actionLog.append("\(winner.name) wins \(pot).")
        }
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

    private func roleName(_ index: Int?) -> String {
        guard let index = index, players.indices.contains(index) else {
            return "--"
        }
        return players[index].name
    }

    private func roleText(for index: Int) -> String {
        var roles: [String] = []

        if index == dealerIndex {
            roles.append("D")
        }
        if index == smallBlindIndex {
            roles.append("SB")
        }
        if index == bigBlindIndex {
            roles.append("BB")
        }

        return roles.isEmpty ? "" : " [\(roles.joined(separator: "/"))]"
    }

    func actionPromptText() -> String {
        let callAmount = callAmountForHuman
        if callAmount > 0 {
            return "\(boardText) | You: \(human.handText) | Need: \(callAmount) | Pot: \(pot)"
        }
        return "\(boardText) | You: \(human.handText) | Pot: \(pot)"
    }

    func mainScreenText() -> String {
        let playersText = players.indices.map { index -> String in
            let player = players[index]
            let status: String

            switch player.status {
            case .active:
                status = "Active"
            case .folded:
                status = "Folded"
            case .allIn:
                status = "All-in"
            case .busted:
                status = "Busted"
            }

            let hand = player.type == .human || phase == .showdown || phase == .gameOver ? player.handText : "?? ??"
            return "\(player.name)\(roleText(for: index)): \(player.chips) chips | Street Bet: \(player.currentBet) | Hand Total: \(player.totalCommitted) | \(status) | Hand: \(hand)"
        }.joined(separator: "\n")

        let lastLog = actionLog.suffix(16).joined(separator: "\n")

        if phase == .gameOver {
            let title = gameOverReason == .allAIOutOfChips ? "You Win!" : "Game Over"
            return """
            \(title)

            Final Chips:
            \(players.map { "\($0.name): \($0.chips)" }.joined(separator: "\n"))

            Press R to restart or Q to quit.
            """
        }

        let turnText: String
        if phase == .showdown {
            turnText = "Hand complete. Press R for next hand."
        } else if players.indices.contains(currentPlayerIndex) {
            let current = players[currentPlayerIndex]
            turnText = current.type == .human && current.canAct ? "Your turn" : "Current: \(current.name)"
        } else {
            turnText = "Resolving..."
        }

        return """
        TouchBar Texas Holdem

        Phase: \(phase.rawValue)    \(turnText)
        Dealer: \(roleName(dealerIndex))    SB: \(roleName(smallBlindIndex)) \(smallBlindAmount)    BB: \(roleName(bigBlindIndex)) \(bigBlindAmount)
        \(boardText)
        Pot: \(pot)
        Current Highest Street Bet: \(highestBet)
        Minimum Raise: \(max(lastRaiseAmount, minimumRaise))

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
