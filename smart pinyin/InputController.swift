//
//  InputController.swift
//  smart pinyin
//
//  macOS Input Method controller with:
//  - Pinyin → Chinese character conversion
//  - LLM-powered next-token prediction
//  - Debug information window
//

import InputMethodKit
import Cocoa

final class InputController: IMKInputController {

    // MARK: - Core

    private let predictor = LLMPredictor()
    private let candidateWindow = CandidateWindow()
    private let debugWindow = DebugWindow()

    // MARK: - Composition State

    private var compositionBuffer: String = ""
    private var committedText: String = ""
    private var isComposing: Bool = false

    private var isPinyinMode: Bool = false
    private var pinyinCandidates: [PinyinCandidate] = []
    private var pinyinParsedSegments: [String] = []
    private var selectedChinese: String = ""

    // MARK: - Metrics

    private var lastPredictionLatency: TimeInterval = 0
    private var lastTokenCount: Int = 0

    // MARK: - IMKInputController

    override func activateServer(_ sender: Any!) {
        NSLog("🟢 SmartPinyin activateServer")
        super.activateServer(sender)
        resetState()
        debugWindow.orderFront(nil)
        refreshDebug()

        candidateWindow.showLoading(modelName: "model", progress: 0)
        candidateWindow.position(near: NSPoint(x: NSScreen.main?.visibleFrame.midX ?? 400, y: 200),
                                 on: NSScreen.main)
        candidateWindow.orderFront(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.predictor.loadModel()
            while true {
                switch self.predictor.state {
                case .loading(let p):
                    self.candidateWindow.showLoading(modelName: self.predictor.modelName, progress: p)
                    self.refreshDebug()
                case .loaded:
                    self.candidateWindow.hideLoading()
                    self.refreshDebug()
                    return
                case .error(let m):
                    self.candidateWindow.showLoading(modelName: "Error: \(m)", progress: 0)
                    self.refreshDebug()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.candidateWindow.hideLoading()
                    return
                case .unloaded: break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    override func deactivateServer(_ sender: Any!) {
        predictionWorkItem?.cancel()
        predictionWorkItem = nil
        candidateWindow.orderOut(nil)
        debugWindow.orderOut(nil)
        resetState()
        super.deactivateServer(sender)
    }

    private func resetState() {
        committedText = ""
        compositionBuffer = ""
        isComposing = false
        isPinyinMode = false
        pinyinCandidates = []
        pinyinParsedSegments = []
        selectedChinese = ""
        lastKnownCursorPoint = nil
        lastKnownScreen = nil
    }

    // MARK: - Event Handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown else { return false }
        return handleKeyDown(event, client: sender)
    }

    private func handleKeyDown(_ event: NSEvent, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }
        let keyCode = event.keyCode
        let chars = event.characters ?? ""
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ── Shortcuts (check before modifier filter) ──
        if mods == [.control, .shift] {
            switch keyCode {
            case 0:   // Ctrl+Shift+A → add selected text to context
                addSelectionToContext(client: client)
                return true
            case 7:   // Ctrl+Shift+X → clear context
                clearContext(client: client)
                return true
            default: break
            }
        }

        if !mods.isEmpty, !mods.isSubset(of: [.shift, .capsLock, .numericPad, .function]) {
            return false
        }

        // Candidate window nav (only when not loading)
        if candidateWindow.isVisible, !candidateWindow.isShowingLoading {
            switch keyCode {
            case 125: candidateWindow.moveDown(); return true
            case 126: candidateWindow.moveUp(); return true
            case 36:  candidateWindow.confirmSelection(); return true
            case 53:  candidateWindow.orderOut(nil); return true
            default: break
            }
        }

        // Number keys 1-9 → select pinyin candidate
        if isPinyinMode, !pinyinCandidates.isEmpty, let n = Int(chars), n >= 1, n <= 9 {
            let idx = n - 1
            if idx < pinyinCandidates.count {
                selectPinyinCandidate(at: idx, client: client)
                return true
            }
        }

        // Special keys
        switch keyCode {
        case 51: return handleBackspace(client: client)
        case 36: return handleReturn(client: client)
        case 49: return handleSpace(client: client)
        case 48:
            if let pred = predictor.predictions.first {
                insertPrediction(pred, client: client); return true
            }
            return false
        case 53:
            if isComposing { cancelComposition(client: client); return true }
            return false
        default: break
        }

        return handlePrintable(chars: chars, client: client)
    }

    // MARK: - Key Handlers

    private func handleBackspace(client: IMKTextInput) -> Bool {
        guard isComposing, !compositionBuffer.isEmpty else { return false }
        compositionBuffer.removeLast()
        if compositionBuffer.isEmpty {
            cancelComposition(client: client)
        } else {
            updateMarkedText(client: client)
            parsePinyinIfNeeded()
            refreshDebug()
        }
        return true
    }

    private func handleReturn(client: IMKTextInput) -> Bool {
        if isComposing { commitComposition(client: client); return true }
        return false
    }

    private func handleSpace(client: IMKTextInput) -> Bool {
        if isPinyinMode, !pinyinCandidates.isEmpty {
            selectPinyinCandidate(at: 0, client: client)
            return true
        }
        if isComposing { commitComposition(client: client) }
        client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += " "
        triggerPrediction()
        refreshDebug()
        return true
    }

    private func handlePrintable(chars: String, client: IMKTextInput) -> Bool {
        let filtered = chars.filter { ch in
            if ch.isASCII { return ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " || ch == "\t" }
            return true
        }
        guard !filtered.isEmpty else { return false }

        if !isComposing {
            isComposing = true
            compositionBuffer = ""
            selectedChinese = ""
        }
        compositionBuffer += filtered

        let hasNonPinyin = compositionBuffer.contains { ch in
            ch.isASCII && (!ch.isLowercase || (!ch.isLetter && ch != "'"))
        }
        isPinyinMode = !hasNonPinyin

        parsePinyinIfNeeded()
        updateMarkedText(client: client)
        triggerPrediction()
        refreshDebug()
        return true
    }

    // MARK: - Pinyin

    private func parsePinyinIfNeeded() {
        guard isPinyinMode else { pinyinCandidates = []; return }
        pinyinParsedSegments = PinyinEngine.segment(compositionBuffer)
        if let last = pinyinParsedSegments.last {
            pinyinCandidates = PinyinEngine.candidates(for: last)
        } else {
            pinyinCandidates = []
        }
        if !pinyinCandidates.isEmpty {
            candidateWindow.showPinyinCandidates(pinyinCandidates, context: compositionBuffer)
            candidateWindow.onSelectPinyin = { [weak self] idx in
                guard let self, let c = self.client() as? IMKTextInput else { return }
                self.selectPinyinCandidate(at: idx, client: c)
            }
        }
    }

    private func selectPinyinCandidate(at idx: Int, client: IMKTextInput) {
        guard idx < pinyinCandidates.count else { return }
        selectedChinese += pinyinCandidates[idx].character
        if let last = pinyinParsedSegments.last, compositionBuffer.hasSuffix(last) {
            compositionBuffer = String(compositionBuffer.dropLast(last.count))
        }
        if compositionBuffer.isEmpty {
            commitPinyinResult(client: client)
        } else {
            parsePinyinIfNeeded()
            updateMarkedText(client: client)
            refreshDebug()
        }
    }

    private func commitPinyinResult(client: IMKTextInput) {
        guard !selectedChinese.isEmpty else { return }
        client.insertText(selectedChinese, replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += selectedChinese
        compositionBuffer = ""
        selectedChinese = ""
        isComposing = false
        isPinyinMode = false
        pinyinCandidates = []
        candidateWindow.orderOut(nil)
        triggerPrediction()
        refreshDebug()
    }

    // MARK: - Marked Text

    private func updateMarkedText(client: IMKTextInput) {
        let display = (isPinyinMode && !selectedChinese.isEmpty)
            ? selectedChinese + compositionBuffer : compositionBuffer
        client.setMarkedText(display,
            selectionRange: NSRange(location: display.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Composition

    private func cancelComposition(client: IMKTextInput) {
        isComposing = false; isPinyinMode = false
        compositionBuffer = ""; selectedChinese = ""; pinyinCandidates = []
        client.setMarkedText("", selectionRange: NSRange(), replacementRange: NSRange())
        candidateWindow.orderOut(nil)
        refreshDebug()
    }

    private func commitComposition(client: IMKTextInput) {
        if isPinyinMode, !selectedChinese.isEmpty { commitPinyinResult(client: client); return }
        guard !compositionBuffer.isEmpty else { return }
        client.insertText(compositionBuffer, replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += compositionBuffer
        compositionBuffer = ""; isComposing = false; isPinyinMode = false; pinyinCandidates = []
        candidateWindow.orderOut(nil)
        refreshDebug()
    }

    private func insertPrediction(_ p: TokenPrediction, client: IMKTextInput) {
        if isComposing { commitComposition(client: client) }
        client.insertText(p.text, replacementRange: NSRange(location: NSNotFound, length: 0))
        committedText += p.text
        candidateWindow.orderOut(nil)
        triggerPrediction()
        refreshDebug()
    }

    // MARK: - Context Shortcuts

    /// Ctrl+Shift+A — grab the currently selected text in the client app
    /// and prepend it to the committed context so the LLM can use it.
    private func addSelectionToContext(client: IMKTextInput) {
        let sel = client.selectedRange()
        guard sel.length > 0,
              let selected = client.attributedSubstring(from: sel)?.string,
              !selected.isEmpty else { return }

        // Insert a separator then the selected text
        committedText = committedText + " " + selected + " "
        isComposing = false
        compositionBuffer = ""
        isPinyinMode = false
        pinyinCandidates = []
        candidateWindow.orderOut(nil)
        refreshDebug()
        NSLog("📎 Context added from selection: \(selected.prefix(50))…")
    }

    /// Ctrl+Shift+X — clear all accumulated context.
    private func clearContext(client: IMKTextInput) {
        committedText = ""
        compositionBuffer = ""
        isComposing = false
        isPinyinMode = false
        selectedChinese = ""
        pinyinCandidates = []
        lastKnownCursorPoint = nil
        lastKnownScreen = nil
        client.setMarkedText("", selectionRange: NSRange(), replacementRange: NSRange())
        candidateWindow.orderOut(nil)
        predictionWorkItem?.cancel()
        predictionWorkItem = nil
        predictor.resetContext()
        refreshDebug()
        NSLog("🧹 Context cleared")
    }

    // MARK: - Prediction

    private let predictionDebounce: TimeInterval = 0.2
    private var predictionWorkItem: DispatchWorkItem?

    private func triggerPrediction() {
        predictionWorkItem?.cancel()
        let ctx = committedText + compositionBuffer
        guard !ctx.isEmpty else { candidateWindow.orderOut(nil); refreshDebug(); return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let start = Date()
            Task { @MainActor in
                await self.predictor.predict(nextTo: ctx)
                self.lastPredictionLatency = Date().timeIntervalSince(start) * 1000
                self.lastTokenCount = self.predictor.predictions.count
                self.refreshDebug()
                let showingPinyin = self.isPinyinMode && !self.pinyinCandidates.isEmpty
                if !showingPinyin {
                    if self.predictor.predictions.isEmpty {
                        self.candidateWindow.orderOut(nil)
                    } else {
                        self.candidateWindow.updatePredictionsWithStorage(self.predictor.predictions)
                        self.candidateWindow.onSelect = { [weak self] pred in
                            guard let self, let c = self.client() as? IMKTextInput else { return }
                            self.insertPrediction(pred, client: c)
                        }
                        self.showCandidateWindow()
                    }
                }
            }
        }
        predictionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + predictionDebounce, execute: workItem)
    }

    private var lastKnownCursorPoint: NSPoint?
    private var lastKnownScreen: NSScreen?

    private func showCandidateWindow() {
        guard let client = client() as? IMKTextInput, let screen = NSScreen.main else { return }
        var lineRect = NSRect.zero
        let marked = client.markedRange()
        if marked.location != NSNotFound, marked.length > 0 {
            _ = client.attributes(forCharacterIndex: marked.location, lineHeightRectangle: &lineRect)
        }
        if lineRect == .zero {
            _ = client.attributes(forCharacterIndex: max(client.selectedRange().location, 0),
                                  lineHeightRectangle: &lineRect)
        }
        if lineRect == .zero {
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        }
        let point: NSPoint
        if lineRect != .zero {
            point = NSPoint(x: lineRect.minX, y: lineRect.minY)
            lastKnownCursorPoint = point; lastKnownScreen = screen
        } else if let c = lastKnownCursorPoint, let s = lastKnownScreen {
            point = c
        } else {
            point = NSPoint(x: screen.visibleFrame.midX - 175, y: screen.visibleFrame.minY + 120)
        }
        candidateWindow.position(near: point, on: screen)
        candidateWindow.orderFront(nil)
    }

    // MARK: - Debug

    private func refreshDebug() {
        let st: String = {
            switch predictor.state {
            case .unloaded: return "unloaded"
            case .loading(let p): return "loading \(Int(p*100))%"
            case .loaded: return "loaded"
            case .error(let m): return "error: \(m)"
            }
        }()
        let ctx = committedText + compositionBuffer
        let py = isPinyinMode
            ? "\(compositionBuffer) → \(pinyinParsedSegments.joined(separator: " "))"
            : "none"
        debugWindow.update(
            state: st, model: predictor.modelName, context: ctx,
            tokens: "\(lastTokenCount)",
            latency: String(format: "%.0f ms", lastPredictionLatency),
            pinyin: py,
            candidates: pinyinCandidates.prefix(5).map(\.character).joined()
        )
    }

    // MARK: - System Candidate Support

    override func candidates(_ sender: Any!) -> [Any]! { predictor.predictions.map(\.text) }
    override func candidateSelected(_ s: NSAttributedString!) {
        guard let c = client() as? IMKTextInput, let t = s?.string else { return }
        insertPrediction(TokenPrediction(text: t, probability: 0, tokenID: 0), client: c)
    }
    override func candidateSelectionChanged(_ s: NSAttributedString!) {}
}
