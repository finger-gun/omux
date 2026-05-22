import Foundation
import OmuxConfig
import OmuxHooks

enum OmuxExtensionPackageKind: String, Codable, Equatable {
    case hook
    case plugin
}

struct OmuxExtensionRegistrySource: Codable, Equatable {
    let originalURL: String
    let catalogURL: URL
    let rawBaseURL: URL

    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let url = URL(string: trimmed) else {
            throw OmuxExtensionRegistryError.invalidRegistryURL(value)
        }

        originalURL = trimmed

        if url.isFileURL {
            let pathExtension = url.pathExtension.lowercased()
            if pathExtension == "toml" {
                catalogURL = url
                rawBaseURL = url.deletingLastPathComponent()
            } else {
                catalogURL = url.appendingPathComponent("catalog.toml")
                rawBaseURL = url
            }
            return
        }

        guard url.scheme?.lowercased() == "https" else {
            throw OmuxExtensionRegistryError.invalidRegistryURL(value)
        }

        if url.host == "github.com" {
            let components = url.pathComponents.filter { $0 != "/" }
            guard components.count >= 2 else {
                throw OmuxExtensionRegistryError.invalidRegistryURL(value)
            }
            let owner = components[0]
            let repo = components[1]
            let branchAndPath: (branch: String, path: [String])
            if components.count >= 4, components[2] == "tree" || components[2] == "blob" {
                branchAndPath = (components[3], Array(components.dropFirst(4)))
            } else {
                branchAndPath = ("main", [])
            }
            let base = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branchAndPath.branch)"
            let rawBase = ([base] + branchAndPath.path).joined(separator: "/")
            guard let rawBaseURL = URL(string: rawBase) else {
                throw OmuxExtensionRegistryError.invalidRegistryURL(value)
            }
            self.rawBaseURL = rawBaseURL
            self.catalogURL = rawBaseURL.appendingPathComponent("catalog.toml")
            return
        }

        if url.lastPathComponent == "catalog.toml" {
            catalogURL = url
            rawBaseURL = url.deletingLastPathComponent()
            return
        }

        catalogURL = url.appendingPathComponent("catalog.toml")
        rawBaseURL = url
    }

    func fileURL(for relativePath: String) throws -> URL {
        try OmuxExtensionPackageValidator.validateRelativePath(relativePath)
        return rawBaseURL.appendingPathComponent(relativePath)
    }
}

struct OmuxExtensionCatalogPackage: Codable, Equatable {
    let kind: OmuxExtensionPackageKind
    let id: String
    let name: String
    let description: String
    let version: String
    let registry: String
    let manifestPath: String
    let tags: [String]
}

struct OmuxExtensionPackageFile: Codable, Equatable {
    let source: String
    let target: String
    let executable: Bool
}

struct OmuxExtensionHookMetadata: Codable, Equatable {
    let name: String
    let category: HookCategory
}

struct OmuxExtensionPluginMetadata: Codable, Equatable {
    let command: String
    let entrypoint: String
}

struct OmuxExtensionPackageManifest: Codable, Equatable {
    let schema: Int
    let id: String
    let name: String
    let description: String
    let version: String
    let license: String?
    let kind: OmuxExtensionPackageKind
    let hook: OmuxExtensionHookMetadata?
    let plugin: OmuxExtensionPluginMetadata?
    let files: [OmuxExtensionPackageFile]
}

struct OmuxExtensionInstallReceipt: Codable, Equatable {
    let schema: Int
    let kind: OmuxExtensionPackageKind
    let id: String
    let version: String
    let registry: String
    let manifestPath: String
    let targetRoot: String
    let installedFiles: [String]
    let installedAt: Date
}

enum OmuxExtensionRegistryError: Error, CustomStringConvertible, Equatable {
    case invalidRegistryURL(String)
    case fetchFailed(String)
    case invalidCatalog(String)
    case packageNotFound(String)
    case ambiguousPackage(String)
    case invalidManifest(String)
    case unsafePath(String)
    case unmanagedPackage(String)
    case targetExists(String)
    case confirmationRequired
    case cancelled

    var description: String {
        switch self {
        case .invalidRegistryURL(let value):
            return "invalid registry URL: \(value)"
        case .fetchFailed(let value):
            return "failed to fetch \(value)"
        case .invalidCatalog(let value):
            return "invalid catalog: \(value)"
        case .packageNotFound(let value):
            return "package not found: \(value)"
        case .ambiguousPackage(let value):
            return "package id is ambiguous across registries: \(value)"
        case .invalidManifest(let value):
            return "invalid package manifest: \(value)"
        case .unsafePath(let value):
            return "unsafe package path: \(value)"
        case .unmanagedPackage(let value):
            return "package is not managed by OpenMUX receipts: \(value)"
        case .targetExists(let value):
            return "install target already exists and is not managed by OpenMUX: \(value)"
        case .confirmationRequired:
            return "installation requires confirmation; rerun with --yes to install non-interactively"
        case .cancelled:
            return "installation cancelled"
        }
    }
}

enum OmuxExtensionPackageValidator {
    static func validatePackageID(_ value: String) -> Bool {
        guard value.isEmpty == false, value.first != "-", value.first != "." else { return false }
        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }

    static func validateRelativePath(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.hasPrefix("/") == false,
              trimmed.contains("\\") == false
        else {
            throw OmuxExtensionRegistryError.unsafePath(value)
        }

        for component in trimmed.split(separator: "/").map(String.init) {
            guard component != ".", component != "..", component.hasPrefix(".") == false else {
                throw OmuxExtensionRegistryError.unsafePath(value)
            }
        }
    }
}

struct OmuxExtensionCatalogClient {
    var loadData: (URL) throws -> Data = { url in
        do {
            return try Data(contentsOf: url)
        } catch {
            throw OmuxExtensionRegistryError.fetchFailed(url.absoluteString)
        }
    }

    func packages(kind: OmuxExtensionPackageKind, registryURLs: [String]) throws -> [OmuxExtensionCatalogPackage] {
        var packages: [OmuxExtensionCatalogPackage] = []
        for registryURL in registryURLs {
            let source = try OmuxExtensionRegistrySource(registryURL)
            let data = try loadData(source.catalogURL)
            let catalog = try parseCatalog(data: data, source: source)
            packages.append(contentsOf: catalog.filter { $0.kind == kind })
        }
        return packages
    }

    func manifest(for package: OmuxExtensionCatalogPackage) throws -> (OmuxExtensionPackageManifest, OmuxExtensionRegistrySource) {
        let source = try OmuxExtensionRegistrySource(package.registry)
        let manifestURL = try source.fileURL(for: package.manifestPath)
        let data = try loadData(manifestURL)
        let manifest = try parseManifest(data: data, expected: package)
        return (manifest, source)
    }

    private func parseCatalog(data: Data, source: OmuxExtensionRegistrySource) throws -> [OmuxExtensionCatalogPackage] {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw OmuxExtensionRegistryError.invalidCatalog("catalog is not UTF-8")
        }
        let parseResult = OmuxTOMLParser.parse(contents: contents, sourceURL: source.catalogURL)
        guard let document = parseResult.document, parseResult.diagnostics.isEmpty else {
            throw OmuxExtensionRegistryError.invalidCatalog(parseResult.diagnostics.first?.message ?? "parse failed")
        }
        guard document.value(for: "schema")?.intValue == 1 else {
            throw OmuxExtensionRegistryError.invalidCatalog("schema must be 1")
        }

        return try document.tableNames
            .filter { $0.hasPrefix("packages.") }
            .sorted()
            .map { tableName in
                let rawID = String(tableName.dropFirst("packages.".count))
                let id = Self.normalizedCatalogKey(rawID)
                guard OmuxExtensionPackageValidator.validatePackageID(id) else {
                    throw OmuxExtensionRegistryError.invalidCatalog("invalid package id \(id)")
                }
                guard let kindRaw = document.value(in: tableName, for: "kind")?.stringValue,
                      let kind = OmuxExtensionPackageKind(rawValue: kindRaw),
                      let name = document.value(in: tableName, for: "name")?.stringValue,
                      let description = document.value(in: tableName, for: "description")?.stringValue,
                      let version = document.value(in: tableName, for: "version")?.stringValue,
                      let path = document.value(in: tableName, for: "path")?.stringValue
                else {
                    throw OmuxExtensionRegistryError.invalidCatalog("package \(id) is missing required fields")
                }
                try OmuxExtensionPackageValidator.validateRelativePath(path)
                let tags = stringArray(document.value(in: tableName, for: "tags")) ?? []
                return OmuxExtensionCatalogPackage(
                    kind: kind,
                    id: id,
                    name: name,
                    description: description,
                    version: version,
                    registry: source.originalURL,
                    manifestPath: path,
                    tags: tags
                )
            }
    }

    private static func normalizedCatalogKey(_ value: String) -> String {
        let unescapedQuotes = value.replacingOccurrences(of: "\\\"", with: "\"")
        guard unescapedQuotes.count >= 2,
              let first = unescapedQuotes.first,
              let last = unescapedQuotes.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else {
            return unescapedQuotes
        }

        let start = unescapedQuotes.index(after: unescapedQuotes.startIndex)
        let end = unescapedQuotes.index(before: unescapedQuotes.endIndex)
        return String(unescapedQuotes[start..<end])
    }

    private func parseManifest(data: Data, expected: OmuxExtensionCatalogPackage) throws -> OmuxExtensionPackageManifest {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw OmuxExtensionRegistryError.invalidManifest("manifest is not UTF-8")
        }
        let parseResult = OmuxTOMLParser.parse(contents: contents)
        guard let document = parseResult.document, parseResult.diagnostics.isEmpty else {
            throw OmuxExtensionRegistryError.invalidManifest(parseResult.diagnostics.first?.message ?? "parse failed")
        }
        guard document.value(for: "schema")?.intValue == 1,
              let id = document.value(for: "id")?.stringValue,
              let name = document.value(for: "name")?.stringValue,
              let description = document.value(for: "description")?.stringValue,
              let version = document.value(for: "version")?.stringValue,
              let kindRaw = document.value(for: "kind")?.stringValue,
              let kind = OmuxExtensionPackageKind(rawValue: kindRaw),
              id == expected.id,
              kind == expected.kind
        else {
            throw OmuxExtensionRegistryError.invalidManifest("manifest does not match catalog entry")
        }
        guard OmuxExtensionPackageValidator.validatePackageID(id) else {
            throw OmuxExtensionRegistryError.invalidManifest("invalid package id")
        }

        let hook: OmuxExtensionHookMetadata?
        let plugin: OmuxExtensionPluginMetadata?
        switch kind {
        case .hook:
            guard let hookName = document.value(in: "hook", for: "name")?.stringValue,
                  let categoryRaw = document.value(in: "hook", for: "category")?.stringValue,
                  let category = HookCategory(rawValue: categoryRaw),
                  OmuxExtensionPackageValidator.validatePackageID(hookName)
            else {
                throw OmuxExtensionRegistryError.invalidManifest("hook metadata is invalid")
            }
            hook = OmuxExtensionHookMetadata(name: hookName, category: category)
            plugin = nil
        case .plugin:
            guard let command = document.value(in: "plugin", for: "command")?.stringValue,
                  let entrypoint = document.value(in: "plugin", for: "entrypoint")?.stringValue,
                  OmuxExtensionPackageValidator.validatePackageID(command)
            else {
                throw OmuxExtensionRegistryError.invalidManifest("plugin metadata is invalid")
            }
            try OmuxExtensionPackageValidator.validateRelativePath(entrypoint)
            plugin = OmuxExtensionPluginMetadata(command: command, entrypoint: entrypoint)
            hook = nil
        }

        let files = try document.tableNames
            .filter { $0.hasPrefix("files.") }
            .sorted()
            .map { tableName in
                guard let source = document.value(in: tableName, for: "source")?.stringValue,
                      let target = document.value(in: tableName, for: "target")?.stringValue
                else {
                    throw OmuxExtensionRegistryError.invalidManifest("\(tableName) is missing source or target")
                }
                try OmuxExtensionPackageValidator.validateRelativePath(source)
                try OmuxExtensionPackageValidator.validateRelativePath(target)
                return OmuxExtensionPackageFile(
                    source: source,
                    target: target,
                    executable: document.value(in: tableName, for: "executable")?.boolValue ?? false
                )
            }
        guard files.isEmpty == false else {
            throw OmuxExtensionRegistryError.invalidManifest("package has no files")
        }
        if let entrypoint = plugin?.entrypoint, files.contains(where: { $0.target == entrypoint }) == false {
            throw OmuxExtensionRegistryError.invalidManifest("plugin entrypoint must be installed by a file entry")
        }

        return OmuxExtensionPackageManifest(
            schema: 1,
            id: id,
            name: name,
            description: description,
            version: version,
            license: document.value(for: "license")?.stringValue,
            kind: kind,
            hook: hook,
            plugin: plugin,
            files: files
        )
    }

    private func stringArray(_ value: OmuxTOMLValue?) -> [String]? {
        guard case .array(let values) = value else { return nil }
        return values.compactMap(\.stringValue)
    }
}

struct OmuxExtensionInstaller {
    let hooksDirectoryURL: URL
    let pluginsDirectoryURL: URL
    let receiptsDirectoryURL: URL
    var fileManager: FileManager = .default
    var client: OmuxExtensionCatalogClient = OmuxExtensionCatalogClient()

    init(
        hooksDirectoryURL: URL = OmuxConfigPaths.hooksDirectoryURL,
        pluginsDirectoryURL: URL = OmuxConfigPaths.pluginsDirectoryURL,
        receiptsDirectoryURL: URL = OmuxConfigPaths.baseDirectoryURL.appendingPathComponent("installed", isDirectory: true),
        fileManager: FileManager = .default,
        client: OmuxExtensionCatalogClient = OmuxExtensionCatalogClient()
    ) {
        self.hooksDirectoryURL = hooksDirectoryURL
        self.pluginsDirectoryURL = pluginsDirectoryURL
        self.receiptsDirectoryURL = receiptsDirectoryURL
        self.fileManager = fileManager
        self.client = client
    }

    func discover(kind: OmuxExtensionPackageKind, registryURLs: [String]) throws -> [OmuxExtensionCatalogPackage] {
        try client.packages(kind: kind, registryURLs: registryURLs)
    }

    func planInstall(
        kind: OmuxExtensionPackageKind,
        id: String,
        registryURLs: [String]
    ) throws -> (package: OmuxExtensionCatalogPackage, manifest: OmuxExtensionPackageManifest, plannedTargets: [URL]) {
        let package = try resolvePackage(kind: kind, id: id, registryURLs: registryURLs)
        let (manifest, _) = try client.manifest(for: package)
        let targetRoot = try targetRoot(for: manifest)
        return (package, manifest, manifest.files.map { targetRoot.appendingPathComponent($0.target) })
    }

    func install(
        kind: OmuxExtensionPackageKind,
        id: String,
        registryURLs: [String],
        replacingExistingReceipt: Bool = false
    ) throws -> (package: OmuxExtensionCatalogPackage, manifest: OmuxExtensionPackageManifest, receipt: OmuxExtensionInstallReceipt, plannedTargets: [URL]) {
        let package = try resolvePackage(kind: kind, id: id, registryURLs: registryURLs)
        let (manifest, source) = try client.manifest(for: package)
        let targetRoot = try targetRoot(for: manifest)
        let receiptURL = self.receiptURL(kind: kind, id: id)
        let existingReceipt = try? readReceipt(kind: kind, id: id)

        if existingReceipt == nil, fileManager.fileExists(atPath: targetRoot.path) {
            throw OmuxExtensionRegistryError.targetExists(targetRoot.path)
        }
        if existingReceipt != nil, replacingExistingReceipt == false {
            throw OmuxExtensionRegistryError.targetExists(targetRoot.path)
        }

        let plannedTargets = manifest.files.map { targetRoot.appendingPathComponent($0.target) }
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("omux-extension-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        for file in manifest.files {
            let data = try client.loadData(source.fileURL(for: packageBasePath(package.manifestPath).appendingPathComponent(file.source)))
            let stagedURL = stagingRoot.appendingPathComponent(file.target)
            try fileManager.createDirectory(at: stagedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stagedURL, options: .atomic)
            if file.executable {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
            }
        }

        if let existingReceipt {
            try removeFiles(recordedBy: existingReceipt)
        }
        try fileManager.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        for file in manifest.files {
            let stagedURL = stagingRoot.appendingPathComponent(file.target)
            let destinationURL = targetRoot.appendingPathComponent(file.target)
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: stagedURL, to: destinationURL)
        }

        let receipt = OmuxExtensionInstallReceipt(
            schema: 1,
            kind: kind,
            id: id,
            version: manifest.version,
            registry: package.registry,
            manifestPath: package.manifestPath,
            targetRoot: targetRoot.path,
            installedFiles: plannedTargets.map(\.path),
            installedAt: Date()
        )
        try fileManager.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.omuxExtensionRegistry.encode(receipt).write(to: receiptURL, options: .atomic)
        return (package, manifest, receipt, plannedTargets)
    }

    func uninstall(kind: OmuxExtensionPackageKind, id: String) throws -> OmuxExtensionInstallReceipt {
        let receipt = try readReceipt(kind: kind, id: id)
        try removeFiles(recordedBy: receipt)
        try fileManager.removeItem(at: receiptURL(kind: kind, id: id))
        return receipt
    }

    func update(kind: OmuxExtensionPackageKind, id: String) throws -> (package: OmuxExtensionCatalogPackage, manifest: OmuxExtensionPackageManifest, receipt: OmuxExtensionInstallReceipt, plannedTargets: [URL]) {
        let receipt = try readReceipt(kind: kind, id: id)
        return try install(kind: kind, id: id, registryURLs: [receipt.registry], replacingExistingReceipt: true)
    }

    func receiptURL(kind: OmuxExtensionPackageKind, id: String) -> URL {
        receiptsDirectoryURL
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent("\(id).json")
    }

    func readReceipt(kind: OmuxExtensionPackageKind, id: String) throws -> OmuxExtensionInstallReceipt {
        let url = receiptURL(kind: kind, id: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw OmuxExtensionRegistryError.unmanagedPackage(id)
        }
        return try JSONDecoder.omuxExtensionRegistry.decode(OmuxExtensionInstallReceipt.self, from: Data(contentsOf: url))
    }

    private func resolvePackage(kind: OmuxExtensionPackageKind, id: String, registryURLs: [String]) throws -> OmuxExtensionCatalogPackage {
        let matches = try discover(kind: kind, registryURLs: registryURLs).filter { $0.id == id }
        guard matches.isEmpty == false else {
            throw OmuxExtensionRegistryError.packageNotFound(id)
        }
        guard matches.count == 1 else {
            throw OmuxExtensionRegistryError.ambiguousPackage(id)
        }
        return matches[0]
    }

    private func targetRoot(for manifest: OmuxExtensionPackageManifest) throws -> URL {
        switch manifest.kind {
        case .hook:
            guard let hook = manifest.hook else {
                throw OmuxExtensionRegistryError.invalidManifest("missing hook metadata")
            }
            return hooksDirectoryURL.appendingPathComponent(hook.name, isDirectory: true)
        case .plugin:
            guard let plugin = manifest.plugin else {
                throw OmuxExtensionRegistryError.invalidManifest("missing plugin metadata")
            }
            return pluginsDirectoryURL.appendingPathComponent(plugin.command, isDirectory: true)
        }
    }

    private func removeFiles(recordedBy receipt: OmuxExtensionInstallReceipt) throws {
        for path in receipt.installedFiles.sorted(by: { $0.count > $1.count }) {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            removeEmptyParents(from: url.deletingLastPathComponent(), stopAt: URL(fileURLWithPath: receipt.targetRoot).deletingLastPathComponent())
        }
    }

    private func removeEmptyParents(from url: URL, stopAt stopURL: URL) {
        var current = url.standardizedFileURL
        let stop = stopURL.standardizedFileURL
        while current.path.hasPrefix(stop.path), current != stop {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: current.path), contents.isEmpty else {
                return
            }
            try? fileManager.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    private func packageBasePath(_ manifestPath: String) -> String {
        let nsPath = manifestPath as NSString
        let directory = nsPath.deletingLastPathComponent
        return directory == "." ? "" : directory
    }
}

private extension String {
    func appendingPathComponent(_ component: String) -> String {
        isEmpty ? component : (self as NSString).appendingPathComponent(component)
    }
}

private extension JSONEncoder {
    static var omuxExtensionRegistry: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var omuxExtensionRegistry: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
