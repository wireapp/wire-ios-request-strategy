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

public protocol Configurable {
    associatedtype Config: Codable
    static var name: String { get }
}

public enum FeatureModel {
    public enum AppLock: Configurable {
        public static var name: String = "applock"
        public struct Config: Codable {
            let enforceAppLock: Bool
            let inactivityTimeoutSecs: UInt
            
            private enum CodingKeys: String, CodingKey {
                case enforceAppLock = "enforce_app_lock"
                case inactivityTimeoutSecs = "inactivity_timeout_secs"
            }
        }
    }
}

public struct FeatureConfigResponse<T: Configurable>: Decodable {
    var status: FeatureStatus
    var config: T.Config?
    
    private enum CodingKeys: String, CodingKey {
        case status
        case config
    }
}

extension FeatureConfigResponse {
    var configData: Data? {
        return try? JSONEncoder().encode(config)
    }
}

struct AllFeatureConfigsResponse: Decodable {
    var applock: FeatureConfigResponse<FeatureModel.AppLock>
    
    private enum CodingKeys: String, CodingKey {
        case applock
    }
}

private let zmLog = ZMSLog(tag: "feature configurations")

public class FeatureController {
    
    public static let needsToUpdateFeatureNotificationName = Notification.Name("needsToUpdateFeatureConfiguration")

    private(set) var moc: NSManagedObjectContext
    
    public init(managedObjectContext: NSManagedObjectContext) {
        moc = managedObjectContext
    }
    
    public func status<T: Configurable>(for feature: T.Type) -> FeatureStatus {
        guard let feature = Feature.fetch(T.name, context: moc) else {
            return .disabled
        }
        return feature.status
    }
    
    public func configuration<T: Configurable>(for feature: T.Type) -> T.Config? {
        guard let configData = Feature.fetch(T.name, context: moc)?.config else {
                return nil
        }
        return try? JSONDecoder().decode(T.Config.self, from: configData)
    }
}

// MARK: - Save to Core Data
extension FeatureController {
    public func save<T: Configurable>(_ feature: T.Type, data: Data) {
        do {
            let configuration = try JSONDecoder().decode(FeatureConfigResponse<T>.self, from: data)
            let feature = Feature.createOrUpdate(feature.name,
                                                        status: configuration.status,
                                                        config: configuration.configData,
                                                        context: moc)
            
            // TODO: Katerina make it more general for all features
            if let appLockFeature = feature  {
                NotificationCenter.default.post(name: FeatureController.needsToUpdateFeatureNotificationName, object: nil, userInfo: ["appLock" : appLockFeature])
            }
            
        } catch {
            zmLog.error("Failed to decode response: \(error)"); return
        }
    }
    
    public func saveAllFeatures(_ data: Data) {
        do {
            let allConfigs = try JSONDecoder().decode(AllFeatureConfigsResponse.self, from: data)
            let appLock = (name: FeatureModel.AppLock.name, schema: allConfigs.applock)
            let appLockFeature = Feature.createOrUpdate(appLock.name,
                                                        status: appLock.schema.status,
                                                        config: appLock.schema.configData,
                                                        context: moc)
            
            if let appLockFeature = appLockFeature  {
                NotificationCenter.default.post(name: FeatureController.needsToUpdateFeatureNotificationName, object: nil, userInfo: ["appLock" : appLockFeature])
            }
        } catch {
            zmLog.error("Failed to decode response: \(error)"); return
        }
    }
}
