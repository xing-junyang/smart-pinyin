//
//  DebugWindow.swift
//  smart pinyin
//
//  A draggable floating window showing debug information:
//  current context (multi-line), model info, token count, latency, etc.
//

import Cocoa

final class DebugWindow: NSWindow {

    // MARK: - Labels

    private let stackView: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 3
        sv.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let stateLabel    = makeLabel("State: —")
    private let modelLabel    = makeLabel("Model: —")
    private let tokensLabel   = makeLabel("Tokens: —")
    private let latencyLabel  = makeLabel("Latency: —")
    private let pinyinLabel   = makeLabel("Pinyin: —")
    private let candidateLabel = makeLabel("Candidates: —")

    // Multi-line context — NSTextView directly (no scroll wrapper needed
    // since the debug window itself is resizable).
    private let contextTextView: NSTextView = {
        let tv = NSTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        tv.textColor = NSColor.labelColor
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.drawsBackground = true
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private static func makeLabel(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        tf.textColor = NSColor.labelColor
        tf.alignment = .left
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }

    private static func makeHeader(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        tf.textColor = NSColor.secondaryLabelColor
        tf.alignment = .left
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
        let title = DebugWindow.makeHeader("🐛 Debug Info")
        let contextHeader = DebugWindow.makeHeader("Context:")

        guard let contentView = contentView else { return }

        contentView.addSubview(stackView)

        stackView.addArrangedSubview(title)
        stackView.addArrangedSubview(stateLabel)
        stackView.addArrangedSubview(modelLabel)
        stackView.addArrangedSubview(tokensLabel)
        stackView.addArrangedSubview(latencyLabel)
        stackView.addArrangedSubview(pinyinLabel)
        stackView.addArrangedSubview(candidateLabel)
        stackView.addArrangedSubview(contextHeader)
        stackView.addArrangedSubview(contextTextView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 520),
            contextTextView.widthAnchor.constraint(equalToConstant: 500),
            contextTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])

        // Start at bottom-right
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let size = NSSize(width: 520, height: 360)
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
        tokensLabel.stringValue = "Tokens: \(tokens)"
        latencyLabel.stringValue = "Latency: \(latency)"
        pinyinLabel.stringValue = "Pinyin: \(pinyin)"
        candidateLabel.stringValue = "Candidates: \(candidates)"

        // Multi-line context — show full text, auto-wrapped
        contextTextView.string = context.isEmpty ? "—" : context
    }
}
