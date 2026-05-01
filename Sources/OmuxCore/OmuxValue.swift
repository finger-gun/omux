import Foundation

public indirect enum OmuxValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case array([OmuxValue])
    case object([String: OmuxValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([OmuxValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: OmuxValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    public var integerValue: Int? {
        if case .integer(let value) = self {
            return value
        }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    public var arrayValue: [OmuxValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    public var objectValue: [String: OmuxValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    public var prettyPrinted: String {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .array, .object, .null:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(self),
                  let string = String(data: data, encoding: .utf8)
            else {
                return "null"
            }
            return string
        }
    }
}
