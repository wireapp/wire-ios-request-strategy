//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

public enum VoIPPushHelper {

    public static var storage: UserDefaults = .standard

    public static var isCallKitAvailable: Bool {
        get { storage.bool(forKey: Keys.isCallKitAvailable.stringValue) }
        set { storage.set(newValue, forKey: Keys.isCallKitAvailable.stringValue) }
    }

    public static func setIsUserSessionLoaded(accountID: UUID, isLoaded: Bool) {
        storage.set(isLoaded, forKey: Keys.isLoadedUserSession(accountID: accountID).stringValue)
    }

    public static func isUserSessionLoaded(accountID: UUID) -> Bool {
        return storage.bool(forKey: Keys.isLoadedUserSession(accountID: accountID).stringValue)
    }

    public static var isAVSReady: Bool {
        get { storage.bool(forKey: Keys.isAVSReady.stringValue) }
        set { storage.set(newValue, forKey: Keys.isAVSReady.stringValue) }
    }

    enum Keys {

        case isCallKitAvailable
        case isLoadedUserSession(accountID: UUID)
        case isAVSReady

        var stringValue: String {
            switch self {
            case .isCallKitAvailable:
                return "isCallKitAvailable"

            case let .isLoadedUserSession(accountID):
                return "isLoadedUserSession-\(accountID)"

            case .isAVSReady:
                return "isAVSReady"
            }
        }
    }

}
