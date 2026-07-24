//
//  CandidateWindow.swift
//  smart pinyin
//
//  A floating window that displays next-token predictions with probability bars.
//

import Cocoa

final class CandidateWindow: NSWindow {

    // MARK: - Subviews

    private let stackView: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 2
        sv.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let titleLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "Next Token Probability")
        tf.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        tf.textColor = NSColor.secondaryLabelColor
        tf.alignment = .left
        return tf
    }()

    private var barViews: [ProbabilityBarView] = []
    private var selectedIndex: Int = 0

    // MARK: - Init

    convenience init() {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .ignoresCycle]
        isReleasedWhenClosed = false

        // Rounded corners
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 10
        contentView?.layer?.masksToBounds = true

        // Border
        contentView?.layer?.borderWidth = 0.5
        contentView?.layer?.borderColor = NSColor.separatorColor.cgColor

        setupContentView()
    }

    private func setupContentView() {
        guard let contentView = contentView else { return }

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 350),
        ])
    }

    // MARK: - Update

    func updatePredictions(_ predictions: [TokenPrediction]) {
        // Clear existing bars
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        barViews.removeAll()
        selectedIndex = 0

        // Add title
        if !predictions.isEmpty {
            stackView.addArrangedSubview(titleLabel)
        }

        // Add bars for each prediction
        for (index, pred) in predictions.enumerated() {
            let bar = ProbabilityBarView()
            bar.tokenText = pred.text
            bar.probability = pred.probability
            bar.isSelected = (index == 0)
            bar.wantsLayer = true
            bar.layer?.cornerRadius = 4
            barViews.append(bar)
            stackView.addArrangedSubview(bar)
        }

        // Size to fit
        contentView?.layout()
        let size = measuredFittingSize()
        setContentSize(size)
    }

    var onSelect: ((TokenPrediction) -> Void)?

    func moveUp() {
        guard !barViews.isEmpty else { return }
        barViews[selectedIndex].isSelected = false
        selectedIndex = (selectedIndex - 1 + barViews.count) % barViews.count
        barViews[selectedIndex].isSelected = true
    }

    func moveDown() {
        guard !barViews.isEmpty else { return }
        barViews[selectedIndex].isSelected = false
        selectedIndex = (selectedIndex + 1) % barViews.count
        barViews[selectedIndex].isSelected = true
    }

    func confirmSelection() {
        guard !storedPredictions.isEmpty, selectedIndex < storedPredictions.count else {
            return
        }
        onSelect?(storedPredictions[selectedIndex])
    }

    // We store predictions separately for selection lookup
    private var storedPredictions: [TokenPrediction] = []

    func updatePredictionsWithStorage(_ predictions: [TokenPrediction]) {
        storedPredictions = predictions
        updatePredictions(predictions)
    }

    // MARK: - Positioning

    /// Position the window relative to a screen point (usually near the cursor).
    func position(near point: NSPoint, on screen: NSScreen?) {
        let screenRect = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = point
        origin.y -= frame.height + 4

        // Keep in screen bounds
        if origin.x + frame.width > screenRect.maxX {
            origin.x = screenRect.maxX - frame.width - 8
        }
        if origin.x < screenRect.minX {
            origin.x = screenRect.minX + 8
        }
        if origin.y < screenRect.minY {
            origin.y = point.y + 24  // Show above cursor instead
        }

        setFrameOrigin(origin)
    }

    // MARK: - Helper

    private func measuredFittingSize() -> NSSize {
        var height: CGFloat = 0
        for subview in stackView.arrangedSubviews {
            height += subview.intrinsicContentSize.height
        }
        height += CGFloat(stackView.arrangedSubviews.count - 1) * stackView.spacing
        height += stackView.edgeInsets.top + stackView.edgeInsets.bottom
        return NSSize(width: 350, height: max(height, 0))
    }
}
