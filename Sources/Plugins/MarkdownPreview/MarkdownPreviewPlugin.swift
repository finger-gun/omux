import Foundation
import OmuxControlPlane
import OmuxCore
import cmark_gfm
import cmark_gfm_extensions

public struct OmuxMarkdownPreviewRequest: Equatable {
    public let fileURL: URL
    public let paneID: String?
    public let title: String?
    public let watch: Bool
    public let axis: PaneSplitAxis
    public let presentationStyle: ExtensionPanePresentationStyle?

    public init(
        fileURL: URL,
        paneID: String?,
        title: String?,
        watch: Bool,
        axis: PaneSplitAxis,
        presentationStyle: ExtensionPanePresentationStyle?
    ) {
        self.fileURL = fileURL
        self.paneID = paneID
        self.title = title
        self.watch = watch
        self.axis = axis
        self.presentationStyle = presentationStyle
    }
}

public enum OmuxMarkdownPreviewRenderError: Error, LocalizedError {
    case parserUnavailable
    case documentUnavailable
    case htmlRenderFailed

    public var errorDescription: String? {
        switch self {
        case .parserUnavailable:
            "Markdown parser is unavailable."
        case .documentUnavailable:
            "Markdown parser did not produce a document."
        case .htmlRenderFailed:
            "Markdown parser could not render HTML."
        }
    }
}

public struct OmuxMarkdownPreviewRenderer {
    public let theme: String

    public init(theme: String) {
        self.theme = theme
    }

    public func render(markdown: String, title: String, sourcePath: String) throws -> String {
        let sourceDirectory = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        let body = try renderMarkdownFragment(markdown, sourceDirectory: sourceDirectory)
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
        return try render(
            markdown: markdown,
            title: fileURL.lastPathComponent,
            sourcePath: fileURL.path
        )
    }

    private func renderMarkdownFragment(_ markdown: String, sourceDirectory: URL) throws -> String {
        cmark_gfm_core_extensions_ensure_registered()

        let options = CMARK_OPT_UNSAFE
            | CMARK_OPT_VALIDATE_UTF8
            | CMARK_OPT_SMART
            | CMARK_OPT_LIBERAL_HTML_TAG
            | CMARK_OPT_TABLE_SPANS
        guard let parser = cmark_parser_new(options) else {
            throw OmuxMarkdownPreviewRenderError.parserUnavailable
        }
        defer { cmark_parser_free(parser) }

        let extensions = activeGFMExtensions(for: parser)
        defer {
            if let list = extensions {
                cmark_llist_free(cmark_get_default_mem_allocator(), list)
            }
        }

        markdown.withCString { buffer in
            cmark_parser_feed(parser, buffer, markdown.utf8.count)
        }
        guard let document = cmark_parser_finish(parser) else {
            throw OmuxMarkdownPreviewRenderError.documentUnavailable
        }
        defer { cmark_node_free(document) }

        guard let rendered = cmark_render_html(document, options, extensions) else {
            throw OmuxMarkdownPreviewRenderError.htmlRenderFailed
        }
        defer { free(rendered) }

        return sanitizeRenderedHTML(String(cString: rendered), sourceDirectory: sourceDirectory)
    }

    private func activeGFMExtensions(for parser: UnsafeMutablePointer<cmark_parser>) -> UnsafeMutablePointer<cmark_llist>? {
        var list: UnsafeMutablePointer<cmark_llist>?
        let allocator = cmark_get_default_mem_allocator()
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
            guard let syntaxExtension = cmark_find_syntax_extension(name) else {
                continue
            }
            cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            list = cmark_llist_append(allocator, list, syntaxExtension)
        }
        return list
    }

    private func sanitizeRenderedHTML(_ html: String, sourceDirectory: URL) -> String {
        var sanitized = html
        sanitized = sanitized.replacingRegex(
            #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            with: ""
        )
        sanitized = sanitized.replacingRegex(
            #"(?is)<script\b[^>]*/\s*>"#,
            with: ""
        )
        sanitized = sanitized.replacingRegex(
            #"(?is)\s+on[a-z][a-z0-9_-]*\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            with: ""
        )
        sanitized = sanitized.replacingRegex(
            #"(?is)\s+(href|src|xlink:href)\s*=\s*"\s*(javascript|vbscript):[^"]*""#,
            with: ""
        )
        sanitized = sanitized.replacingRegex(
            #"(?is)\s+(href|src|xlink:href)\s*=\s*'\s*(javascript|vbscript):[^']*'"#,
            with: ""
        )
        sanitized = sanitized.replacingRegex(
            #"(?is)\s+(href|src|xlink:href)\s*=\s*(javascript|vbscript):[^\s>]+"#,
            with: ""
        )
        return rewriteLocalImageSources(in: sanitized, sourceDirectory: sourceDirectory)
    }

    private func rewriteLocalImageSources(in html: String, sourceDirectory: URL) -> String {
        html.replacingRegex(#"(?is)(<img\b[^>]*\bsrc\s*=\s*)(["'])([^"']*)(["'])"#) { match, source in
            guard match.numberOfRanges == 5,
                  let fullRange = Range(match.range(at: 0), in: source),
                  let prefixRange = Range(match.range(at: 1), in: source),
                  let quoteRange = Range(match.range(at: 2), in: source),
                  let valueRange = Range(match.range(at: 3), in: source),
                  let closingQuoteRange = Range(match.range(at: 4), in: source)
            else {
                return nil
            }

            let value = String(source[valueRange])
            guard let resolvedSource = resolvedLocalImageSource(value, sourceDirectory: sourceDirectory) else {
                return String(source[fullRange])
            }

            return "\(source[prefixRange])\(source[quoteRange])\(escapeAttribute(resolvedSource))\(source[closingQuoteRange])"
        }
    }

    private func resolvedLocalImageSource(_ value: String, sourceDirectory: URL) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.hasPrefix("#") == false,
              trimmed.hasPrefix("//") == false,
              let components = URLComponents(string: trimmed)
        else {
            return nil
        }

        if let scheme = components.scheme?.lowercased() {
            guard scheme == "file",
                  let fileURL = URL(string: trimmed)
            else {
                return nil
            }
            return embeddedLocalImageSource(for: fileURL.standardizedFileURL) ?? trimmed
        }

        let path = components.path
        guard path.isEmpty == false else {
            return nil
        }

        let fileURL = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: path, relativeTo: sourceDirectory).standardizedFileURL

        return embeddedLocalImageSource(for: fileURL) ?? fileURL.absoluteString
    }

    private func embeddedLocalImageSource(for fileURL: URL) -> String? {
        guard fileURL.isFileURL,
              let mimeType = imageMIMEType(for: fileURL),
              let data = try? Data(contentsOf: fileURL),
              data.isEmpty == false
        else {
            return nil
        }
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func imageMIMEType(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "png":
            "image/png"
        case "jpg", "jpeg":
            "image/jpeg"
        case "gif":
            "image/gif"
        case "webp":
            "image/webp"
        case "svg":
            "image/svg+xml"
        default:
            nil
        }
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
        p, ul, ol, pre, table, blockquote { margin: 0 0 16px; }
        a { color: var(--link); }
        blockquote {
          color: var(--muted);
          border-left: .25em solid var(--border);
          padding: 0 1em;
        }
        img { max-width: 100%; }
        table {
          border-collapse: collapse;
          display: block;
          overflow: auto;
          width: max-content;
          max-width: 100%;
        }
        th, td {
          border: 1px solid var(--border);
          padding: 6px 13px;
        }
        tr:nth-child(2n) { background: color-mix(in srgb, var(--code-bg) 60%, transparent); }
        input[type="checkbox"] { margin-right: .35em; }
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

private extension String {
    func replacingRegex(_ pattern: String, with replacement: String) -> String {
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(startIndex..<endIndex, in: self)
        return expression.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: replacement
        )
    }

    func replacingRegex(
        _ pattern: String,
        transform: (_ match: NSTextCheckingResult, _ source: String) -> String?
    ) -> String {
        let expression = try! NSRegularExpression(pattern: pattern)
        let matches = expression.matches(
            in: self,
            range: NSRange(startIndex..<endIndex, in: self)
        )
        var result = self
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let replacement = transform(match, self)
            else {
                continue
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
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
        let markdown = try String(contentsOf: request.fileURL, encoding: .utf8)
        if let createdPaneID = try updatePreview(request: request, paneID: paneID, client: client, markdown: markdown) {
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
        try watch(request: request, paneID: paneID, client: client, initialMarkdown: markdown, writeLine: writeLine)
        return 0
    }

    private func updatePreview(
        request: OmuxMarkdownPreviewRequest,
        paneID: String?,
        client: OmuxControlClient
    ) throws -> String? {
        let markdown = try String(contentsOf: request.fileURL, encoding: .utf8)
        return try updatePreview(request: request, paneID: paneID, client: client, markdown: markdown)
    }

    private func updatePreview(
        request: OmuxMarkdownPreviewRequest,
        paneID: String?,
        client: OmuxControlClient,
        markdown: String
    ) throws -> String? {
        let html: String
        let status: String
        let message: String?
        do {
            html = try renderer.render(markdown: markdown, title: request.title ?? request.fileURL.lastPathComponent, sourcePath: request.fileURL.path)
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
        if let presentation = request.presentationStyle.map({ RPCValue.string($0.rawValue) }) {
            params["presentation"] = presentation
        }
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
        initialMarkdown: String,
        writeLine: (String) -> Void
    ) throws {
        var tracker = MarkdownPreviewChangeTracker(initialMarkdown: initialMarkdown)
        while true {
            Thread.sleep(forTimeInterval: 0.4)
            guard let nextMarkdown = tracker.nextMarkdown(for: request.fileURL) else { continue }
            do {
                _ = try updatePreview(request: request, paneID: paneID, client: client, markdown: nextMarkdown)
            } catch {
                writeLine("omux markdown-preview error: \(error.localizedDescription)")
            }
        }
    }
}

struct MarkdownPreviewChangeTracker {
    private var lastMarkdown: String?

    init(initialMarkdown: String? = nil) {
        self.lastMarkdown = initialMarkdown
    }

    mutating func nextMarkdown(for fileURL: URL) -> String? {
        guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        guard markdown != lastMarkdown else {
            return nil
        }
        lastMarkdown = markdown
        return markdown
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
