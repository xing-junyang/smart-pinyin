//
//  CandidateWindow.swift
//  smart pinyin
//
//  A floating window that displays next-token predictions with probability bars.
//

import Cocoa

// MARK: - Rounded Background View

/// A view that draws itself as a rounded rectangle, used as the window backdrop.
private final class RoundedBackdropView: NSView {
    var fillColor: NSColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97)
    var borderColor: NSColor = NSColor.separatorColor
    var cornerRadius: CGFloat = 12

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

// MARK: - Candidate Window

final class CandidateWindow: NSWindow {

    // MARK: - Subviews

    private let backdrop: RoundedBackdropView = {
        let v = RoundedBackdropView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let stackView: NSStackView = {
        let sv = NSStackView()
        sv.orientation = .vertical
        sv.spacing = 2
        sv.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
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

    // MARK: - Loading UI

    private let loadingLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        tf.textColor = NSColor.labelColor
        tf.alignment = .center
        tf.lineBreakMode = .byTruncatingTail
        return tf
    }()

    private let progressBar: NSProgressIndicator = {
        let pi = NSProgressIndicator()
        pi.style = .bar
        pi.isIndeterminate = false
        pi.minValue = 0
        pi.maxValue = 100
        pi.doubleValue = 0
        pi.controlSize = .small
        pi.translatesAutoresizingMaskIntoConstraints = false
        return pi
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

        // Transparent window – the backdrop view draws the rounded rect.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .ignoresCycle]
        isReleasedWhenClosed = false

        setupContentView()
    }

    private func setupContentView() {
        guard let contentView = contentView else { return }

        // Backdrop fills the window and clips subviews to rounded corners.
        contentView.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backdrop.widthAnchor.constraint(equalToConstant: 350),
        ])

        // Stack sits inside the backdrop with a small inner margin.
        backdrop.addSubview(stackView)
        let inset = backdrop.cornerRadius / 2
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: inset),
            stackView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: inset),
            stackView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -inset),
            stackView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -inset),
        ])
    }

    // MARK: - Update

    /// Whether we are currently showing the loading UI vs predictions.
    private var isLoadingMode = false

    func showLoading(modelName: String, progress: Double) {
        clearContent()
        isLoadingMode = true

        loadingLabel.stringValue = "Loading \(modelName)..."
        progressBar.doubleValue = progress * 100

        stackView.addArrangedSubview(loadingLabel)
        stackView.addArrangedSubview(progressBar)

        NSLayoutConstraint.activate([
            progressBar.widthAnchor.constraint(equalToConstant: 300),
            progressBar.heightAnchor.constraint(equalToConstant: 12),
        ])

        contentView?.layout()
        setContentSize(NSSize(width: 350, height: 60))
    }

    func hideLoading() {
        guard isLoadingMode else { return }
        isLoadingMode = false
        clearContent()
        setContentSize(NSSize(width: 0, height: 0))
    }

    func updatePredictions(_ predictions: [TokenPrediction]) {
        clearContent()
        isLoadingMode = false
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

    private func clearContent() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    private func measuredFittingSize() -> NSSize {
        var height: CGFloat = 0
        for subview in stackView.arrangedSubviews {
            height += subview.intrinsicContentSize.height
        }
        height += CGFloat(max(stackView.arrangedSubviews.count - 1, 0)) * stackView.spacing
        height += stackView.edgeInsets.top + stackView.edgeInsets.bottom
        // Account for the backdrop inset (cornerRadius / 2 on each side)
        height += backdrop.cornerRadius
        return NSSize(width: 350, height: max(height, 0))
    }
}
