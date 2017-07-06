//
//  FastJSONDecoder.swift
//  HoliduKit
//
//  Created by Tobias Haeberle on 05.07.17.
//  Copyright © 2017 Holidu GmbH. All rights reserved.
//

import Foundation


public final class FastJSONDecoder {
    public enum AllocationStrategy {
        case single
        case dynamic
        
        fileprivate var sajson_strategy: sajson_swift.AllocationStrategy {
            switch self {
            case .single: return .single
            case .dynamic: return .dynamic
            }
        }
    }
    
    public enum DateDecodingStrategy {
        /// Defer to `Date` for decoding. This is the default strategy.
        case deferredToDate
        
        /// Decode the `Date` as a UNIX timestamp from a JSON number.
        case secondsSince1970
        
        /// Decode the `Date` as UNIX millisecond timestamp from a JSON number.
        case millisecondsSince1970
        
        /// Decode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(OSX 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601
        
        /// Decode the `Date` as a string parsed by the given formatter.
        case formatted(DateFormatter)
        
        /// Decode the `Date` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Date)
    }
    
    /// The strategy to use for decoding `Data` values.
    public enum DataDecodingStrategy {
        /// Defer to `Data` for decoding.
        case deferredToData
        
        /// Decode the `Data` from a Base64-encoded string. This is the default strategy.
        case base64
        
        /// Decode the `Data` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Data)
    }
    
    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatDecodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`
        
        /// Decode the values from the given representation strings.
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }
    
    /// The memory allocation strategy used in decoding
    public var allocationStrategy: AllocationStrategy = .dynamic
    
    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    public var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    
    /// The strategy to use in decoding binary data. Defaults to `.base64`.
    public var dataDecodingStrategy: DataDecodingStrategy = .base64
    
    /// The strategy to use in decoding non-conforming numbers. Defaults to `.throw`.
    public var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
    
    /// Contextual user-provided information for use during decoding.
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    
    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dateDecodingStrategy: DateDecodingStrategy
        let dataDecodingStrategy: DataDecodingStrategy
        let nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        let userInfo: [CodingUserInfoKey : Any]
    }
    
    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        return _Options(dateDecodingStrategy: dateDecodingStrategy,
                        dataDecodingStrategy: dataDecodingStrategy,
                        nonConformingFloatDecodingStrategy: nonConformingFloatDecodingStrategy,
                        userInfo: userInfo)
    }
    
    public init() { }
    
    
    public func decode<T : _Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let doc: Document
        do {
            doc = try parse(allocationStrategy: allocationStrategy.sajson_strategy, input: data)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not valid JSON.", underlyingError: error))
        }
        
        return try doc.withRootValueReader() { value in
            let decoder = _JSONDecoder(referencing: value, options: options)
            return try T(from: decoder)
        }
    }
}

fileprivate struct _JSONDecoderContainerStorage {
    private(set) var containers: [ValueReader] = []
    
    fileprivate var count: Int {
        return self.containers.count
    }
    
    fileprivate var topContainer: ValueReader {
        precondition(self.containers.count > 0, "Empty container stack.")
        return self.containers.last!
    }
    
    fileprivate mutating func push(container: ValueReader) {
        self.containers.append(container)
    }
    
    fileprivate mutating func popContainer() {
        precondition(self.containers.count > 0, "Empty container stack.")
        self.containers.removeLast()
    }
}

fileprivate class _JSONDecoder: Decoder {
    private(set) public var codingPath: [CodingKey] = []
    
    fileprivate var storage: _JSONDecoderContainerStorage
    
    public var userInfo: [CodingUserInfoKey : Any] { return options.userInfo }
    
    fileprivate let options: FastJSONDecoder._Options
    
    fileprivate init(referencing container: ValueReader, at codingPath: [CodingKey] = [], options: FastJSONDecoder._Options) {
        self.storage = _JSONDecoderContainerStorage()
        self.options = options
        self.codingPath = codingPath
        self.storage.push(container: container)
    }
    
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        guard !storage.topContainer.isNull else {
            throw DecodingError.valueNotFound(KeyedDecodingContainer<Key>.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Cannot get keyed decoding container -- found null value instead."))
        }
        
        guard case .object(let objectReader) = storage.topContainer else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: ObjectReader.self, reality: self.storage.topContainer)
        }
        
        let container = _JSONKeyedDecodingContainer<Key>(referencing: self, wrapping: objectReader)
        return KeyedDecodingContainer(container)
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !storage.topContainer.isNull else {
            throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                              DecodingError.Context(codingPath: self.codingPath,
                                                                    debugDescription: "Cannot get unkeyed decoding container -- found null value instead."))
        }
        
        guard case .array(let arrayReader) = self.storage.topContainer else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: ArrayReader.self, reality: self.storage.topContainer)
        }
        
        return _JSONUnkeyedDecodingContainer(referencing: self, wrapping: arrayReader)
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        return self
    }
    
    fileprivate func with<T>(pushedKey key: CodingKey, _ work: () throws -> (T)) rethrows -> T {
        codingPath.append(key)
        let ret: T = try work()
        codingPath.removeLast()
        return ret
    }
}

// MARK: - Concrete Value Representations
extension _JSONDecoder {
    /// Returns the given value unboxed from a value reader.
    fileprivate func unbox(_ value: ValueReader, as type: Bool.Type) throws -> Bool? {
        guard !value.isNull else { return nil }
        guard case .bool(let unboxedValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: Bool.self, reality: value)
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Int.Type) throws -> Int? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: type, reality: value)
        }
        
        guard let unboxedValue = Int(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Int8.Type) throws -> Int8? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: type, reality: value)
        }
        
        guard let int8Value = Int8(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return int8Value
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Int16.Type) throws -> Int16? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: type, reality: value)
        }
        
        guard let unboxedValue = Int16(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Int32.Type) throws -> Int32? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: Int.self, reality: value)
        }
        
        return intValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Int64.Type) throws -> Int64? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: type, reality: value)
        }
        
        guard let unboxedValue = Int64(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: UInt.Type) throws -> UInt? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: UInt.self, reality: value)
        }
        
        guard let unboxedValue = UInt(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: UInt8.Type) throws -> UInt8? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: UInt8.self, reality: value)
        }
        
        guard let unboxedValue = UInt8(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: UInt16.Type) throws -> UInt16? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: UInt16.self, reality: value)
        }
        
        guard let unboxedValue = UInt16(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: UInt32.Type) throws -> UInt32? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: UInt32.self, reality: value)
        }
        
        guard let unboxedValue = UInt32(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: UInt64.Type) throws -> UInt64? {
        guard !value.isNull else { return nil }
        
        guard case let .integer(intValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: UInt64.self, reality: value)
        }
        
        guard let unboxedValue = UInt64(exactly: intValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(intValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Float.Type) throws -> Float? {
        guard !value.isNull else { return nil }
        
        guard case let .double(doubleValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: Float.self, reality: value)
        }
        
        guard let unboxedValue = Float(exactly: doubleValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(doubleValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: Double.Type) throws -> Double? {
        guard !value.isNull else { return nil }
        
        guard case let .double(doubleValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: Double.self, reality: value)
        }
        
        guard let unboxedValue = Double(exactly: doubleValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Parsed JSON number <\(doubleValue)> does not fit in \(type)."))
        }
        
        return unboxedValue
    }
    
    fileprivate func unbox(_ value: ValueReader, as type: String.Type) throws -> String? {
        guard !value.isNull else { return nil }
        
        guard case let .string(stringValue) = value else {
            throw DecodingError._typeMismatch(at: codingPath, expectation: String.self, reality: value)
        }
        
        return stringValue
    }
    
    fileprivate func unbox<T: _Decodable>(_ value: ValueReader, as type: T.Type) throws -> T? {
        guard !value.isNull else { return nil }
        
        storage.push(container: value)
        let ret = try T(from: self)
        storage.popContainer()
        
        return ret
    }
}

// MARK: - JSONKeyedDecodingContainer

fileprivate struct _JSONKeyedDecodingContainer<K : CodingKey> : KeyedDecodingContainerProtocol {
    typealias Key = K
    
    // reference to the decoder
    private let decoder: _JSONDecoder
    
    // the reference to the object reader we are using
    fileprivate let objectReader: ObjectReader
    
    let codingPath: [CodingKey]
    
    init(referencing decoder: _JSONDecoder, wrapping reader: ObjectReader) {
        self.decoder = decoder
        self.objectReader = reader
        self.codingPath = decoder.codingPath
    }
    
    var allKeys: [Key] { return Array(objectReader.asDictionary().keys.flatMap { Key(stringValue: $0) }) }
    
    func contains(_ key: K) -> Bool {
        return objectReader.contains(where: { $0.0 == key.stringValue  })
    }
    
    func decode(_ type: Bool.Type, forKey key: K) throws -> Bool {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Bool.self) else {
                throw DecodingError.valueNotFound(Bool.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    
    func decode(_ type: Int.Type, forKey key: K) throws -> Int {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Int.self) else {
                throw DecodingError.valueNotFound(Int.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    
    func decode(_ type: Int8.Type, forKey key: K) throws -> Int8 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Int8.self) else {
                throw DecodingError.valueNotFound(Int8.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: Int16.Type, forKey key: K) throws -> Int16 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Int16.self) else {
                throw DecodingError.valueNotFound(Int16.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: Int32.Type, forKey key: K) throws -> Int32 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Int32.self) else {
                throw DecodingError.valueNotFound(Int32.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: Int64.Type, forKey key: K) throws -> Int64 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: type) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    
    func decode(_ type: UInt.Type, forKey key: K) throws -> UInt {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: type) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: UInt8.self) else {
                throw DecodingError.valueNotFound(UInt8.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: UInt16.self) else {
                throw DecodingError.valueNotFound(UInt16.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: UInt32.self) else {
                throw DecodingError.valueNotFound(UInt32.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: UInt64.self) else {
                throw DecodingError.valueNotFound(UInt64.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: Float.Type, forKey key: K) throws -> Float {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Float.self) else {
                throw DecodingError.valueNotFound(Float.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: Double.Type, forKey key: K) throws -> Double {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: Double.self) else {
                throw DecodingError.valueNotFound(Double.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decode(_ type: String.Type, forKey key: K) throws -> String {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: String.self) else {
                throw DecodingError.valueNotFound(String.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func decodeNil(forKey key: K) throws -> Bool {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return entry.isNull
    }
    
    func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T : _Decodable {
        guard let entry = objectReader[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."))
        }
        
        return try decoder.with(pushedKey: key) {
            guard let value = try decoder.unbox(entry, as: T.self) else {
                throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected \(type) value but found null instead."))
            }
            
            return value
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        return try decoder.with(pushedKey: key) {
            guard let value = objectReader[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: codingPath,
                                                                      debugDescription: "Cannot get \(KeyedDecodingContainer<NestedKey>.self) -- no value found for key \"\(key.stringValue)\""))
            }
            
            guard case let .object(nestedObjectReader) = value else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: ObjectReader.self, reality: value)
            }
            
            let container = _JSONKeyedDecodingContainer<NestedKey>(referencing: decoder, wrapping: nestedObjectReader)
            return KeyedDecodingContainer(container)
        }
    }
    
    func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        return try decoder.with(pushedKey: key) {
            guard let value = objectReader[key.stringValue] else {
                throw DecodingError.keyNotFound(key,
                                                DecodingError.Context(codingPath: codingPath,
                                                                      debugDescription: "Cannot get \(UnkeyedDecodingContainer.self) -- no value found for key \"\(key.stringValue)\""))
            }
            
            guard case let .array(nestedArrayReader) = value else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: ArrayReader.self, reality: value)
            }
            
            return _JSONUnkeyedDecodingContainer(referencing: self.decoder, wrapping: nestedArrayReader)
        }
    }
    
    private func _superDecoder(forKey key: CodingKey) throws -> Decoder {
        return self.decoder.with(pushedKey: key) {
            let value: ValueReader = objectReader[key.stringValue] ?? .null
            return _JSONDecoder(referencing: value, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }
    
    func superDecoder() throws -> Decoder {
        return try _superDecoder(forKey: _JSONKey.super)
    }
    
    public func superDecoder(forKey key: Key) throws -> Decoder {
        return try _superDecoder(forKey: key)
    }
}

// MARK: - JSONUnkeyedDecodingContainer
fileprivate struct _JSONUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    
    
    
    /// A reference to the decoder we're reading from.
    private let decoder: _JSONDecoder
    
    /// A reference to the container we're reading from.
    private let container: ArrayReader
    
    /// The path of coding keys taken to get to this point in decoding.
    private(set) public var codingPath: [CodingKey]
    
    /// The index of the element we're about to decode.
    private(set) public var currentIndex: Int
    
    
    public var count: Int? {
        return container.count
    }
    
    
    public var isAtEnd: Bool {
        return currentIndex >= self.count!
    }
    
    // MARK: - Initialization
    /// Initializes `self` by referencing the given decoder and container.
    fileprivate init(referencing decoder: _JSONDecoder, wrapping container: ArrayReader) {
        self.decoder = decoder
        self.container = container
        self.codingPath = decoder.codingPath
        self.currentIndex = 0
    }
    
    
    mutating func decodeNil() throws -> Bool {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(Any?.self, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        if self.container[self.currentIndex].isNull {
            self.currentIndex += 1
            return true
        } else {
            return false
        }
    }
    
    
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Bool.self) else {
                // TODO: Check if this error message is correct! Key is alreay pushed on decoder's coding path?
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    
    mutating func decode(_ type: Int.Type) throws -> Int {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: Int8.Type) throws -> Int8 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int8.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: Int16.Type) throws -> Int16 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int16.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: Int32.Type) throws -> Int32 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int32.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: Int64.Type) throws -> Int64 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Int64.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: UInt.Type) throws -> UInt {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt8.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt16.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt32.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: UInt64.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: Float.Type) throws -> Float {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Float.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: Double.Type) throws -> Double {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: Double.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode(_ type: String.Type) throws -> String {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: String.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func decode<T : _Decodable>(_ type: T.Type) throws -> T {
        guard !self.isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Unkeyed container is at end."))
        }
        
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard let decoded = try self.decoder.unbox(self.container[self.currentIndex], as: T.self) else {
                throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.decoder.codingPath + [_JSONKey(index: self.currentIndex)], debugDescription: "Expected \(type) but found null instead."))
            }
            
            self.currentIndex += 1
            return decoded
        }
    }
    
    public mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end."))
            }
            
            let value = self.container[self.currentIndex]
            guard !value.isNull else {
                throw DecodingError.valueNotFound(KeyedDecodingContainer<NestedKey>.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get keyed decoding container -- found null value instead."))
            }
            
            guard case .object(let objectReader) = value  else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: ObjectReader.self, reality: value)
            }
            
            self.currentIndex += 1
            let container = _JSONKeyedDecodingContainer<NestedKey>(referencing: self.decoder, wrapping: objectReader)
            return KeyedDecodingContainer(container)
        }
    }
    
    public mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end."))
            }
            
            let value = self.container[self.currentIndex]
            guard !value.isNull else {
                throw DecodingError.valueNotFound(UnkeyedDecodingContainer.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get keyed decoding container -- found null value instead."))
            }
            
            guard case .array(let arrayReader) = value else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: ArrayReader.self, reality: value)
            }
            
            self.currentIndex += 1
            return _JSONUnkeyedDecodingContainer(referencing: self.decoder, wrapping: arrayReader)
        }
    }
    
    public mutating func superDecoder() throws -> Decoder {
        return try self.decoder.with(pushedKey: _JSONKey(index: self.currentIndex)) {
            guard !self.isAtEnd else {
                throw DecodingError.valueNotFound(Decoder.self,
                                                  DecodingError.Context(codingPath: self.codingPath,
                                                                        debugDescription: "Cannot get superDecoder() -- unkeyed container is at end."))
            }
            
            let value = self.container[self.currentIndex]
            self.currentIndex += 1
            return _JSONDecoder(referencing: value, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }
}

extension _JSONDecoder : SingleValueDecodingContainer {
    // MARK: SingleValueDecodingContainer Methods
    private func expectNonNull<T>(_ type: T.Type) throws {
        guard !self.decodeNil() else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected \(type) but found null value instead."))
        }
    }
    
    public func decodeNil() -> Bool {
        return self.storage.topContainer.isNull
    }
    
    public func decode(_ type: Bool.Type) throws -> Bool {
        try expectNonNull(Bool.self)
        return try self.unbox(self.storage.topContainer, as: Bool.self)!
    }
    
    public func decode(_ type: Int.Type) throws -> Int {
        try expectNonNull(Int.self)
        return try self.unbox(self.storage.topContainer, as: Int.self)!
    }
    
    public func decode(_ type: Int8.Type) throws -> Int8 {
        try expectNonNull(Int8.self)
        return try self.unbox(self.storage.topContainer, as: Int8.self)!
    }
    
    public func decode(_ type: Int16.Type) throws -> Int16 {
        try expectNonNull(Int16.self)
        return try self.unbox(self.storage.topContainer, as: Int16.self)!
    }
    
    public func decode(_ type: Int32.Type) throws -> Int32 {
        try expectNonNull(Int32.self)
        return try self.unbox(self.storage.topContainer, as: Int32.self)!
    }
    
    public func decode(_ type: Int64.Type) throws -> Int64 {
        try expectNonNull(Int64.self)
        return try self.unbox(self.storage.topContainer, as: Int64.self)!
    }
    
    public func decode(_ type: UInt.Type) throws -> UInt {
        try expectNonNull(UInt.self)
        return try self.unbox(self.storage.topContainer, as: UInt.self)!
    }
    
    public func decode(_ type: UInt8.Type) throws -> UInt8 {
        try expectNonNull(UInt8.self)
        return try self.unbox(self.storage.topContainer, as: UInt8.self)!
    }
    
    public func decode(_ type: UInt16.Type) throws -> UInt16 {
        try expectNonNull(UInt16.self)
        return try self.unbox(self.storage.topContainer, as: UInt16.self)!
    }
    
    public func decode(_ type: UInt32.Type) throws -> UInt32 {
        try expectNonNull(UInt32.self)
        return try self.unbox(self.storage.topContainer, as: UInt32.self)!
    }
    
    public func decode(_ type: UInt64.Type) throws -> UInt64 {
        try expectNonNull(UInt64.self)
        return try self.unbox(self.storage.topContainer, as: UInt64.self)!
    }
    
    public func decode(_ type: Float.Type) throws -> Float {
        try expectNonNull(Float.self)
        return try self.unbox(self.storage.topContainer, as: Float.self)!
    }
    
    public func decode(_ type: Double.Type) throws -> Double {
        try expectNonNull(Double.self)
        return try self.unbox(self.storage.topContainer, as: Double.self)!
    }
    
    public func decode(_ type: String.Type) throws -> String {
        try expectNonNull(String.self)
        return try self.unbox(self.storage.topContainer, as: String.self)!
    }
    
    public func decode<T : _Decodable>(_ type: T.Type) throws -> T {
        try expectNonNull(T.self)
        return try self.unbox(self.storage.topContainer, as: T.self)!
    }
}

//===----------------------------------------------------------------------===//
// Shared Key Types
//===----------------------------------------------------------------------===//
fileprivate struct _JSONKey : CodingKey {
    public var stringValue: String
    public var intValue: Int?
    
    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
    
    fileprivate init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
    
    fileprivate static let `super` = _JSONKey(stringValue: "super")!
}


//===----------------------------------------------------------------------===//
// Error Utilities
//===----------------------------------------------------------------------===//
fileprivate extension DecodingError {
    /// Returns a `.typeMismatch` error describing the expected type.
    ///
    /// - parameter path: The path of `CodingKey`s taken to decode a value of this type.
    /// - parameter expectation: The type expected to be encountered.
    /// - parameter reality: The value that was encountered instead of the expected type.
    /// - returns: A `DecodingError` with the appropriate path and debug description.
    static func _typeMismatch(at path: [CodingKey], expectation: Any.Type, reality: ValueReader) -> DecodingError {
        let description = "Expected to decode \(_description(of: expectation)) but found \(_typeDescription(of: reality)) instead."
        return .typeMismatch(expectation, Context(codingPath: path, debugDescription: description))
    }
    
    /// Returns a description of the type of `value` appropriate for an error message.
    ///
    /// - parameter value: The value whose type to describe.
    /// - returns: A string describing `value`.
    /// - precondition: `value` is one of the types below.
    fileprivate static func _typeDescription(of value: ValueReader) -> String {
        switch value {
        case .null: return "a null value"
        case .integer(_): return "an integer"
        case .double(_): return "a double"
        case .bool(_): return "a boolean"
        case .string(_): return "a string"
        case .array(_): return "an array"
        case .object(_): return "an object"
        }
    }
    
    /// Returns a description of `type` appropriate for an error message.
    ///
    /// - parameter type: The type to describe.
    /// - returns: A string describing `value`.
    /// - precondition: `value` is one of the types below.
    fileprivate static func _description(of type: Any.Type) -> String {
        switch type {
        case is ObjectReader.Type: return "an object"
        case is ArrayReader.Type: return "an array"
        default: return String(describing: type)
        }
    }
}

extension ValueReader {
    fileprivate var isNull: Bool {
        switch self {
        case .null: return true
        default: return false
        }
    }
}
