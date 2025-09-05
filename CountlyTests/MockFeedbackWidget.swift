//
//  MockFeedbackWidget.swift
//  Countly
//
//  Created by Arif Burak Demiray on 4.04.2025.
//  Copyright © 2025 Countly. All rights reserved.
//


import Countly

class MockFeedbackWidget: CountlyFeedbackWidget {
    private let _id: String
    private let _type: CLYFeedbackWidgetType

    override var id: String { return _id }
    override var type: CLYFeedbackWidgetType { return _type }

    init(
        id: String,
        type: CLYFeedbackWidgetType
    ) {
        self._id = id
        self._type = type
        super.init()
    }
}
