#!/usr/bin/env swift

import Foundation

struct ScriptError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Color {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(dictionary: [String: Any]) throws {
        guard
            let red = dictionary["Red Component"] as? Double,
            let green = dictionary["Green Component"] as? Double,
            let blue = dictionary["Blue Component"] as? Double
        else {
            throw ScriptError(message: "Invalid iTerm2 color dictionary: \(dictionary)")
        }

        self.init(red: red, green: green, blue: blue)
    }

    var hex: String {
        String(
            format: "#%02x%02x%02x",
            Int(clamped(red) * 255),
            Int(clamped(green) * 255),
            Int(clamped(blue) * 255)
        )
    }

    var luminance: Double {
        (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    func lighten(_ amount: Double) -> Color {
        blend(toward: Color(red: 1, green: 1, blue: 1), amount: amount)
    }

    func darken(_ amount: Double) -> Color {
        blend(toward: Color(red: 0, green: 0, blue: 0), amount: amount)
    }

    func mix(with other: Color, selfWeight: Double) -> Color {
        let otherWeight = 1 - selfWeight
        return Color(
            red: (red * selfWeight) + (other.red * otherWeight),
            green: (green * selfWeight) + (other.green * otherWeight),
            blue: (blue * selfWeight) + (other.blue * otherWeight)
        )
    }

    private func blend(toward other: Color, amount: Double) -> Color {
        mix(with: other, selfWeight: 1 - amount)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

let tokenOrder = [
    "bg.canvas", "bg.surface", "bg.elevated",
    "fg.primary", "fg.secondary", "fg.muted",
    "border.subtle", "border.strong",
    "accent",
    "cursor", "cursor.text", "selection.bg", "selection.fg",
    "ansi.black", "ansi.red", "ansi.green", "ansi.yellow",
    "ansi.blue", "ansi.magenta", "ansi.cyan", "ansi.white",
    "ansi.brightBlack", "ansi.brightRed", "ansi.brightGreen", "ansi.brightYellow",
    "ansi.brightBlue", "ansi.brightMagenta", "ansi.brightCyan", "ansi.brightWhite",
]

func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2 else {
        throw ScriptError(
            message: """
            usage: Scripts/import-iterm2.swift <input.itermcolors> <output.toml> [--name name] [--display-name "Display Name"]
            """
        )
    }

    let inputURL = URL(fileURLWithPath: arguments[0])
    let outputURL = URL(fileURLWithPath: arguments[1])

    var explicitName: String?
    var explicitDisplayName: String?
    var index = 2
    while index < arguments.count {
        switch arguments[index] {
        case "--name":
            index += 1
            guard index < arguments.count else {
                throw ScriptError(message: "--name requires a value")
            }
            explicitName = arguments[index]
        case "--display-name":
            index += 1
            guard index < arguments.count else {
                throw ScriptError(message: "--display-name requires a value")
            }
            explicitDisplayName = arguments[index]
        default:
            throw ScriptError(message: "Unknown option: \(arguments[index])")
        }
        index += 1
    }

    let data = try Data(contentsOf: inputURL)
    let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
    guard let root = propertyList as? [String: Any] else {
        throw ScriptError(message: "Expected iTerm2 plist dictionary at root")
    }

    let name = explicitName ?? slugify(inputURL.deletingPathExtension().lastPathComponent)
    let displayName = explicitDisplayName ?? inputURL.deletingPathExtension().lastPathComponent

    let background = try color(root, key: "Background Color")
    let foreground = try color(root, key: "Foreground Color")
    let cursor = try color(root, key: "Cursor Color")
    let selection = try color(root, key: "Selection Color")

    let ansiNames = [
        "black", "red", "green", "yellow",
        "blue", "magenta", "cyan", "white",
        "brightBlack", "brightRed", "brightGreen", "brightYellow",
        "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
    ]

    var tokens: [String: Color] = [
        "bg.canvas": background,
        "fg.primary": foreground,
        "cursor": cursor,
        "cursor.text": background,
        "selection.bg": selection,
        "selection.fg": background.luminance < 0.5 ? Color(red: 1, green: 1, blue: 1) : Color(red: 0, green: 0, blue: 0),
    ]

    for (index, name) in ansiNames.enumerated() {
        tokens["ansi.\(name)"] = try color(root, key: "Ansi \(index) Color")
    }

    let isDark = background.luminance < 0.5
    tokens["bg.surface"] = isDark ? background.lighten(0.03) : background.darken(0.03)
    tokens["bg.elevated"] = isDark ? background.lighten(0.06) : background.darken(0.06)
    tokens["fg.secondary"] = foreground.mix(with: background, selfWeight: 0.65)
    tokens["fg.muted"] = foreground.mix(with: background, selfWeight: 0.45)
    tokens["border.subtle"] = foreground.mix(with: background, selfWeight: 0.12)
    tokens["border.strong"] = foreground.mix(with: background, selfWeight: 0.25)
    tokens["accent"] = tokens["ansi.blue"] ?? foreground

    let contents = makeThemeTOML(name: name, displayName: displayName, tokens: tokens)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: outputURL, atomically: true, encoding: .utf8)
}

func color(_ root: [String: Any], key: String) throws -> Color {
    guard let dictionary = root[key] as? [String: Any] else {
        throw ScriptError(message: "Missing iTerm2 color key '\(key)'")
    }
    return try Color(dictionary: dictionary)
}

func slugify(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func makeThemeTOML(name: String, displayName: String, tokens: [String: Color]) -> String {
    var lines = [
        "schema = 1",
        "name = \"\(name)\"",
        "displayName = \"\(displayName)\"",
        "",
        "[tokens]",
    ]

    for token in tokenOrder {
        guard let color = tokens[token] else {
            continue
        }
        lines.append("\"\(token)\" = \"\(color.hex)\"")
    }

    return lines.joined(separator: "\n") + "\n"
}

do {
    try main()
} catch {
    fputs("import-iterm2 error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
