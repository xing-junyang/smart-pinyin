//
//  InputController.swift
//  smart pinyin
//
//  macOS Input Method controller with LLM-powered next-token prediction.
//  Handles key events, composition, candidate display, and prediction UI.
//

import InputMethodKit
import Cocoa

final class InputController: IMKInputController {

    // MARK: - LLM Predictor

    private let predictor = LLMPredictor()
    private let candidateWindow = CandidateWindow()

    // MARK: - Composition State

    /// Current composition (raw) string – what the user is typing.
    private var compositionBuffer: String = ""

    /// Committed text so far in the current session.
    private var committedText: String = ""

    /// Whether we are in the middle of a composition.
    private var isComposing: Bool = false

    // MARK: - IMKInputController Overrides

    override func activateServer(_ sender: Any!) {
        NSLog("🟢 SmartPinyin activateServer")
        super.activateServer(sender)

        // Start loading the model asynchronously
        Task { @MainActor [weak self] in
            await self?.predictor.loadModel()
            NSLog("🟢 SmartPinyin model loaded")
        }
    }

    override func deactivateServer(_ sender: Any!) {
        NSLog("🔴 SmartPinyin deactivateServer")
        predictionWorkItem?.cancel()
        candidateWindow.orderOut(nil)
        super.deactivateServer(sender)
    }

    // MARK: - Event Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else { return false }

        switch event.type {
        case .keyDown:
            return handleKeyDown(event, client: sender)
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: NSEvent, client sender: Any!) -> Bool {
        let characters = event.characters ?? ""
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ---- Candidate window navigation ----
        if candidateWindow.isVisible {
            switch keyCode {
            case 125:  // Down arrow
                candidateWindow.moveDown()
                return true
            case 126:  // Up arrow
                candidateWindow.moveUp()
                return true
            case 36:   // Return
                candidateWindow.confirmSelection()
                return true
            case 53:   // Escape
                candidateWindow.orderOut(nil)
                return true
            default:
                break
            }
        }

        // ---- Handle composition ----
        // If there are no command/control modifiers, process as text input
        if modifiers.isEmpty || modifiers == .shift || modifiers == .capsLock {
            return handleTextInput(characters: characters, keyCode: keyCode, client: sender)
        }

        // For other modifiers, let system handle it
        return false
    }

    private func handleTextInput(characters: String, keyCode: UInt16, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }

        switch keyCode {
        case 51:  // Delete / Backspace
            if isComposing && !compositionBuffer.isEmpty {
                compositionBuffer.removeLast()
                if compositionBuffer.isEmpty {
                    isComposing = false
                    client.setMarkedText("", selectionRange: NSRange(), replacementRange: NSRange())
                } else {
                    client.setMarkedText(
                        compositionBuffer,
                        selectionRange: NSRange(location: compositionBuffer.utf16.count, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: 0)
                    )
                }
                triggerPrediction()
                return true
            }
            return false

        case 36:  // Return – commit current composition
            if isComposing {
                commitComposition(client: client)
                return true
            }
            return false

        case 49:  // Space – commit + add space
            if isComposing {
                commitComposition(client: client)
                client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
                committedText += " "
                triggerPrediction()
                return true
            }
            // Not composing: let system handle for other uses or pass through
            return false

        case 48:  // Tab – accept first prediction
            if candidateWindow.isVisible, let pred = predictor.predictions.first {
                insertPrediction(pred, client: client)
                return true
            }
            return false

        default:
            // Printable characters
            if characters.isEmpty { return false }

            let printable = characters.filter { !$0.isASCII || ($0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " ") }
            if printable.isEmpty { return false }

            if !isComposing {
                isComposing = true
                compositionBuffer = ""
            }

            compositionBuffer += printable
            client.setMarkedText(
                compositionBuffer,
                selectionRange: NSRange(location: compositionBuffer.utf16.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )

            triggerPrediction()
            return true
        }
    }

    // MARK: - Composition

    private func commitComposition(client: IMKTextInput) {
        guard !compositionBuffer.isEmpty else { return }

        let text = compositionBuffer
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += text
        compositionBuffer = ""
        isComposing = false
        candidateWindow.orderOut(nil)
    }

    private func insertPrediction(_ prediction: TokenPrediction, client: IMKTextInput) {
        // Commit any pending composition first
        if isComposing {
            commitComposition(client: client)
        }

        client.insertText(prediction.text, replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += prediction.text
        candidateWindow.orderOut(nil)
        triggerPrediction()
    }

    // MARK: - Prediction

    /// Debounce interval in seconds. Rapid typing cancels the previous
    /// prediction and schedules a new one, so the model only runs when
    /// the user pauses briefly.
    private let predictionDebounce: TimeInterval = 0.15

    private var predictionWorkItem: DispatchWorkItem?

    private func triggerPrediction() {
        predictionWorkItem?.cancel()

        let fullContext = committedText + compositionBuffer
        guard !fullContext.isEmpty else {
            candidateWindow.orderOut(nil)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.predictor.predict(nextTo: fullContext)

                if self.predictor.predictions.isEmpty {
                    self.candidateWindow.orderOut(nil)
                } else {
                    self.candidateWindow.updatePredictionsWithStorage(self.predictor.predictions)
                    self.candidateWindow.onSelect = { [weak self] pred in
                        guard let self,
                              let client = self.client() as? IMKTextInput else { return }
                        self.insertPrediction(pred, client: client)
                    }
                    self.showCandidateWindow()
                }
            }
        }

        predictionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + predictionDebounce, execute: workItem)
    }

    private func showCandidateWindow() {
        // Use a reasonable default position near the bottom of the screen.
        // IMK does not give exact caret coordinates, so we approximate.
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let point = NSMakePoint(
            screenRect.midX - 175,  // center horizontally (window is 350 wide)
            screenRect.minY + 120   // near bottom but above Dock
        )

        candidateWindow.position(near: point, on: screen)
        candidateWindow.orderFront(nil)
    }

    // MARK: - Candidate Support (for traditional input method compatibility)

    override func candidates(_ sender: Any!) -> [Any]! {
        // Return LLM predictions as candidates when requested
        return predictor.predictions.map { $0.text }
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = client() as? IMKTextInput,
              let text = candidateString?.string else { return }
        insertPrediction(TokenPrediction(text: text, probability: 0, tokenID: 0), client: client)
    }

    override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        // Optional: preview the candidate
    }
}

