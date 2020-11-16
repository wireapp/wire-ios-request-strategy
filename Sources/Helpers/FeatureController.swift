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

enum FeatureModel {
    enum AppLock: Configurable {
        static var name: String = "applock"
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

struct FeatureConfigResponse<T: Configurable>: Decodable {
    var status: String
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

public class FeatureController {
    
    public static let needsToUpdateFeatureNotificationName = Notification.Name("needsToUpdateFeatureConfiguration")

    private(set) var moc: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        moc = managedObjectContext
    }
    
    func status<T: Configurable>(for feature: T.Type) -> Bool {
        guard let feature = Feature.fetch(feature.name, context: moc) else {
                return false
        }
        return Bool(statusStr: feature.status)
    }
    
    func configuration<T: Configurable>(for feature: T.Type) -> T.Config? {
        guard let configData = Feature.fetch(feature.name, context: moc)?.config else {
                return nil
        }
        return try? JSONDecoder().decode(feature.Config, from: configData)
    }
}


// MARK: - Internal
extension FeatureController {
    func save<T: Configurable>(_ feature: T.Type, data: Data) {
        do {
            let configuration = try JSONDecoder().decode(FeatureConfigResponse<FeatureModel.AppLock>.self, from: data)
            let appLockFeature = Feature.createOrUpdate(feature.name,
                                                        status: configuration.status,
                                                        config: configuration.configData,
                                                        context: moc)
            moc.saveOrRollback()
            
            if let appLockFeature = appLockFeature  {
                NotificationCenter.default.post(name: FeatureController.needsToUpdateFeatureNotificationName, object: nil, userInfo: ["appLock" : appLockFeature])
            }
            
        } catch {}
    }
    
    func saveAllFeatures(_ data: Data) {
        do {
            let allConfigs = try JSONDecoder().decode(AllFeatureConfigsResponse.self, from: data)
            let appLock = (name: FeatureModel.AppLock.name, schema: allConfigs.applock)
            let appLockFeature = Feature.createOrUpdate(appLock.name,
                                                        status: appLock.schema.status,
                                                        config: appLock.schema.configData,
                                                        context: moc)
            moc.saveOrRollback()
            
            if let appLockFeature = appLockFeature  {
                NotificationCenter.default.post(name: FeatureController.needsToUpdateFeatureNotificationName, object: nil, userInfo: ["appLock" : appLockFeature])
            }
        } catch {}
    }
}

private extension Bool {
    init(statusStr: String) {
        switch statusStr {
        case "enabled":
            self = true
        case "disabled":
            self = false
        default:
            self = false
        }
    }
}
