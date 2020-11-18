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

public enum FeatureModel {
    public enum AppLock: Configurable, Named {
        public static var name: String = "applock"
        public struct Config: Codable {
            let enforceAppLock: Bool
            let inactivityTimeoutSecs: UInt
            
            private enum CodingKeys: String, CodingKey {
                case enforceAppLock = "enforceAppLock"
                case inactivityTimeoutSecs = "inactivityTimeoutSecs"
            }
        }
    }
}

public struct FeatureConfigResponse<T: Configurable>: Decodable {
    var status: Feature.Status
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

public struct AllFeatureConfigsResponse: Decodable {
    var applock: FeatureConfigResponse<FeatureModel.AppLock>
    
    private enum CodingKeys: String, CodingKey {
        case applock
    }
}

public class FeatureController {
    
    public static let needsToUpdateFeatureNotificationName = Notification.Name("needsToUpdateFeatureConfiguration")

    private(set) var moc: NSManagedObjectContext
    
    public init(managedObjectContext: NSManagedObjectContext) {
        moc = managedObjectContext
    }
    
    public static func status<T: Named>(for feature: T.Type, context: NSManagedObjectContext) -> Feature.Status {
        guard let feature = Feature.fetch(T.name, context: context) else {
            return .disabled
        }
        return feature.status
    }
    
    public func configuration<T: Configurable & Named>(for feature: T.Type) -> T.Config? {
        guard let configData = Feature.fetch(T.name, context: moc)?.config else {
                return nil
        }
        return try? JSONDecoder().decode(T.Config.self, from: configData)
    }
}

// MARK: - Save to Core Data
extension FeatureController {
    public func save<T: Configurable & Named>(_ feature: T.Type, configuration: FeatureConfigResponse<T>) {
        let feature = Feature.createOrUpdate(feature.name,
                                             status: configuration.status,
                                             config: configuration.configData,
                                             context: moc)
        
        // TODO: Katerina make it more general for all features
        NotificationCenter.default.post(name: FeatureController.needsToUpdateFeatureNotificationName, object: nil, userInfo: ["appLock" : feature])
    }
    
    public func saveAllFeatures(_ configurations: AllFeatureConfigsResponse) {
        let appLock = (name: FeatureModel.AppLock.name, schema: configurations.applock)
        let appLockFeature = Feature.createOrUpdate(appLock.name,
                                                    status: appLock.schema.status,
                                                    config: appLock.schema.configData,
                                                    context: moc)
        
        NotificationCenter.default.post(name: FeatureController.needsToUpdateFeatureNotificationName, object: nil, userInfo: ["appLock" : appLockFeature])
    }
}
