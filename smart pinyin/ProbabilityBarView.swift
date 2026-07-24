//
//  ProbabilityBarView.swift
//  smart pinyin
//
//  A row showing: [token text] ··· [numeric %] [probability bar ████░░].
//  The bar always has a visible track so even low probabilities are readable.
//

import Cocoa

final class ProbabilityBarView: NSView {

    var probability: Float = 0 {
        didSet { needsDisplay = true }
    }

    var tokenText: String = "" {
        didSet { needsDisplay = true }
    }

    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    /// Width reserved for the bar + percentage on the right.
    private let barAreaWidth: CGFloat = 120
    private let barHeight: CGFloat = 14
    private let textLeftPadding: CGFloat = 10

    // MARK: - Colors

    private let barTrackColor   = NSColor.tertiaryLabelColor.withAlphaComponent(0.25)
    private let barFillColor    = NSColor.systemBlue
    private let textColor       = NSColor.labelColor
    private let pctColor        = NSColor.secondaryLabelColor
    private let selectedBg      = NSColor.selectedControlColor
    private let selectedText    = NSColor.selectedControlTextColor

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        // ---- Row background ----
        if isSelected {
            selectedBg.setFill()
            bounds.fill()
        } else {
            NSColor.clear.setFill()
            bounds.fill()
        }

        let textColorToUse   = isSelected ? selectedText : textColor
        let pctColorToUse    = isSelected ? selectedText.withAlphaComponent(0.8) : pctColor
        let trackColorToUse  = isSelected
            ? NSColor.white.withAlphaComponent(0.2)
            : barTrackColor
        let fillColorToUse   = isSelected
            ? NSColor.white
            : barFillColor

        // ---- 1. Token text (left) ----
        let textRightEdge = bounds.maxX - barAreaWidth - 8
        let textRect = NSRect(
            x: textLeftPadding,
            y: 0,
            width: textRightEdge - textLeftPadding,
            height: bounds.height
        )
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineBreakMode = .byTruncatingTail
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColorToUse,
            .paragraphStyle: paraStyle,
        ]
        let textDrawRect = textRect.insetBy(dx: 0, dy: (textRect.height - 18) / 2)
        (tokenText as NSString).draw(in: textDrawRect, withAttributes: textAttrs)

        // ---- 2. Percentage label ----
        let pctString = String(format: "%.1f%%", probability * 100)
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: pctColorToUse,
        ]
        let pctSize = (pctString as NSString).size(withAttributes: pctAttrs)
        let pctX = bounds.maxX - barAreaWidth + 2
        let pctRect = NSRect(
            x: pctX,
            y: bounds.height - pctSize.height - 3,
            width: pctSize.width,
            height: pctSize.height
        )
        (pctString as NSString).draw(in: pctRect, withAttributes: pctAttrs)

        // ---- 3. Bar track (full width background) ----
        let barY: CGFloat = 5
        let barRect = NSRect(
            x: pctX,
            y: barY,
            width: barAreaWidth - 4,
            height: barHeight
        )
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3)
        trackColorToUse.setFill()
        barPath.fill()

        // ---- 4. Bar fill (probability width, minimum 3pt) ----
        let fillWidth = max(barRect.width * CGFloat(probability), 3)
        let fillRect = NSRect(
            x: barRect.minX,
            y: barRect.minY,
            width: fillWidth,
            height: barRect.height
        )
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
        fillColorToUse.setFill()
        fillPath.fill()
    }
}