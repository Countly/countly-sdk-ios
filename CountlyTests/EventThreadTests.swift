//
//  CountlyBaseTestCase.swift
//  CountlyTests
//
//  Created by Muhammad Junaid Akram on 27/12/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

import XCTest
@testable import Countly

final class EventRaceReproTests: XCTestCase {
    func testPreviousEventIDRace() {
        let config = CountlyConfig()
        config.appKey = "appkey"
        config.host = "https://127.0.0.1"
        config.enableDebug = true
        config.requiresConsent = false
        config.eventSendThreshold = UInt(10_000)
        config.experimental().enablePreviousNameRecording = true;
        Countly.sharedInstance().start(with: config)

        Countly.sharedInstance().recordEvent("warmup")

        let group = DispatchGroup()
        let workers = 8
        let iterations = 1_000

        for w in 0..<workers {
            group.enter()
            DispatchQueue.global().async {
                for i in 0..<iterations {
                    let seg: [String: Any] = ["step": i, "flag": i % 2 == 0]
                    Countly.sharedInstance().recordEvent("Login Result #\(w)-\(i)", segmentation: seg)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + 300)
        XCTAssertEqual(waitResult, .success)

        CountlyConnectionManager.sharedInstance()?.sendEvents()

        guard let persistency = CountlyPersistency.sharedInstance() else {
            XCTFail("Persistency is not available")
            return
        }

        guard let queuedRequests = persistency.value(forKey: "queuedRequests") as? [String] else {
            XCTFail("Failed to read queued requests")
            return
        }

        struct EventPayload {
            let key: String
            let id: String
            let previousID: String
            let previousName: String
            let timestamp: TimeInterval
        }

        func extractEvents(from request: String) -> [EventPayload] {
            let params = TestUtils.parseQueryString(request)
            guard let eventsJSON = params["events"] as? String,
                  let data = eventsJSON.data(using: .utf8) else {
                return []
            }

            guard let decodedEvents = try? JSONDecoder().decode([CountlyEventStruct].self, from: data) else {
                return []
            }

            return decodedEvents.map { event in
                let previousName = (event.segmentation?[kCountlyPreviousEventName] as? String) ?? ""
                return EventPayload(
                    key: event.key,
                    id: event.ID,
                    previousID: event.PEID ?? "",
                    previousName: previousName,
                    timestamp: event.timestamp
                )
            }
        }

        var queuedEvents: [EventPayload] = []
        for request in queuedRequests {
            queuedEvents.append(contentsOf: extractEvents(from: request))
        }

        XCTAssertFalse(queuedEvents.isEmpty, "No events found in queued requests")

        let expectedNonReservedCount = 1 + (workers * iterations)
        let nonReservedEvents = queuedEvents
            .filter { !$0.key.hasPrefix("[CLY]_") }

        XCTAssertEqual(nonReservedEvents.count, expectedNonReservedCount)

        var mismatchSummaries: [String] = []

        for (index, event) in nonReservedEvents.enumerated() {
            if index == 0 {
                if !event.previousID.isEmpty || !event.previousName.isEmpty {
                    mismatchSummaries.append("Index 0 expected empty previous metadata but found id=\(event.previousID), name=\(event.previousName)")
                }
                continue
            }

            let priorEvent = nonReservedEvents[index - 1]

            if event.previousID != priorEvent.id {
                mismatchSummaries.append("Index \(index) id=\(event.id) expected prior id=\(priorEvent.id) but was \(event.previousID)")
            }

            if event.previousName != priorEvent.key {
                mismatchSummaries.append("Index \(index) id=\(event.id) expected prior name=\(priorEvent.key) but was \(event.previousName)")
            }
        }

        XCTAssertTrue(mismatchSummaries.isEmpty, mismatchSummaries.joined(separator: "\n"))
    }
}
