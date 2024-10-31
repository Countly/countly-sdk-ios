//
//  CountlyEventStruct.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 30/05/2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import Foundation

// Helper struct to decode Any values in the segmentation dictionary
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let nestedDictionary = try? container.decode([String: AnyCodable].self) {
            value = nestedDictionary.mapValues { $0.value }
        } else if let nestedArray = try? container.decode([AnyCodable].self) {
            value = nestedArray.map { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let nestedDictionary = value as? [String: Any] {
            try container.encode(nestedDictionary.mapValues { AnyCodable($0) })
        } else if let nestedArray = value as? [Any] {
            try container.encode(nestedArray.map { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// Define a struct that matches the CountlyEvent class properties
struct CountlyEventStruct: Codable {
    let key: String
    let ID: String
    let CVID: String?
    let PVID: String?
    let PEID: String?
    let segmentation: [String: Any]?
    let count: UInt
    let sum: Double
    let timestamp: TimeInterval
    let hourOfDay: UInt
    let dayOfWeek: UInt
    let duration: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case key, ID = "id", CVID = "cvid", PVID = "pvid", PEID = "peid", segmentation, count, sum, timestamp, hourOfDay = "hour", dayOfWeek = "dow", duration = "dur"
    }
    
    // Custom decoding for the segmentation dictionary
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        ID = try container.decode(String.self, forKey: .ID)
        CVID = try container.decodeIfPresent(String.self, forKey: .CVID)
        PVID = try container.decodeIfPresent(String.self, forKey: .PVID)
        PEID = try container.decodeIfPresent(String.self, forKey: .PEID)
        count = try container.decode(UInt.self, forKey: .count)
        sum = try container.decode(Double.self, forKey: .sum)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        hourOfDay = try container.decode(UInt.self, forKey: .hourOfDay)
        dayOfWeek = try container.decode(UInt.self, forKey: .dayOfWeek)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        
        do {
            let segmentationData = try container.decodeIfPresent([String: AnyCodable].self, forKey: .segmentation)
            segmentation = segmentationData?.mapValues { $0.value }
        } catch {
            print("Error decoding segmentation: \(error.localizedDescription)")
            segmentation = nil
        }
    }
    
    // Custom encoding for the segmentation dictionary
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(ID, forKey: .ID)
        try container.encode(CVID, forKey: .CVID)
        try container.encode(PVID, forKey: .PVID)
        try container.encode(PEID, forKey: .PEID)
        try container.encode(count, forKey: .count)
        try container.encode(sum, forKey: .sum)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(hourOfDay, forKey: .hourOfDay)
        try container.encode(dayOfWeek, forKey: .dayOfWeek)
        try container.encode(duration, forKey: .duration)
        
        if let segmentation = segmentation {
            let segmentationData = segmentation.mapValues { AnyCodable($0) }
            try container.encode(segmentationData, forKey: .segmentation)
        }
    }
}

