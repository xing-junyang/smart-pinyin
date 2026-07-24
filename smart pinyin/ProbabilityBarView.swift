//
//  ProbabilityBarView.swift
//  smart pinyin
//
//  An NSView that draws a horizontal probability bar with a label.
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

    // MARK: Colors

    private let barGradientStart = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
    private let barGradientEnd   = NSColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1.0)
    private let selectedBg       = NSColor.selectedControlColor
    private let textColor        = NSColor.labelColor
    private let selectedTextColor = NSColor.selectedControlTextColor
    private let percentColor     = NSColor.secondaryLabelColor

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let inset: CGFloat = 4

        // Background
        if isSelected {
            selectedBg.setFill()
            bounds.fill()
        } else {
            NSColor.clear.setFill()
            bounds.fill()
        }

        let drawRect = bounds.insetBy(dx: inset, dy: 2)

        // ---- Probability bar ----
        let barWidth = drawRect.width * CGFloat(probability)
        let barRect = NSRect(x: drawRect.minX, y: drawRect.minY,
                             width: barWidth, height: drawRect.height)

        // Gradient bar
        if let gradient = NSGradient(starting: barGradientStart, ending: barGradientEnd) {
            gradient.draw(in: barRect, angle: 0)
        } else {
            barGradientStart.setFill()
            barRect.fill()
        }

        // Bar rounded corners (clip)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4)
        barPath.addClip()
        barGradientStart.setFill()
        barRect.fill()

        // ---- Text ----
        let textColorToUse = isSelected ? selectedTextColor : textColor
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineBreakMode = .byTruncatingTail

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColorToUse,
            .paragraphStyle: paraStyle,
        ]

        // Token text on the left
        let textRect = NSRect(
            x: drawRect.minX + 8,
            y: drawRect.minY + 2,
            width: drawRect.width * 0.55,
            height: drawRect.height - 4
        )
        (tokenText as NSString).draw(in: textRect, withAttributes: textAttrs)

        // Percentage on the right
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: isSelected ? selectedTextColor.withAlphaComponent(0.8) : percentColor,
        ]
        let pctString = String(format: "%.1f%%", probability * 100)
        let pctSize = (pctString as NSString).size(withAttributes: pctAttrs)
        let pctRect = NSRect(
            x: drawRect.maxX - pctSize.width - 8,
            y: drawRect.minY + (drawRect.height - pctSize.height) / 2,
            width: pctSize.width,
            height: pctSize.height
        )
        (pctString as NSString).draw(in: pctRect, withAttributes: pctAttrs)
    }
}
