//
//  CountlyCrashReporterTests.swift
//  CountlyTests
//
//  Created by Arif Burak Demiray on 23.05.2024.
//  Copyright © 2024 Countly. All rights reserved.
//

import Foundation

import XCTest
@testable import Countly

class CountlyCrashReporterTests: CountlyBaseTestCase {
    
    func testRecordHandledException_globalCrashFilter() throws {
        let cConfig = createBaseConfig()
        cConfig.manualSessionHandling = true
        cConfig.crashSegmentation = [
            "secret": "Minato",
            "int": String(Int.max),
            "double": String(Double.greatestFiniteMagnitude),
            "bool": String(true),
            "long": String(Int64.max),
            "float": String(1.1),
        ]

        let crashFilterBlock: (CountlyCrashData?) -> Bool = { crash in
            if (crash!.crashDescription.contains("Secret")) {
                return true
            }
            
            crash?.crashSegmentation.removeObject(forKey: "secret")
            crash?.fatal = true
            crash!.crashMetrics["secret"] = "Minato"
            crash!.crashMetrics.removeObject(forKey: "_ram_total")
            
            let keys = crash!.crashSegmentation.allKeys as? [String]
            return keys!.contains("sphinx_no_1")
        }
        
        cConfig.crashes().crashFilterCallback = crashFilterBlock
        
        let countly = Countly()
        countly.start(with: cConfig)
        
        // First Exception
        let exception1 = NSException(name: NSExceptionName(rawValue: "secret"), reason: "Secret message")
        countly.record(exception1, isFatal: false, stackTrace: nil, segmentation: nil)
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        // Second Exception
        let exception2 = NSException(name: NSExceptionName(rawValue: "some"), reason: "Some message")
        countly.record(exception2, isFatal: false, stackTrace: nil, segmentation: ["sphinx_no_1": "secret"])
        XCTAssertEqual(0, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        // Third Exception
        countly.recordCrashLog("Breadcrumb_1")
        countly.recordCrashLog("Breadcrumb_2")
        let exception3 = NSException(name: NSExceptionName(rawValue: "some_other"), reason: "Some other message")
        countly.record(exception3, isFatal: false, stackTrace: nil, segmentation: ["sphinx_no": "324"])
        XCTAssertEqual(1, CountlyPersistency.sharedInstance().remainingRequestCount())
        
        try validateCrash(
            extractStackTrace(exception3),
            breadcrumbs: "Breadcrumb_1\nBreadcrumb_2",
            isFatal: true,
            changedBits: 11,
            customSegmentation: [
                "int": String(Int.max),
                "double": String(Double.greatestFiniteMagnitude),
                "bool": String(true),
                "float": String(1.1),
                "long": String(Int64.max),
                "sphinx_no": "324"
            ],
            idx: 0,
            customMetrics: ["secret": "Minato"],
            metricsToExclude: ["_ram_total"]
        )
    }
    
    func validateCrash(_ stackTrace: String?, breadcrumbs: String, isFatal: Bool, changedBits: Int, customSegmentation: [String: Any], idx: Int, customMetrics: [String: Any], metricsToExclude: [String]) throws {
        
        if let queuedRequests = CountlyPersistency.sharedInstance().value(forKey: "queuedRequests") as? [String] {
            let request = parseQueryString(queuedRequests[idx])
            //TestUtils.validateRequiredParams(RQ[idx])
            
            let crash = request["crash"] as! [String: Any]
            
            var paramCount = 0 //try validateCrashMetrics(crash: crash,  customMetrics: customMetrics, metricsToExclude: metricsToExclude)
            
            paramCount += 2 // for nonFatal and ob
            XCTAssertEqual(!isFatal, crash["_nonfatal"] as? Bool)
            XCTAssertEqual(changedBits, crash["_ob"] as? Int)
            
            if !customSegmentation.isEmpty {
                paramCount += 1
                let custom = crash["_custom"] as? [String: Any]

                for (key, value) in customSegmentation {
                    XCTAssertEqual(value as? NSObject, custom![key] as? NSObject)
                }
                XCTAssertEqual(custom?.count, customSegmentation.count)
            }
            
            if !breadcrumbs.isEmpty {
                paramCount += 1
                XCTAssertEqual(breadcrumbs, crash["_logs"] as? String)
            }
            
            //XCTAssertEqual(paramCount, crash.count)
        }
        
    }
    
    func validateCrashMetrics(crash: [String: Any], customMetrics: [String: Any], metricsToExclude: [String]) throws -> Int {
        var metricCount = 20 - metricsToExclude.count

        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_device", expectedValue: "C", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_os", expectedValue: "A", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_os_version", expectedValue: "B", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_resolution", expectedValue: "E", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_app_version", expectedValue: "Countly.DEFAULT_APP_VERSION", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_manufacturer", expectedValue: "D", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_cpu", expectedValue: "N", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_opengl", expectedValue: "O", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_root", expectedValue: "T", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_has_hinge", expectedValue: "Z", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_ram_total", expectedValue: "48", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_disk_total", expectedValue: "45", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_ram_current", expectedValue: "12", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_disk_current", expectedValue: "23", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_run", expectedValue: "88", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_background", expectedValue: "true", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_muted", expectedValue: "V", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_orientation", expectedValue: "S", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_online", expectedValue: "U", crash: crash)
        try assertMetricIfNotExcluded(metricsToExclude: metricsToExclude, key: "_bat", expectedValue: "6", crash: crash)


        for (key, value) in customMetrics {
            guard let crashValue = crash[key], "\(crashValue)" == "\(value)" else {
                throw ValidationError.assertionFailed
            }
        }
        metricCount += customMetrics.count

        return metricCount
    }
    
    enum ValidationError: Error {
        case jsonError
        case assertionFailed
    }
    
    func assertMetricIfNotExcluded(metricsToExclude: [String], key: String, expectedValue: String, crash: [String: Any]) throws {
        if !metricsToExclude.contains(key) {
            XCTAssertTrue(expectedValue == crash[key] as? String)
        }else{
            XCTAssertNil(crash[key])
        }
    }
    
    func extractStackTrace(_ exception: NSException) -> String? {
        return exception.callStackSymbols.joined(separator: "\n")
    }
    
}
