#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
IMPORT_DIR="$ROOT_DIR/Scripts/theme-imports"
MANIFEST_FILE="${THEME_IMPORT_MANIFEST:-"$IMPORT_DIR/iterm2-popular.txt"}"
REF_FILE="${ITERM2_COLOR_SCHEMES_REF_FILE:-"$IMPORT_DIR/iterm2-colors-ref"}"
OUTPUT_DIR="${THEME_OUTPUT_DIR:-"$ROOT_DIR/Sources/OmuxTheme/Resources/themes"}"
REPOSITORY_URL="https://github.com/mbadolato/iTerm2-Color-Schemes"

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "error: missing theme import manifest at $MANIFEST_FILE" >&2
  exit 1
fi

if [ "${ITERM2_COLOR_SCHEMES_REF:-}" ]; then
  UPSTREAM_REF="$ITERM2_COLOR_SCHEMES_REF"
elif [ -f "$REF_FILE" ]; then
  UPSTREAM_REF="$(sed -e 's/[[:space:]]//g' "$REF_FILE")"
else
  echo "error: missing upstream ref file at $REF_FILE" >&2
  exit 1
fi

if [ -z "$UPSTREAM_REF" ]; then
  echo "error: upstream ref is empty" >&2
  exit 1
fi

SWIFT_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/openmux-theme-import.XXXXXX.swift")"
cleanup() {
  rm -f "$SWIFT_SCRIPT"
}
trap cleanup EXIT INT TERM

cat > "$SWIFT_SCRIPT" <<'SWIFT'
import Foundation

struct ThemeRow {
    let outputID: String
    let upstreamName: String
    let displayName: String
}

struct SourceTheme {
    let colors: [String: String]
    let palette: [Int: String]
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("usage: import <manifest> <upstream-ref> <output-dir> <repository-url>")
}

let manifestURL = URL(fileURLWithPath: arguments[1])
let upstreamRef = arguments[2]
let outputDirectoryURL = URL(fileURLWithPath: arguments[3], isDirectory: true)
let repositoryURL = arguments[4]
let rawBaseURL = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/\(upstreamRef)/ghostty"

let rows = parseManifest(at: manifestURL)
try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

var seenIDs: Set<String> = []
var seenSources: Set<String> = []
for row in rows {
    guard seenIDs.insert(row.outputID).inserted else {
        fail("duplicate output id '\(row.outputID)' in \(manifestURL.path)")
    }
    guard seenSources.insert(row.upstreamName).inserted else {
        fail("duplicate upstream theme '\(row.upstreamName)' in \(manifestURL.path)")
    }

    let source = fetchSourceTheme(row.upstreamName, rawBaseURL: rawBaseURL)
    let theme = parseSourceTheme(source, upstreamName: row.upstreamName)
    let output = renderOpenMUXTheme(
        row: row,
        source: theme,
        upstreamRef: upstreamRef,
        repositoryURL: repositoryURL
    )
    let outputURL = outputDirectoryURL.appendingPathComponent("\(row.outputID).toml")
    let temporaryURL = outputURL.appendingPathExtension("tmp")
    try output.write(to: temporaryURL, atomically: true, encoding: .utf8)
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    print("Wrote \(outputURL.path)")
}

func parseManifest(at url: URL) -> [ThemeRow] {
    let contents: String
    do {
        contents = try String(contentsOf: url, encoding: .utf8)
    } catch {
        fail("unable to read manifest at \(url.path): \(error)")
    }

    var rows: [ThemeRow] = []
    for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") {
            continue
        }

        let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 3 else {
            fail("invalid manifest row \(index + 1): expected 'output-id | upstream-name | display-name'")
        }

        guard isValidThemeIdentifier(parts[0]) else {
            fail("invalid output id '\(parts[0])' on manifest row \(index + 1)")
        }

        guard parts[1].isEmpty == false, parts[2].isEmpty == false else {
            fail("manifest row \(index + 1) contains an empty upstream name or display name")
        }

        rows.append(ThemeRow(outputID: parts[0], upstreamName: parts[1], displayName: parts[2]))
    }

    guard rows.isEmpty == false else {
        fail("manifest at \(url.path) does not contain any themes")
    }
    return rows
}

func isValidThemeIdentifier(_ value: String) -> Bool {
    guard let first = value.unicodeScalars.first, CharacterSet.lowercaseLetters.union(.decimalDigits).contains(first) else {
        return false
    }

    let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-"))
    return value.unicodeScalars.allSatisfy { allowed.contains($0) } && value.contains("--") == false && value.hasSuffix("-") == false
}

func fetchSourceTheme(_ upstreamName: String, rawBaseURL: String) -> String {
    var pathComponentAllowed = CharacterSet.urlPathAllowed
    pathComponentAllowed.remove(charactersIn: "/")
    guard let encodedName = upstreamName.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed) else {
        fail("unable to URL-encode upstream theme name '\(upstreamName)'")
    }

    let url = "\(rawBaseURL)/\(encodedName)"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["-fsSL", url]

    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("unable to run curl for '\(upstreamName)': \(error)")
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    if process.terminationStatus != 0 {
        let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        fail("unable to fetch upstream theme '\(upstreamName)' from \(url): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    guard let contents = String(data: data, encoding: .utf8), contents.isEmpty == false else {
        fail("upstream theme '\(upstreamName)' returned empty or non-UTF-8 content")
    }
    return contents
}

func parseSourceTheme(_ contents: String, upstreamName: String) -> SourceTheme {
    var colors: [String: String] = [:]
    var palette: [Int: String] = [:]

    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") {
            continue
        }

        guard let equalsIndex = line.firstIndex(of: "=") else {
            continue
        }

        let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)

        if key == "palette" {
            guard let paletteEqualsIndex = value.firstIndex(of: "=") else {
                fail("invalid palette entry in upstream theme '\(upstreamName)': \(line)")
            }

            let indexText = value[..<paletteEqualsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let colorText = value[value.index(after: paletteEqualsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(indexText), (0...15).contains(index) else {
                fail("invalid palette index '\(indexText)' in upstream theme '\(upstreamName)'")
            }
            palette[index] = normalizedHex(colorText, context: "palette \(index)", upstreamName: upstreamName)
        } else {
            colors[key] = normalizedHex(value, context: key, upstreamName: upstreamName)
        }
    }

    for key in ["background", "foreground", "cursor-color", "cursor-text", "selection-background", "selection-foreground"] where colors[key] == nil {
        fail("upstream theme '\(upstreamName)' is missing required color '\(key)'")
    }

    for index in 0...15 where palette[index] == nil {
        fail("upstream theme '\(upstreamName)' is missing required palette index \(index)")
    }

    return SourceTheme(colors: colors, palette: palette)
}

func normalizedHex(_ value: String, context: String, upstreamName: String) -> String {
    let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    guard unquoted.hasPrefix("#") else {
        fail("color '\(context)' in upstream theme '\(upstreamName)' must be a hex string")
    }

    let digits = String(unquoted.dropFirst())
    let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    guard (digits.count == 6 || digits.count == 8), digits.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
        fail("color '\(context)' in upstream theme '\(upstreamName)' is not #RRGGBB or #RRGGBBAA")
    }

    return "#\(digits.lowercased())"
}

func renderOpenMUXTheme(row: ThemeRow, source: SourceTheme, upstreamRef: String, repositoryURL: String) -> String {
    let colors = source.colors
    let palette = source.palette
    let sourcePath = "ghostty/\(row.upstreamName)"
    let sourceURL = "\(repositoryURL)/blob/\(upstreamRef)/\(sourcePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sourcePath)"

    let tokens: [(String, String)] = [
        ("bg.canvas", colors["background"]!),
        ("bg.surface", colors["background"]!),
        ("bg.elevated", palette[8] ?? colors["selection-background"]!),
        ("fg.primary", colors["foreground"]!),
        ("fg.secondary", palette[7] ?? colors["foreground"]!),
        ("fg.muted", palette[8] ?? colors["foreground"]!),
        ("border.subtle", palette[8] ?? colors["selection-background"]!),
        ("border.strong", colors["selection-background"]!),
        ("accent", palette[12] ?? colors["cursor-color"]!),
        ("cursor", colors["cursor-color"]!),
        ("cursor.text", colors["cursor-text"]!),
        ("selection.bg", colors["selection-background"]!),
        ("selection.fg", colors["selection-foreground"]!),
        ("ansi.black", palette[0]!),
        ("ansi.red", palette[1]!),
        ("ansi.green", palette[2]!),
        ("ansi.yellow", palette[3]!),
        ("ansi.blue", palette[4]!),
        ("ansi.magenta", palette[5]!),
        ("ansi.cyan", palette[6]!),
        ("ansi.white", palette[7]!),
        ("ansi.brightBlack", palette[8]!),
        ("ansi.brightRed", palette[9]!),
        ("ansi.brightGreen", palette[10]!),
        ("ansi.brightYellow", palette[11]!),
        ("ansi.brightBlue", palette[12]!),
        ("ansi.brightMagenta", palette[13]!),
        ("ansi.brightCyan", palette[14]!),
        ("ansi.brightWhite", palette[15]!),
    ]

    var lines: [String] = [
        "# Generated by Scripts/import-iterm2-themes.sh. Do not edit directly.",
        "# Source repository: \(repositoryURL)",
        "# Source ref: \(upstreamRef)",
        "# Source theme: \(row.upstreamName)",
        "# Source file: \(sourceURL)",
        "# Upstream collection license: MIT; individual theme copyrights/licenses remain with their authors.",
        "schema = 1",
        "name = \"\(escapeTOML(row.outputID))\"",
        "displayName = \"\(escapeTOML(row.displayName))\"",
        "",
        "[tokens]",
    ]

    lines.append(contentsOf: tokens.map { "\"\($0.0)\" = \"\($0.1)\"" })
    lines.append("")
    return lines.joined(separator: "\n")
}

func escapeTOML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}
SWIFT

swift "$SWIFT_SCRIPT" "$MANIFEST_FILE" "$UPSTREAM_REF" "$OUTPUT_DIR" "$REPOSITORY_URL"
