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

public class FeatureController {
    
    public static let featureConfigDidChange = Notification.Name("FeatureConfigDidChange")

    private(set) var moc: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        moc = managedObjectContext
    }
    
    public static func status<T: Named>(for feature: T.Type, managedObjectContext: NSManagedObjectContext) -> Feature.Status {
        managedObjectContext.performGroupedAndWait { _ in
            guard let feature = Feature.fetch(T.name, context: managedObjectContext) else {
                return .disabled
            }
            return feature.status
        }
    }
    
    public static func configuration<T: Configurable & Named>(for feature: T.Type, managedObjectContext: NSManagedObjectContext) -> T.Config? {
        managedObjectContext.performGroupedAndWait { _ in
            guard let configData = Feature.fetch(T.name, context: managedObjectContext)?.config else {
                return nil
            }
            return try? JSONDecoder().decode(T.Config.self, from: configData)
        }
    }
}

// MARK: - Save to Core Data
extension FeatureController {
    internal func save<T: Configurable & Named>(_ feature: T.Type, configuration: FeatureConfigResponse<T>) {
        let feature = Feature.createOrUpdate(feature.name,
                                             status: configuration.status,
                                             config: configuration.configData,
                                             context: moc)
        
        // TODO: Katerina make it more general for all features
        var config: Feature.AppLock.Config?
        if let featureConfig = feature.config {
            config = try? JSONDecoder().decode(Feature.AppLock.Config.self, from: featureConfig)
        }
        let featureInfo = FeatureConfigResponse<Feature.AppLock>(status: feature.status, config: config)
        NotificationCenter.default.post(name: FeatureController.featureConfigDidChange, object: nil, userInfo: [Feature.AppLock.name : featureInfo])
    }
    
    internal func saveAllFeatures(_ configurations: AllFeatureConfigsResponse) {
        let appLock = (name: Feature.AppLock.name, schema: configurations.applock)
        let appLockFeature = Feature.createOrUpdate(appLock.name,
                                                    status: appLock.schema.status,
                                                    config: appLock.schema.configData,
                                                    context: moc)
        
        var config: Feature.AppLock.Config?
        if let featureConfig = appLockFeature.config {
            config = try? JSONDecoder().decode(Feature.AppLock.Config.self, from: featureConfig)
        }
        let featureInfo = FeatureConfigResponse<Feature.AppLock>(status: appLockFeature.status, config: config)
        NotificationCenter.default.post(name: FeatureController.featureConfigDidChange, object: nil, userInfo: [appLock.name : featureInfo])
    }
}
