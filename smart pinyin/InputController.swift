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
        committedText = ""
        compositionBuffer = ""

        // Show loading window immediately
        candidateWindow.showLoading(modelName: "model", progress: 0)
        candidateWindow.position(near: NSPoint(x: NSScreen.main?.visibleFrame.midX ?? 400, y: 200),
                                 on: NSScreen.main)
        candidateWindow.orderFront(nil)

        // Start model loading
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.predictor.loadModel()

            // Poll state to update UI until loaded or error
            var pollCount = 0
            while true {
                switch self.predictor.state {
                case .loading(let progress):
                    self.candidateWindow.showLoading(
                        modelName: self.predictor.modelName,
                        progress: progress
                    )
                case .loaded:
                    self.candidateWindow.hideLoading()
                    NSLog("🟢 SmartPinyin model loaded")
                    return
                case .error(let msg):
                    self.candidateWindow.showLoading(modelName: "Error: \(msg)", progress: 0)
                    // Keep error visible for 3 seconds then dismiss
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.candidateWindow.hideLoading()
                    return
                case .unloaded:
                    break
                }
                pollCount += 1
                try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms poll
            }
        }
    }

    override func deactivateServer(_ sender: Any!) {
        NSLog("🔴 SmartPinyin deactivateServer")
        predictionWorkItem?.cancel()
        predictionWorkItem = nil
        candidateWindow.orderOut(nil)
        committedText = ""
        compositionBuffer = ""
        isComposing = false
        lastKnownCursorPoint = nil
        lastKnownScreen = nil
        super.deactivateServer(sender)
    }

    // MARK: - Event Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else {
            return false
        }

        guard event.type == .keyDown else {
            return false
        }

        return handleKeyDown(event, client: sender)
    }

    private func handleKeyDown(_ event: NSEvent, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else {
            NSLog("⚠️ handleKeyDown: sender is not IMKTextInput, type=\(type(of: sender))")
            return false
        }

        let keyCode = event.keyCode
        let characters = event.characters ?? ""
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Pass through if Command, Control, or Option is held
        if !modifiers.isEmpty
            && !modifiers.isSubset(of: [.shift, .capsLock, .numericPad, .function])
        {
            return false
        }

        // ---- Candidate window navigation (when visible) ----
        if candidateWindow.isVisible {
            switch keyCode {
            case 125:  // ↓
                candidateWindow.moveDown(); return true
            case 126:  // ↑
                candidateWindow.moveUp(); return true
            case 36:   // Return — accept selected prediction
                candidateWindow.confirmSelection(); return true
            case 53:   // Escape — dismiss
                candidateWindow.orderOut(nil); return true
            default:
                // Not a nav key while window is visible — dismiss it, then process normally
                candidateWindow.orderOut(nil)
            }
        }

        // ---- Special keys ----
        switch keyCode {
        case 51:  // Delete / Backspace
            return handleBackspace(client: client)

        case 36:  // Return
            return handleReturn(client: client)

        case 49:  // Space
            return handleSpace(client: client)

        case 48:  // Tab — accept first prediction
            if let pred = predictor.predictions.first {
                insertPrediction(pred, client: client)
                return true
            }
            return false

        case 53:  // Escape — cancel composition
            if isComposing {
                cancelComposition(client: client)
                return true
            }
            return false

        default:
            break
        }

        // ---- Printable characters ----
        return handlePrintable(characters: characters, client: client)
    }

    // MARK: - Key Handlers

    private func handleBackspace(client: IMKTextInput) -> Bool {
        if isComposing && !compositionBuffer.isEmpty {
            compositionBuffer.removeLast()
            if compositionBuffer.isEmpty {
                cancelComposition(client: client)
            } else {
                client.setMarkedText(
                    compositionBuffer,
                    selectionRange: NSRange(location: compositionBuffer.utf16.count, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
                triggerPrediction()
            }
            return true
        }
        // Not composing: forward backspace to client
        return forwardKeyEventToClient(client)
    }

    private func handleReturn(client: IMKTextInput) -> Bool {
        if isComposing {
            commitComposition(client: client)
            return true
        }
        return false
    }

    private func handleSpace(client: IMKTextInput) -> Bool {
        if isComposing {
            commitComposition(client: client)
        }
        client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += " "
        triggerPrediction()
        return true
    }

    private func handlePrintable(characters: String, client: IMKTextInput) -> Bool {
        // Filter: keep only letters, numbers, punctuation, spaces
        let filtered = characters.filter { ch in
            if ch.isASCII {
                return ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " || ch == "\t"
            }
            return true  // Non-ASCII (CJK, etc.) — always keep
        }

        guard !filtered.isEmpty else {
            return false
        }

        if !isComposing {
            isComposing = true
            compositionBuffer = ""
        }

        compositionBuffer += filtered
        client.setMarkedText(
            compositionBuffer,
            selectionRange: NSRange(location: compositionBuffer.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        triggerPrediction()
        return true
    }

    // MARK: - Composition

    private func cancelComposition(client: IMKTextInput) {
        isComposing = false
        compositionBuffer = ""
        client.setMarkedText("", selectionRange: NSRange(), replacementRange: NSRange())
        candidateWindow.orderOut(nil)
    }

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
        if isComposing {
            commitComposition(client: client)
        }
        client.insertText(prediction.text, replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += prediction.text
        candidateWindow.orderOut(nil)
        triggerPrediction()
    }

    private func forwardKeyEventToClient(_ client: IMKTextInput) -> Bool {
        // Let the system handle the event for the client
        return false
    }

    // MARK: - Prediction

    private let predictionDebounce: TimeInterval = 0.2
    private var predictionWorkItem: DispatchWorkItem?

    private func triggerPrediction() {
        predictionWorkItem?.cancel()

        let context = committedText + compositionBuffer
        guard !context.isEmpty else {
            candidateWindow.orderOut(nil)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.predictor.predict(nextTo: context)
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

    /// Cached last-known cursor position so the candidate window stays
    /// near the text even when the client stops reporting coordinates.
    private var lastKnownCursorPoint: NSPoint?
    private var lastKnownScreen: NSScreen?

    private func showCandidateWindow() {
        guard let client = client() as? IMKTextInput,
              let screen = NSScreen.main else { return }

        var lineRect = NSRect.zero

        // 1) Try the marked (composition) range — this is where the user is looking.
        let marked = client.markedRange()
        if marked.location != NSNotFound, marked.length > 0 {
            _ = client.attributes(forCharacterIndex: marked.location,
                                  lineHeightRectangle: &lineRect)
        }

        // 2) Fallback: insertion point.
        if lineRect == .zero {
            let sel = client.selectedRange()
            let charIndex = max(sel.location, 0)
            _ = client.attributes(forCharacterIndex: charIndex,
                                  lineHeightRectangle: &lineRect)
        }

        // 3) Another fallback: try character index 0 (top of document).
        if lineRect == .zero {
            _ = client.attributes(forCharacterIndex: 0,
                                  lineHeightRectangle: &lineRect)
        }

        // Compute anchor point.
        let point: NSPoint
        if lineRect != .zero {
            // Show below the line, just past the left edge
            point = NSPoint(x: lineRect.minX, y: lineRect.minY)
            lastKnownCursorPoint = point
            lastKnownScreen = screen
        } else if let cached = lastKnownCursorPoint, let cachedScreen = lastKnownScreen {
            // Reuse the last good position so the window doesn't jump away
            point = cached
        } else {
            let screenRect = screen.visibleFrame
            point = NSPoint(x: screenRect.midX - 175, y: screenRect.minY + 120)
        }

        candidateWindow.position(near: point, on: screen)
        candidateWindow.orderFront(nil)
    }

    // MARK: - Candidate Support

    override func candidates(_ sender: Any!) -> [Any]! {
        return predictor.predictions.map(\.text)
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let client = client() as? IMKTextInput,
              let text = candidateString?.string else { return }
        insertPrediction(
            TokenPrediction(text: text, probability: 0, tokenID: 0),
            client: client
        )
    }

    override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {}
}

