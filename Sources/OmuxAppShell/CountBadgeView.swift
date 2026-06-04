import AppKit

/// A small circular badge displaying a numeric count.
/// Used by `CollapsibleSectionHeaderView` to show item counts next to section titles.
@MainActor
final class CountBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 6),
            heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func render(count: Int, badgeColor: NSColor, numberColor: NSColor) {
        label.stringValue = "\(count)"
        layer?.backgroundColor = badgeColor.cgColor
        label.textColor = numberColor
    }
}
