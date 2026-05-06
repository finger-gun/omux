import Foundation
import OmuxControlPlane
import OmuxCore

public struct OmuxMarkdownPreviewRequest: Equatable {
    public let fileURL: URL
    public let paneID: String?
    public let title: String?
    public let watch: Bool
    public let axis: PaneSplitAxis

    public init(
        fileURL: URL,
        paneID: String?,
        title: String?,
        watch: Bool,
        axis: PaneSplitAxis
    ) {
        self.fileURL = fileURL
        self.paneID = paneID
        self.title = title
        self.watch = watch
        self.axis = axis
    }
}

public struct OmuxMarkdownPreviewRenderer {
    public let theme: String

    public init(theme: String) {
        self.theme = theme
    }

    public func render(markdown: String, title: String, sourcePath: String) -> String {
        let body = renderBlocks(markdown)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <style>
        \(styleSheet(theme: theme))
        </style>
        </head>
        <body>
        <main>
        <div class="source">\(escapeHTML(sourcePath))</div>
        \(body)
        </main>
        </body>
        </html>
        """
    }

    public func renderFile(_ fileURL: URL) throws -> String {
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        return render(
            markdown: markdown,
            title: fileURL.lastPathComponent,
            sourcePath: fileURL.path
        )
    }

    private func renderBlocks(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var codeLines: [String] = []
        var isInsideCodeFence = false

        func flushParagraph() {
            guard paragraph.isEmpty == false else {
                return
            }
            output.append("<p>\(renderInline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }

        func flushList() {
            guard listItems.isEmpty == false else {
                return
            }
            output.append("<ul>\n\(listItems.map { "<li>\($0)</li>" }.joined(separator: "\n"))\n</ul>")
            listItems.removeAll()
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if isInsideCodeFence {
                    output.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                    isInsideCodeFence = false
                } else {
                    flushParagraph()
                    flushList()
                    isInsideCodeFence = true
                }
                continue
            }

            if isInsideCodeFence {
                codeLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                output.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                listItems.append(renderInline(String(trimmed.dropFirst(2))))
                continue
            }

            flushList()
            paragraph.append(trimmed)
        }

        if isInsideCodeFence {
            output.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
        }
        flushParagraph()
        flushList()

        return output.joined(separator: "\n")
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level),
              line.dropFirst(level).first == " "
        else {
            return nil
        }
        return (level, String(line.dropFirst(level + 1)))
    }

    private func renderInline(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0

        while index < characters.count {
            if characters[index] == "`",
               let end = characters[(index + 1)...].firstIndex(of: "`") {
                let content = String(characters[(index + 1)..<end])
                output += "<code>\(escapeHTML(content))</code>"
                index = end + 1
                continue
            }

            if characters[index] == "[",
               let labelEnd = characters[(index + 1)...].firstIndex(of: "]"),
               labelEnd + 1 < characters.count,
               characters[labelEnd + 1] == "(",
               let urlEnd = characters[(labelEnd + 2)...].firstIndex(of: ")") {
                let label = String(characters[(index + 1)..<labelEnd])
                let url = sanitizeURL(String(characters[(labelEnd + 2)..<urlEnd]))
                output += "<a href=\"\(escapeAttribute(url))\">\(escapeHTML(label))</a>"
                index = urlEnd + 1
                continue
            }

            output += escapeHTML(String(characters[index]))
            index += 1
        }

        return output
    }

    private func sanitizeURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased()
        else {
            return trimmed
        }
        return ["http", "https", "mailto"].contains(scheme) ? trimmed : "#"
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escapeHTML(value).replacingOccurrences(of: "\n", with: "")
    }

    private func styleSheet(theme: String) -> String {
        let explicitDark = theme == "dark"
        let explicitLight = theme == "light"
        return """
        :root {
          color-scheme: light dark;
          --bg: #ffffff;
          --fg: #24292f;
          --muted: #57606a;
          --border: #d0d7de;
          --code-bg: #f6f8fa;
          --link: #0969da;
        }
        \(explicitDark ? darkStyle : "")
        @media (prefers-color-scheme: dark) {
          \(explicitLight ? "" : darkVariables)
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          background: var(--bg);
          color: var(--fg);
          font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        main {
          max-width: 980px;
          margin: 0 auto;
          padding: 32px 40px;
        }
        .source {
          color: var(--muted);
          font-size: 12px;
          margin-bottom: 24px;
        }
        h1, h2 {
          border-bottom: 1px solid var(--border);
          padding-bottom: .3em;
        }
        h1, h2, h3, h4, h5, h6 {
          margin: 24px 0 16px;
          line-height: 1.25;
        }
        p, ul, pre { margin: 0 0 16px; }
        a { color: var(--link); }
        code {
          background: var(--code-bg);
          border-radius: 6px;
          padding: .2em .4em;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 85%;
        }
        pre {
          background: var(--code-bg);
          border-radius: 8px;
          overflow: auto;
          padding: 16px;
        }
        pre code {
          background: transparent;
          padding: 0;
          font-size: 100%;
        }
        """
    }

    private var darkStyle: String {
        """
        :root {
          \(darkVariables)
        }
        """
    }

    private var darkVariables: String {
        """
        --bg: #0d1117;
        --fg: #e6edf3;
        --muted: #8b949e;
        --border: #30363d;
        --code-bg: #161b22;
        --link: #2f81f7;
        """
    }
}

public struct OmuxMarkdownPreviewPlugin {
    public static let pluginID = "dev.fingergun.markdown-preview"
    public static let commandName = "markdown-preview"
    public static let commandDisplayPath = "bundled:\(pluginID)"

    public let renderer: OmuxMarkdownPreviewRenderer

    public init(renderer: OmuxMarkdownPreviewRenderer) {
        self.renderer = renderer
    }

    public func run(
        request: OmuxMarkdownPreviewRequest,
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws -> Int32 {
        var paneID = request.paneID
        if let createdPaneID = try updatePreview(request: request, paneID: paneID, client: client) {
            paneID = createdPaneID
        }

        guard request.watch else {
            return 0
        }

        guard let paneID else {
            writeLine("omux markdown-preview error: extension pane did not return a pane ID for watch mode.")
            return 1
        }

        writeLine("Watching \(request.fileURL.path)")
        try watch(request: request, paneID: paneID, client: client, writeLine: writeLine)
        return 0
    }

    private func updatePreview(
        request: OmuxMarkdownPreviewRequest,
        paneID: String?,
        client: OmuxControlClient
    ) throws -> String? {
        let html: String
        let status: String
        let message: String?
        do {
            html = try renderer.renderFile(request.fileURL)
            status = ExtensionPaneStatus.ready.rawValue
            message = nil
        } catch {
            html = ""
            status = ExtensionPaneStatus.error.rawValue
            message = "Unable to render \(request.fileURL.lastPathComponent): \(error.localizedDescription)"
        }

        var params: [String: RPCValue] = [
            "pluginID": .string(Self.pluginID),
            "title": .string(request.title ?? request.fileURL.lastPathComponent),
            "source": .string(request.fileURL.path),
            "contentKind": .string(ExtensionPaneContentKind.html.rawValue),
            "status": .string(status),
            "html": .string(html),
        ]
        if let message {
            params["message"] = .string(message)
        }

        if let paneID {
            params["paneID"] = .string(paneID)
            _ = try client.request(method: .updateExtensionPane, params: .object(params))
            return nil
        } else {
            params["axis"] = .string(request.axis.rawValue)
            let response = try client.request(method: .createExtensionPane, params: .object(params))
            return response.result?.objectValue?["paneID"]?.stringValue
        }
    }

    private func watch(
        request: OmuxMarkdownPreviewRequest,
        paneID: String,
        client: OmuxControlClient,
        writeLine: (String) -> Void
    ) throws {
        var lastModificationDate = modificationDate(for: request.fileURL)
        while true {
            Thread.sleep(forTimeInterval: 0.4)
            let nextModificationDate = modificationDate(for: request.fileURL)
            guard nextModificationDate != lastModificationDate else {
                continue
            }
            lastModificationDate = nextModificationDate
            do {
                _ = try updatePreview(request: request, paneID: paneID, client: client)
            } catch {
                writeLine("omux markdown-preview error: \(error.localizedDescription)")
            }
        }
    }

    private func modificationDate(for fileURL: URL) -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }
}

private extension RPCValue {
    var objectValue: [String: RPCValue]? {
        guard case .object(let object) = self else {
            return nil
        }
        return object
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }
}
