//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//
import Foundation

public class DebugLogger {
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
