//
//  TextsWatchApp.swift
//  xDrip Watch App
//
//  Created by Paul Plant on 11/2/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import Foundation

// all common texts
class Texts_WatchApp {
    static private let filename = "TextsWatchApp"
    
    static let minutes = {
        return NSLocalizedString("widget_minutes", tableName: filename, bundle: Bundle.main, value: "mins", comment: "literal translation needed")
    }()
    
    static let minute = {
        return NSLocalizedString("widget_minute", tableName: filename, bundle: Bundle.main, value: "min", comment: "literal translation needed")
    }()
    
    static let high = {
        return NSLocalizedString("widget_high", tableName: filename, bundle: Bundle.main, value: "HIGH", comment: "the word HIGH, in capitals")
    }()
    
    static let low = {
        return NSLocalizedString("widget_low", tableName: filename, bundle: Bundle.main, value: "LOW", comment: "the word LOW, in capitals")
    }()
    
    static let urgentHigh = {
        return NSLocalizedString("widget_urgentHigh", tableName: filename, bundle: Bundle.main, value: "URGENT\nHIGH", comment: "the words URGENT HIGH, in capitals")
    }()
    
    static let urgentLow = {
        return NSLocalizedString("widget_urgentLow", tableName: filename, bundle: Bundle.main, value: "URGENT\nLOW", comment: "the words URGENT LOW, in capitals")
    }()
        
    static let mgdl: String = {
        return NSLocalizedString("widget_mgdl", tableName: filename, bundle: Bundle.main, value: "mg/dL", comment: "mg/dL")
    }()

    static let mmol: String = {
        return NSLocalizedString("widget_mmol", tableName: filename, bundle: Bundle.main, value: "mmol/L", comment: "mmol/L")
    }()

    static let ago:String = {
        return NSLocalizedString("ago", tableName: filename, bundle: Bundle.main, value: "ago", comment: "where it say how old the reading is, 'x minutes ago', literaly translation of 'ago'")
    }()

}

