//
//  Foundation+Decodable.swift
//  sajson
//
//  Created by Tobias Haeberle on 06.07.17.
//  Copyright © 2017 Chad Austin. All rights reserved.
//

import Foundation


extension Data: Decodable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        
        // It's more efficient to pre-allocate the buffer if we can.
        if let count = container.count {
            self.init(count: count)
            
            // Loop only until count, not while !container.isAtEnd, in case count is underestimated (this is misbehavior) and we haven't allocated enough space.
            // We don't want to write past the end of what we allocated.
            for i in 0 ..< count {
                let byte = try container.decode(UInt8.self)
                self[i] = byte
            }
        } else {
            self.init()
        }
        
        while !container.isAtEnd {
            var byte = try container.decode(UInt8.self)
            self.append(&byte, count: 1)
        }
    }
}

extension Date: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let timestamp = try container.decode(Double.self)
        self.init(timeIntervalSinceReferenceDate: timestamp)
    }
}

extension UUID: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected UUID string but found \(value).")
        }
        
        self = uuid
    }
}
