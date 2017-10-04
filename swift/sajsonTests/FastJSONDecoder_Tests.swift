//
//  FastJSONDecoder_Tests.swift
//  sajson
//
//  Created by Tobias Haeberle on 06.07.17.
//  Copyright © 2017 Chad Austin. All rights reserved.
//

import Foundation
import XCTest
@testable import sajson_swift

func data(_ string: String) -> Data {
    return string.data(using: .utf8)!
}

struct TestCodingKey: CodingKey, ExpressibleByStringLiteral, CustomStringConvertible {
    var stringValue: String
    var intValue: Int? { return Int(stringValue) }
    
    init(stringValue string: String) { stringValue = string }
    
    init?(intValue: Int) {
        self.init(stringValue: "\(intValue)")
    }
    
    init(stringLiteral value: String) {
        self.init(stringValue: value)
    }
    
    init(unicodeScalarLiteral value: String) {
        self.init(stringValue: value)
    }
    
    init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringValue: value)
    }
    
    init(_ string: String) { self.init(stringValue: string) }
    
    var description: String { return "TestCodingKey(\"\(stringValue)\")" }
}

struct DeferredDecodable: Decodable {
    static var decodeHandler: (Decoder) throws -> () = { _ in }
    init(from decoder: Decoder) throws {
        try DeferredDecodable.decodeHandler(decoder)
    }
}



class FastJSONDecoder_Tests: XCTestCase {
    
    
    func test_empty_int_array() throws {
        let _ : [Int] = try FastJSONDecoder().decode([Int].self, from: data("[]"))
    }
    
    func test_int_array() throws {
        let array: [Int] = try FastJSONDecoder().decode([Int].self, from: data("[10,5,8]"))
        XCTAssertEqual([ 10, 5, 8], array)
    }
    
    func test_empty_string_array() throws {
        let _ : [String] = try FastJSONDecoder().decode([String].self, from: data("[]"))
    }
    
    func test_string_array() throws {
        let array: [String] = try FastJSONDecoder().decode([String].self, from: data("[\"Kai\",\"Andrei\",\"Florian\",\"Tobias\"]"))
        XCTAssertEqual([ "Kai", "Andrei", "Florian", "Tobias"], array)
    }
    
    func test_empty_object() throws {
        let object: [String: String] = try FastJSONDecoder().decode([String: String].self, from: data("{}"))
        XCTAssertTrue(object.isEmpty)
    }
    
    func test_mismatch_expecting_object_getting_array() throws {
        do {
            let _: [String: String] = try FastJSONDecoder().decode([String: String].self, from: data("[]"))
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(_, let context):
                XCTAssertEqual(context.debugDescription, "Expected to decode an object but found an array instead.")
            default: throw error
            }
        }
    }
    
    func test_mismatch_expecting_array_getting_object() throws {
        do {
            let _: [String] = try FastJSONDecoder().decode([String].self, from: data("{}"))
        } catch let error as DecodingError {
            switch error {
            case .typeMismatch(_, let context):
                XCTAssertEqual(context.debugDescription, "Expected to decode an array but found an object instead.")
            default: throw error
            }
        }
    }
    
    
    func test_decoding_int() throws {
        let input = "{\"value\":10}"
        let expectedOutput: Int = 10
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            
            let parsedInt = try container.decode(Int.self, forKey: "value")
            XCTAssertEqual(parsedInt, expectedOutput)
        }
        
        let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
    }
    
    func test_decoding_string() throws {
        let input = "{\"value\":\"Hello, world!\"}"
        let expectedOutput: String = "Hello, world!"
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let parsedValue = try container.decode(String.self, forKey: "value")
            XCTAssertEqual(parsedValue, expectedOutput)
        }
        
        let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
    }
    
    func test_decoding_float() throws {
        let input = "{\"value\": 90.32}"
        let expectedOutput: Float = 90.32
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let parsedInt = try container.decode(Float.self, forKey: "value")
            XCTAssertEqual(parsedInt, expectedOutput, accuracy: 0.01)
        }
        
        let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
    }
    
    func test_decoding_int_as_float() throws {
        let input = "{\"value\": 90}"
        let expectedOutput: Float = 90.0
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let parsedValue = try container.decode(Float.self, forKey: "value")
            XCTAssertEqual(parsedValue, expectedOutput, accuracy: 0.1)
        }
        
        do {
            let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
        } catch { print(error); throw error }
    }
    
    func test_decoding_int_as_double() throws {
        let input = "{\"value\": 90}"
        let expectedOutput: Double = 90.0
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let parsedValue = try container.decode(Double.self, forKey: "value")
            XCTAssertEqual(parsedValue, expectedOutput, accuracy: 0.1)
        }
        
        do {
            let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
        } catch { print(error); throw error }
    }
    
    func test_decoding_string_missing_key() throws {
        let input = "{\"value\":\"Hello, world!\"}"
        let expectedDebugDescription: String = "No value associated with key TestCodingKey(\"wrong_key\") (\"wrong_key\")."
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let _ = try container.decode(String.self, forKey: "wrong_key")
            XCTFail("Should throw before.")
        }
        
        do {
        let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
        } catch let error as DecodingError {
            guard case .keyNotFound(let key, let context) = error else {
                throw error
            }
            
            XCTAssertEqual(key.stringValue, "wrong_key")
            XCTAssertEqual(context.debugDescription, expectedDebugDescription)
            XCTAssertEqual(context.codingPath.map { $0.stringValue }, [])
        }
    }
    
    func test_decoding_string_type_mismatch() throws {
        let input = "{\"value\":10}"
        let expectedDebugDescription: String = "Expected to decode String but found an integer instead."
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let _ = try container.decode(String.self, forKey: "value")
            XCTFail("Should throw before.")
        }
        
        do {
            let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
        } catch let error as DecodingError {
            guard case .typeMismatch(_, let context) = error else {
                throw error
            }
            
            XCTAssertEqual(context.debugDescription, expectedDebugDescription)
            XCTAssertEqual(context.codingPath.map { $0.stringValue }, ["value"])
        }
    }
    
    func test_decoding_missing_bool_from_array() throws {
        let input = "{\"array\": [ true, null ]}"
        let expectedDebugDescription: String = "Expected Bool but found null instead."
        
        
        DeferredDecodable.decodeHandler = { decoder in
            let keyedContainer = try decoder.container(keyedBy: TestCodingKey.self)
            var container = try keyedContainer.nestedUnkeyedContainer(forKey: "array")
            XCTAssertEqual(true, try container.decode(Bool.self)) // true
            let _ = try container.decode(Bool.self) // null
            XCTFail("Should throw before.")
        }
        
        do {
            let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
        } catch let error as DecodingError {
            guard case .valueNotFound(_, let context) = error else {
                throw error
            }
            
            XCTAssertEqual(context.debugDescription, expectedDebugDescription)
            XCTAssertEqual(context.codingPath.map { $0.stringValue }, ["array", "Index 1"])
        }
    }
    
    func test_decoding_missing_nested_string() throws {
        let input = "{\"data\": {\"name\": null }}"
        let expectedDebugDescription: String = "Expected String value but found null instead."
        
        
        DeferredDecodable.decodeHandler = { decoder in
            let keyedContainer = try decoder.container(keyedBy: TestCodingKey.self)
            let nestedContainer = try keyedContainer.nestedContainer(keyedBy: TestCodingKey.self, forKey: "data")
            let _: String = try nestedContainer.decode(String.self, forKey: "name")
        }
        
        do {
            let _: DeferredDecodable = try FastJSONDecoder().decode(DeferredDecodable.self, from: data(input))
        } catch let error as DecodingError {
            guard case .valueNotFound(_, let context) = error else {
                throw error
            }
            
            XCTAssertEqual(context.debugDescription, expectedDebugDescription)
            XCTAssertEqual(context.codingPath.map { $0.stringValue }, ["data", "name"])
        }
    }
    
    
    func test_object() throws {
        let input: Data = data("{\"hello\": \"world\", \"hello2\": null}")
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            XCTAssertEqual(try container.decode(String.self, forKey: "hello"), "world")
            XCTAssertTrue(try container.decodeNil(forKey: "hello2"))
        }
        
        let _ = try FastJSONDecoder().decode(DeferredDecodable.self, from: input)
    }
    
    func test_date_defferedToDate() throws {
        let date = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate)
        let inputString = "{\"date\": \(date.timeIntervalSinceReferenceDate)}"
        let input : Data = data(inputString)
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            let parsedDate = try container.decode(Date.self, forKey: "date")
            XCTAssertEqual("\(parsedDate.timeIntervalSinceReferenceDate)", "\(date.timeIntervalSinceReferenceDate)")
        }
        
        let decoder = FastJSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        _ = try decoder.decode(DeferredDecodable.self, from: input)
    }
    
    func test_date_secondsSince1970() throws {
        let date = Date(timeIntervalSince1970: TimeInterval(Int(Date().timeIntervalSince1970)))
        let input : Data = data("{\"date\": \(date.timeIntervalSince1970)}")
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            XCTAssertEqual(try container.decode(Date.self, forKey: "date"), date)
        }
        
        let decoder = FastJSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        _ = try decoder.decode(DeferredDecodable.self, from: input)
    }
    
    func test_date_miliSecondsSince1970() throws {
        let date = Date(timeIntervalSince1970: round(Date().timeIntervalSince1970 * 1000)/1000)
        let input : Data = data("{\"date\": \(date.timeIntervalSince1970 * 1000)}")
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            XCTAssertEqual(try container.decode(Date.self, forKey: "date"), date)
        }
        
        let decoder = FastJSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        _ = try decoder.decode(DeferredDecodable.self, from: input)
    }
    
    func test_date_iso() throws {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = .withInternetDateTime
        let isoString = isoFormatter.string(from: Date())
        let date  : Date = isoFormatter.date(from: isoString)!
        let input : Data = data("{\"date\": \"\(isoString)\"}")
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            XCTAssertEqual(try container.decode(Date.self, forKey: "date"), date)
        }
        
        let decoder = FastJSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(DeferredDecodable.self, from: input)
    }
    
    func test_date_formatted() throws {
        
        let dateFormatter = DateFormatter()
        let formattedDate = dateFormatter.string(from: Date())
        let input: Data = data("{\"date\": \"\(formattedDate)\"}")
        let date = dateFormatter.date(from: formattedDate)!
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            XCTAssertEqual(try container.decode(Date.self, forKey: "date"), date)
        }
        
        let decoder = FastJSONDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        _ = try decoder.decode(DeferredDecodable.self, from: input)
    }
    
    
    func test_date_custom() throws {
        let calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        var datecomponents = DateComponents()
        datecomponents.calendar = calendar
        datecomponents.year = 2017
        datecomponents.month = 3
        datecomponents.day = 28
        
        let date = datecomponents.date!
        let input: Data = data("{\"date\": \"2017-03-28\"}")
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.container(keyedBy: TestCodingKey.self)
            XCTAssertEqual(try container.decode(Date.self, forKey: "date"), date)
        }
        
        let decoder = FastJSONDecoder()
        decoder.dateDecodingStrategy = .custom({ decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let components = string.components(separatedBy: "-").flatMap { Int($0) }
            guard components.count == 3 else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected date in format YYYY-MM-DD but got: \"\(string)\".") }
            
            var dateComponents = DateComponents()
            dateComponents.calendar = calendar
            dateComponents.year = components[0]
            dateComponents.month = components[1]
            dateComponents.day = components[2]
            
            guard let date = dateComponents.date else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Could not convert string \"\(string)\" to date in format YYYY-MM-DD.") }
            return date
        })
        _ = try decoder.decode(DeferredDecodable.self, from: input)
    }
    
    // MARK: Benchmarks
    
    func test_large_json_benchmark_parse_only() {
        let largeJsonData = createLargeTestJsonData(objectCount: 1000)
        
        measure {
            _ = try! parse(allocationStrategy: .single, input: largeJsonData)
        }
    }
    
    func test_large_json_benchmark_parse_only_legacy() {
        let largeJsonData = createLargeTestJsonData(objectCount: 1000)
        
        measure {
            _ = try! JSONSerialization.jsonObject(with: largeJsonData, options: [])
        }
    }
    
    
    func test_large_json_benchmark_all() {
        let largeJsonData = createLargeTestJsonData(objectCount: 1000)
        
        DeferredDecodable.decodeHandler = { decoder in
            let container = try decoder.unkeyedContainer()
            XCTAssertEqual(container.count!, 1000)
        }
        
        measure {
            let decoder = FastJSONDecoder()
            decoder.allocationStrategy = .single
            let _ = try! decoder.decode(DeferredDecodable.self, from: largeJsonData)
        }
    }
    
    func test_large_json_benchmark_all_legacy() {
        let largeJsonData = createLargeTestJsonData(objectCount: 1000)
        
        measure {
            let result: Any = try! JSONSerialization.jsonObject(with: largeJsonData, options: [])
            let array = result as! [[String: Any]]
            XCTAssertEqual(array.count, 1000)
        }
    }
    
    // MARK: Helpers
    
    func createLargeTestJsonData(objectCount: Int) -> Data {
        var largeArray = [[String: Any]]()
        for _ in 0..<objectCount {
            largeArray.append(createTestJsonObject())
        }
        return try! JSONSerialization.data(withJSONObject: largeArray)
    }
    
    func createTestJsonObject() -> [String: Any] {
        var jsonDict =  [String: Any]()
        for i in 0..<100 {
            jsonDict["\(i)"] = randomString()
        }
        for i in 100..<200 {
            jsonDict["\(i)"] = randomInt()
        }
        return jsonDict
    }
    
    private func randomString() -> String {
        return UUID().uuidString
    }
    
    private func randomInt() -> Int32 {
        return Int32(arc4random_uniform(UInt32(Int32.max)))
    }

}
