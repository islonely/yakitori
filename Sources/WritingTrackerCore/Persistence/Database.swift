import Foundation

/// A dynamically typed SQL value exchanged with the storage engine.
public enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public static func bool(_ value: Bool) -> SQLValue { .integer(value ? 1 : 0) }
    public static func date(_ value: Date?) -> SQLValue {
        guard let value else { return .null }
        return .real(value.timeIntervalSince1970)
    }
}

extension SQLValue {
    public var intValue: Int? {
        switch self {
        case .integer(let v): return Int(v)
        case .real(let v): return Int(v)
        case .text(let v): return Int(v)
        default: return nil
        }
    }

    public var int64Value: Int64? {
        switch self {
        case .integer(let v): return v
        case .real(let v): return Int64(v)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .real(let v): return v
        case .integer(let v): return Double(v)
        case .text(let v): return Double(v)
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .text(let v): return v
        case .integer(let v): return String(v)
        case .real(let v): return String(v)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .integer(let v): return v != 0
        case .real(let v): return v != 0
        default: return nil
        }
    }

    public var dateValue: Date? {
        switch self {
        case .real(let v): return Date(timeIntervalSince1970: v)
        case .integer(let v): return Date(timeIntervalSince1970: Double(v))
        default: return nil
        }
    }

    public var dataValue: Data? {
        switch self {
        case .blob(let v): return v
        case .text(let v): return v.data(using: .utf8)
        default: return nil
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

public typealias SQLParameters = [SQLValue]

/// A single result row with typed accessors.
public struct Row {
    private let storage: [String: SQLValue]
    public init(_ storage: [String: SQLValue]) { self.storage = storage }

    public subscript(_ column: String) -> SQLValue { storage[column] ?? .null }

    public func int(_ column: String) -> Int? { self[column].intValue }
    public func int64(_ column: String) -> Int64? { self[column].int64Value }
    public func double(_ column: String) -> Double? { self[column].doubleValue }
    public func string(_ column: String) -> String? { self[column].stringValue }
    public func bool(_ column: String) -> Bool? { self[column].boolValue }
    public func date(_ column: String) -> Date? { self[column].dateValue }
    public func data(_ column: String) -> Data? { self[column].dataValue }
    public func hasValue(_ column: String) -> Bool { !self[column].isNull }

    public var columnNames: [String] { Array(storage.keys) }

    /// Decodes a JSON-encoded text column into a `Codable` value.
    public func decodeJSON<T: Decodable>(_ type: T.Type, from column: String, decoder: JSONDecoder = JSONDecoder()) -> T? {
        guard let text = string(column), let data = text.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

/// Storage abstraction so the engine can be swapped out later.
public protocol Database: AnyObject {
    @discardableResult
    func execute(_ sql: String, _ params: SQLParameters) throws -> Int
    func query(_ sql: String, _ params: SQLParameters) throws -> [Row]
    func queryOne(_ sql: String, _ params: SQLParameters) throws -> Row?
    func scalar(_ sql: String, _ params: SQLParameters) throws -> SQLValue?
    func transaction<T>(_ body: () throws -> T) throws -> T
    var lastInsertRowID: Int64 { get }
    func close()
}

public extension Database {
    @discardableResult
    func execute(_ sql: String) throws -> Int { try execute(sql, []) }
    func query(_ sql: String) throws -> [Row] { try query(sql, []) }
    func queryOne(_ sql: String) throws -> Row? { try queryOne(sql, []) }
    func scalar(_ sql: String) throws -> SQLValue? { try scalar(sql, []) }
}
