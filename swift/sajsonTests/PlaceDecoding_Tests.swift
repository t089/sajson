//
//  ApartmentDecoding_Tests
//
//  Created on 07.07.17.
//  Copyright © 2017 Chad Austin. All rights reserved.
//

import XCTest
@testable import sajson_swift

fileprivate struct Place: Decodable {
    fileprivate struct Pin: Decodable {
        let lon: Float
        let lat: Float
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            lon = try container.decode(Float.self, forKey: .lon)
            lat = try container.decode(Float.self, forKey: .lat)
        }
        
        enum CodingKeys: String, CodingKey {
            case lon
            case lat
        }
    }
    
    let pin: Pin
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pin = try container.decode(Pin.self, forKey: .pin)
    }
    
    enum CodingKeys: String, CodingKey {
        case pin
    }
}

class PlaceDecoding_Tests: XCTestCase {
    
    lazy var fixtureUrl : URL = Bundle(for: PlaceDecoding_Tests.self).url(forResource: "place", withExtension: "json")!
    var input: Data!
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        input = try! Data(contentsOf: fixtureUrl)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        
        input = nil
    }
    
    func test_pin_decoding() throws {
        let place: Place
        do {
            place = try FastJSONDecoder().decode(Place.self, from: input)
        } catch {
            print(error)
            throw error
        }
        XCTAssertEqual(place.pin.lon, 138.11)
        XCTAssertEqual(place.pin.lat, -62.13)
    }
    
    
    
}
