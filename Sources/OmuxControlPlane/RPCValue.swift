import Foundation
import OmuxCore

public indirect enum RPCValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([RPCValue])
    case object([String: RPCValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RPCValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: RPCValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
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

    public var prettyPrinted: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            } else {
                return String(value)
            }
        case .bool(let value):
            return String(value)
        case .array, .object, .null:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
                return "null"
            }
            return string
        }
    }
}

public extension RPCValue {
    static func integer(_ value: Int) -> RPCValue {
        .number(Double(value))
    }

    init(_ value: OmuxValue) {
        switch value {
        case .string(let string):
            self = .string(string)
        case .integer(let integer):
            self = .integer(integer)
        case .double(let double):
            self = .number(double)
        case .bool(let bool):
            self = .bool(bool)
        case .array(let array):
            self = .array(array.map(RPCValue.init))
        case .object(let object):
            self = .object(object.mapValues(RPCValue.init))
        case .null:
            self = .null
        }
    }

    var omuxValue: OmuxValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .number(let value):
            if value.rounded(.towardZero) == value,
               value >= Double(Int.min),
               value <= Double(Int.max)
            {
                return .integer(Int(value))
            }
            return .double(value)
        case .bool(let value):
            return .bool(value)
        case .array(let value):
            return .array(value.map(\.omuxValue))
        case .object(let value):
            return .object(value.mapValues(\.omuxValue))
        case .null:
            return .null
        }
    }
}
