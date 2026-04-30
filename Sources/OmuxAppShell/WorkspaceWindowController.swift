import AppKit
import OmuxCore

@MainActor
final class WorkspaceWindowController: NSWindowController {
    private let rootViewController = WorkspaceViewController()

    init(workspace: Workspace) {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = workspace.name
        window.contentViewController = rootViewController
        super.init(window: window)
        rootViewController.update(workspace: workspace)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(workspace: Workspace) {
        window?.title = workspace.name
        rootViewController.update(workspace: workspace)
    }
}

@MainActor
final class WorkspaceViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "OpenMUX")
    private let detailLabel = NSTextField(labelWithString: "")
    private let panesStack = NSStackView()

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        panesStack.orientation = .vertical
        panesStack.spacing = 12
        panesStack.alignment = .leading

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(detailLabel)
        container.addArrangedSubview(panesStack)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    func update(workspace: Workspace) {
        titleLabel.stringValue = workspace.name
        detailLabel.stringValue = "Root: \(workspace.rootPath)"

        panesStack.arrangedSubviews.forEach { subview in
            panesStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for tab in workspace.tabs {
            let tabLabel = NSTextField(labelWithString: "Tab: \(tab.title)")
            tabLabel.font = .systemFont(ofSize: 14, weight: .medium)
            panesStack.addArrangedSubview(tabLabel)

            for pane in tab.panes {
                panesStack.addArrangedSubview(TerminalPanePlaceholderView(pane: pane))
            }
        }
    }
}

@MainActor
final class TerminalPanePlaceholderView: NSView {
    init(pane: Pane) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(
            labelWithString: "Pane \(pane.id.rawValue.prefix(6)) · \(pane.title) · \(pane.session.workingDirectory)"
        )
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor

        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 720),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
