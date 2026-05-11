import Foundation
import OmuxCore

struct CommandPaletteCommandDescriptor: Decodable, Equatable {
    enum Category: String, Decodable {
        case action
        case cli

        var paletteCategory: CommandPaletteCategory {
            switch self {
            case .action: return .action
            case .cli: return .cli
            }
        }
    }

    struct Command: Decodable, Equatable {
        enum Kind: String, Decodable {
            case action
            case builtin
        }

        let kind: Kind
        let target: String
    }

    let id: String
    let title: String
    let subtitle: String?
    let category: Category
    let matchText: String
    let aliases: [String]
    let requiresArguments: Bool
    let hasSafeDefaultTarget: Bool
    let disabledReason: String?
    let command: Command
}

enum CommandPaletteCommandDescriptorCatalog {
    private static let appShellResourceBundleName = "OpenMUX_OmuxAppShell.bundle"
    private static let commandSubdirectory = "CommandPalette/Commands"

    static func bundledDescriptors(
        fileManager: FileManager = .default,
        mainBundleURL: URL = Bundle.main.bundleURL,
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainExecutableURL: URL? = Bundle.main.executableURL
    ) -> [CommandPaletteCommandDescriptor] {
        guard mainBundleURL.pathExtension == "app" else {
            return appShellDescriptors(from: .module)
        }
        let bundle = packagedResourceBundle(
            fileManager: fileManager,
            mainBundleURL: mainBundleURL,
            mainResourceURL: mainResourceURL,
            mainExecutableURL: mainExecutableURL
        ) ?? .module
        return appShellDescriptors(from: bundle)
    }

    static func loadDescriptors(from bundle: Bundle) -> [CommandPaletteCommandDescriptor] {
        let urls = nonEmpty(bundle.urls(forResourcesWithExtension: "json", subdirectory: commandSubdirectory))
            ?? nonEmpty(bundle.urls(forResourcesWithExtension: "json", subdirectory: nil))
            ?? nonEmpty(resourceDirectoryJSONURLs(bundle: bundle))
        guard let urls else {
            return []
        }
        return loadDescriptors(from: urls)
    }

    private static func appShellDescriptors(from bundle: Bundle) -> [CommandPaletteCommandDescriptor] {
        loadDescriptors(from: bundle).filter { $0.category != .cli } + cliCommandDescriptors()
    }

    private static func nonEmpty(_ urls: [URL]?) -> [URL]? {
        guard let urls, urls.isEmpty == false else {
            return nil
        }
        return urls
    }

    private static func resourceDirectoryJSONURLs(bundle: Bundle) -> [URL]? {
        let roots = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }
        var urls: [URL] = []
        for root in roots {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            urls.append(contentsOf: contents.filter { $0.pathExtension == "json" })
        }
        return urls.isEmpty ? nil : urls
    }

    static func loadDescriptors(from urls: [URL]) -> [CommandPaletteCommandDescriptor] {
        let decoder = JSONDecoder()
        var seenIDs = Set<String>()
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            do {
                let descriptor = try decoder.decode(CommandPaletteCommandDescriptor.self, from: Data(contentsOf: url))
                guard descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                      descriptor.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                      descriptor.command.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                      seenIDs.insert(descriptor.id).inserted
                else {
                    return nil
                }
                return descriptor
            } catch {
                fputs("warning: failed to load command palette descriptor \(url.lastPathComponent): \(error)\n", stderr)
                return nil
            }
        }
    }

    private static func cliCommandDescriptors() -> [CommandPaletteCommandDescriptor] {
        OpenMUXCLICommandCatalog.commands.map { spec in
            CommandPaletteCommandDescriptor(
                id: "cli:\(spec.id)",
                title: spec.title,
                subtitle: spec.usage,
                category: .cli,
                matchText: spec.matchText,
                aliases: spec.aliases,
                requiresArguments: spec.requiresArguments,
                hasSafeDefaultTarget: spec.hasSafeDefaultTarget,
                disabledReason: spec.disabledReason,
                command: CommandPaletteCommandDescriptor.Command(kind: .builtin, target: spec.id)
            )
        }
    }

    static func packagedResourceBundle(
        fileManager: FileManager = .default,
        mainBundleURL: URL = Bundle.main.bundleURL,
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainExecutableURL: URL? = Bundle.main.executableURL
    ) -> Bundle? {
        let executableURLs = executableResourceLookupURLs(from: mainExecutableURL)
        let executableCandidates = executableURLs.flatMap { executableURL in
            [
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(appShellResourceBundleName, isDirectory: true),
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(appShellResourceBundleName, isDirectory: true),
            ]
        }

        let candidates = [
            mainResourceURL?.appendingPathComponent(appShellResourceBundleName, isDirectory: true),
            mainBundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(appShellResourceBundleName, isDirectory: true),
            mainBundleURL.appendingPathComponent(appShellResourceBundleName, isDirectory: true),
        ].compactMap { $0 } + executableCandidates

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            if let bundle = Bundle(path: url.path) {
                return bundle
            }
        }
        return nil
    }

    private static func executableResourceLookupURLs(from executableURL: URL?) -> [URL] {
        guard let executableURL else {
            return []
        }
        let resolvedURL = executableURL.resolvingSymlinksInPath().standardizedFileURL
        let standardizedURL = executableURL.standardizedFileURL
        return resolvedURL == standardizedURL ? [standardizedURL] : [standardizedURL, resolvedURL]
    }
}
