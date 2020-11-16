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

public protocol Configurable {
    associatedtype Config: Codable
}

enum FeatureModel {
    enum AppLock: Configurable {
        struct Config: Codable {
            let enforceAppLock: Bool
            let inactivityTimeoutSecs: UInt
            
            private enum CodingKeys: String, CodingKey {
                case enforceAppLock = "enforce_app_lock"
                case inactivityTimeoutSecs = "inactivity_timeout_secs"
            }
        }
    }
}

struct FeatureResponse<ConfigType: Decodable>: Decodable {
    var status: String
    var config: ConfigType?
    
    private enum CodingKeys: String, CodingKey {
        case status
        case config
    }
}

struct FeatureConfigsResponse: Decodable {
    var applock: FeatureResponse<FeatureModel.AppLock.Config>
    
    private enum CodingKeys: String, CodingKey {
        case applock
    }
}

import Foundation

public class FeatureController {
    
//    var observers: [[String : ((T.Config) -> Void)]]? = []
    private(set) var moc: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        moc = managedObjectContext
    }
    
    func status<T: Configurable>(for feature: T.Type) -> Bool {
        guard let featureName = getName(for: feature),
            let feature = Feature.fetch(featureName, context: moc) else {
                return false
        }
        return feature.status.boolStatus()
    }
    
    func configuration<T: Configurable>(for feature: T.Type) -> T.Config? {
        guard let featureName = getName(for: feature),
            let configData = Feature.fetch(featureName, context: moc)?.config else {
                return nil
        }
        return try? JSONDecoder().decode(feature.Config, from: configData)
    }
    
    func addObserver<T: Configurable>(for feature: T.Type, onChange: @escaping (T.Config) -> Void) {
//        observers?.append(featureName : onChange)
    }
}


// MARK: - Internal
extension FeatureController {
    func save<T: Configurable>(_ feature: T.Type, data: Data) {
        let features = try? JSONDecoder().decode(FeatureResponse<>, from: data)
    }
    
//    internal func saveAllConfigs(_ data: Data) {
//        if let features = try? JSONDecoder().decode(FeatureConfigsResponse.self, from: data) {
//            //?
//        }
//    }
}

// MARK: - Private
extension FeatureController {
    private func getName<T: Configurable>(for feature: T.Type) -> String? {
//        if T.self == FeatureModel.AppLock.self {
//            return "applock"
//        }
//        return nil
        
        switch feature {
        case is FeatureModel.AppLock.Type:
            return "appLock"
        default:
            return nil
        }
    }
}

private extension String {
    func boolStatus() -> Bool {
        switch self {
        case "enabled":
            return true
        case "disabled":
            return false
        default:
            return false
        }
    }
}

