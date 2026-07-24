//
//  DebugWindow.swift
//  smart pinyin
//
//  A draggable floating window showing debug information:
//  current context, model info, token count, latency, etc.
//

import Cocoa

final class DebugWindow: NSWindow {

    // MARK: - Labels

    private let stackView: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 2
        sv.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let stateLabel    = makeLabel("State: —")
    private let modelLabel    = makeLabel("Model: —")
    private let contextLabel  = makeLabel("Context: —")
    private let tokensLabel   = makeLabel("Tokens: —")
    private let latencyLabel  = makeLabel("Latency: —")
    private let pinyinLabel   = makeLabel("Pinyin: —")
    private let candidateLabel = makeLabel("Candidates: —")

    private static func makeLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        tf.textColor = NSColor.labelColor
        tf.alignment = .left
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }

    // MARK: - Init

    convenience init() {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        // Rounded corners
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 8
        contentView?.layer?.masksToBounds = true
        contentView?.layer?.borderWidth = 0.5
        contentView?.layer?.borderColor = NSColor.separatorColor.cgColor

        // Title
        let title = DebugWindow.makeLabel("🐛 Debug Info")
        title.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

        guard let contentView = contentView else { return }
        contentView.addSubview(stackView)

        stackView.addArrangedSubview(title)
        stackView.addArrangedSubview(stateLabel)
        stackView.addArrangedSubview(modelLabel)
        stackView.addArrangedSubview(contextLabel)
        stackView.addArrangedSubview(tokensLabel)
        stackView.addArrangedSubview(latencyLabel)
        stackView.addArrangedSubview(pinyinLabel)
        stackView.addArrangedSubview(candidateLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 420),
        ])

        // Start at bottom-right
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let size = NSSize(width: 420, height: 210)
            setContentSize(size)
            setFrameOrigin(NSPoint(
                x: screenRect.maxX - size.width - 20,
                y: screenRect.minY + 60
            ))
        }
    }

    // MARK: - Update

    func update(
        state: String = "—",
        model: String = "—",
        context: String = "—",
        tokens: String = "—",
        latency: String = "—",
        pinyin: String = "—",
        candidates: String = "—"
    ) {
        stateLabel.stringValue = "State: \(state)"
        modelLabel.stringValue = "Model: \(model)"
        contextLabel.stringValue = "Context: \(context.truncated(to: 80))"
        tokensLabel.stringValue = "Tokens: \(tokens)"
        latencyLabel.stringValue = "Latency: \(latency)"
        pinyinLabel.stringValue = "Pinyin: \(pinyin)"
        candidateLabel.stringValue = "Candidates: \(candidates.truncated(to: 60))"
    }
}

private extension String {
    func truncated(to maxLen: Int) -> String {
        count > maxLen ? String(prefix(maxLen)) + "…" : self
    }
}
