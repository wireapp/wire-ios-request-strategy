//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

public protocol Named {
  static var name: String { get }
}

public protocol Configurable {
    associatedtype Config: Codable
}

extension Feature {
    public enum AppLock: Configurable, Named {
        public static var name: String = "applock"
        public struct Config: Codable {
            let enforceAppLock: Bool
            let inactivityTimeoutSecs: UInt
        }
    }
}

// MARK: - Feature Responses
struct FeatureConfigResponse<T: Configurable>: Decodable {
    var status: Feature.Status
    var config: T.Config?
    
    var configData: Data? {
        return try? JSONEncoder().encode(config)
    }
}

struct AllFeatureConfigsResponse: Decodable {
    var applock: FeatureConfigResponse<Feature.AppLock>
}
