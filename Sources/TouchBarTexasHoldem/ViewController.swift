import Cocoa

final class ViewController: NSViewController, NSTouchBarDelegate, GameEngineDelegate {
    private let engine = GameEngine()
    private let mainLabel = NSTextField(labelWithString: "")
    private let touchBarLabel = NSTextField(labelWithString: "")

    private var selectedActionIndex = 0
    private let raiseOptions = [50, 100, 200, 500]
    private var raiseAmount = 50
    private var latestTouchBarMessage = "Welcome | Press R to start"

    override var acceptsFirstResponder: Bool { true }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        engine.delegate = self
        setupMainLabel()
        engine.startNewGame()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(self)
    }

    private func setupMainLabel() {
        mainLabel.frame = view.bounds.insetBy(dx: 24, dy: 24)
        mainLabel.autoresizingMask = [.width, .height]
        mainLabel.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        mainLabel.alignment = .left
        mainLabel.lineBreakMode = .byWordWrapping
        mainLabel.maximumNumberOfLines = 0
        view.addSubview(mainLabel)
    }

    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.display]
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == .display else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        touchBarLabel.stringValue = latestTouchBarMessage
        touchBarLabel.alignment = .center
        touchBarLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        touchBarLabel.lineBreakMode = .byTruncatingTail
        item.view = touchBarLabel
        return item
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // left
            moveSelectionLeft()
        case 124: // right
            moveSelectionRight()
        case 125: // down
            decreaseRaise()
        case 126: // up
            increaseRaise()
        case 36, 76: // return / enter
            confirmSelectedAction()
        case 15: // R
            if engine.phase == .gameOver {
                engine.startNewGame()
            } else {
                engine.startNewHand()
            }
        case 12: // Q
            NSApplication.shared.terminate(nil)
        case 53: // Esc
            if engine.phase == .gameOver {
                NSApplication.shared.terminate(nil)
            } else {
                engine.performHumanAction(.fold)
            }
        default:
            super.keyDown(with: event)
        }
    }

    private var currentActions: [ActionOption] {
        engine.availableActionsForHuman()
    }

    private var selectedAction: ActionOption {
        let actions = currentActions
        if selectedActionIndex >= actions.count { selectedActionIndex = 0 }
        return actions[selectedActionIndex]
    }

    private func moveSelectionLeft() {
        guard engine.phase != .gameOver else { return }
        let count = currentActions.count
        selectedActionIndex = (selectedActionIndex - 1 + count) % count
        updateTouchBarActionText()
    }

    private func moveSelectionRight() {
        guard engine.phase != .gameOver else { return }
        let count = currentActions.count
        selectedActionIndex = (selectedActionIndex + 1) % count
        updateTouchBarActionText()
    }

    private func increaseRaise() {
        guard selectedAction == .raise else { return }
        if let index = raiseOptions.firstIndex(of: raiseAmount), index < raiseOptions.count - 1 {
            raiseAmount = raiseOptions[index + 1]
        }
        updateTouchBarActionText()
    }

    private func decreaseRaise() {
        guard selectedAction == .raise else { return }
        if let index = raiseOptions.firstIndex(of: raiseAmount), index > 0 {
            raiseAmount = raiseOptions[index - 1]
        }
        updateTouchBarActionText()
    }

    private func confirmSelectedAction() {
        guard engine.phase != .gameOver else { return }
        switch selectedAction {
        case .check:
            engine.performHumanAction(.check)
        case .call:
            engine.performHumanAction(.call)
        case .raise:
            engine.performHumanAction(.raise(raiseAmount))
        case .allIn:
            engine.performHumanAction(.allIn)
        case .fold:
            engine.performHumanAction(.fold)
        }
        selectedActionIndex = 0
        updateTouchBarActionText()
    }

    private func actionBarText() -> String {
        if engine.phase == .gameOver {
            return latestTouchBarMessage
        }

        let callAmount = engine.callAmountForHuman
        let actions = currentActions
        let actionText = actions.enumerated().map { index, action in
            var title = action.title
            if action == .call { title = "Call \(callAmount)" }
            if action == .raise { title = "Raise \(raiseAmount)" }
            return index == selectedActionIndex ? "> \(title) <" : title
        }.joined(separator: "   ")

        return "\(engine.boardText) | You: \(engine.human.handText) | Pot: \(engine.pot) | \(actionText)"
    }

    private func updateTouchBarActionText() {
        latestTouchBarMessage = actionBarText()
        touchBarLabel.stringValue = latestTouchBarMessage
        mainLabel.stringValue = engine.mainScreenText()
    }

    func gameEngineDidUpdate(_ engine: GameEngine) {
        mainLabel.stringValue = engine.mainScreenText()
        updateTouchBarActionText()
    }

    func gameEngine(_ engine: GameEngine, didShowTouchBarMessage message: String) {
        latestTouchBarMessage = message
        touchBarLabel.stringValue = message
    }
}

extension NSTouchBarItem.Identifier {
    static let display = NSTouchBarItem.Identifier("com.touchbartexasholdem.display")
}
