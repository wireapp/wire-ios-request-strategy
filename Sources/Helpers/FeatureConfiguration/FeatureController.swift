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

private let zmLog = ZMSLog(tag: "feature configurations")

public class FeatureController {
    
    public static let featureConfigDidChange = Notification.Name("FeatureConfigDidChange")

    private(set) var moc: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        moc = managedObjectContext
    }

}

// MARK: - Save to Core Data
extension FeatureController {

    func store<T: FeatureLike>(feature: T, in team: Team) {
        do {
            try feature.store(for: team, in: moc)

            // TODO: Katerina make it more general for all features
            NotificationCenter.default.post(
                name: FeatureController.featureConfigDidChange,
                object: nil,
                userInfo: [Feature.AppLock.name : feature]
            )
        }
        catch {
            zmLog.error("Failed to store feature config in Core Data: \(error.localizedDescription)")
        }
    }
    
}
