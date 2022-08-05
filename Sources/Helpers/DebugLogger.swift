//
//  DebugLogger.swift
//  WireRequestStrategy
//
//  Created by Marcin Ratajczak on 04/08/2022.
//  Copyright © 2022 Wire GmbH. All rights reserved.
//
import Foundation

class DebugLogger {
    public static var storage: UserDefaults = .standard
    static let DebugFlagIsOnKey = "DebugFlagIsOn"
    static let PushNotificationLogsKey = "PushNotificationLogs"

    static func addStep(step: String, eventID: String) {
        guard storage.bool(forKey: DebugFlagIsOnKey) == true else { return }
        var logsDictionary = (storage.object(forKey: PushNotificationLogsKey) as? Dictionary<String, Any>) ?? [:]
        var eventDictionary: [String: String] = (logsDictionary[eventID] as? Dictionary<String, String>) ?? [:]
        let timeStamp = "\(Date().timeIntervalSince1970)"
        eventDictionary[timeStamp] = step
        logsDictionary[eventID] = eventDictionary
        storage.set(logsDictionary, forKey: PushNotificationLogsKey)
    }

    static func addFinalStep(eventID: String) {
        guard storage.bool(forKey: DebugFlagIsOnKey) == true else { return }
        var logsDictionary = (storage.object(forKey: PushNotificationLogsKey) as? Dictionary<String, Any>) ?? [:]
        let eventDictionary: [String: String] = (logsDictionary[eventID] as? Dictionary<String, String>) ?? [:]
        guard let start = eventDictionary.keys.sorted().first,
              let startInSeconds = Double(start) else {
                  addStep(step: "Finished", eventID: eventID)
                  return
              }
        if Date().timeIntervalSince1970 - (startInSeconds) < 4*60 {
            logsDictionary.removeValue(forKey: eventID)
            storage.set(logsDictionary, forKey: PushNotificationLogsKey)
        } else {
            addStep(step: "Finished", eventID: eventID)
        }
    }
}
