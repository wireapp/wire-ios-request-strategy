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

@objcMembers
public final class FeatureConfigRequestStrategy: AbstractRequestStrategy {
    
    enum PendingItem {
        case singleFeature(name: String)
        case allFeatures
    }
    
    public static let needsToFetchFeatureConfigNotificationName = Notification.Name("needsToFetchFeatureConfiguration")
    
    private let zmLog = ZMSLog(tag: "feature configurations")
    
    private var observerToken: Any?
    private var pendingItems: [PendingItem] = []
    private var fetchSingleConfigSync: ZMSingleRequestSync!
    private var fetchAllConfigsSync: ZMSingleRequestSync!
    private var featureController: FeatureController!
    
    // MARK: - Init
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.configuration = [.allowsRequestsWhileOnline,
                              .allowsRequestsDuringQuickSync,
                              .allowsRequestsWhileInBackground]
        
        self.featureController = FeatureController(managedObjectContext: managedObjectContext)
        self.fetchSingleConfigSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                         groupQueue: managedObjectContext)
        self.fetchAllConfigsSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                       groupQueue: managedObjectContext)
        self.observerToken = NotificationInContext.addObserver(
            name: FeatureConfigRequestStrategy.needsToFetchFeatureConfigNotificationName,
            context: self.managedObjectContext.notificationContext,
            object: nil) { [weak self] in
                self?.requestConfig(with: $0)
        }
    }
    
    // MARK: - Overrides
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return fetchSingleConfigSync.nextRequest() ?? fetchAllConfigsSync.nextRequest()
    }
}

// MARK: - ZMSingleRequestTranscoder
extension FeatureConfigRequestStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard !pendingItems.isEmpty else {
            return nil
        }
        let pendingItem = pendingItems.removeFirst()
        switch (sync, pendingItem) {
        case (fetchSingleConfigSync, let .singleFeature(name: featureName)):
            return fetchConfigRequestFor(featureName)
        case (fetchAllConfigsSync, .allFeatures):
            return fetchAllConfigsRequest()
        default:
            return nil
        }
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        guard response.result == .success else {
            zmLog.error("error downloading feature configuration (\(response.httpStatus))")
            return
        }
        guard let responseData = response.rawData else {
            zmLog.error("response has no rawData")
            return
        }
        
        switch sync {
        case fetchSingleConfigSync:
            do {
                // TODO: Katerina make it more general for all kind of features
                let config = try JSONDecoder().decode(ConfigResponse<Feature.AppLock>.self, from: responseData)
                featureController.store(feature: config.asFeature)
            } catch {
                zmLog.error("Failed to decode feature config response: \(error.localizedDescription)")
            }

        case fetchAllConfigsSync:
            do {
                let allConfigs = try JSONDecoder().decode(AllConfigsResponse.self, from: responseData)
                featureController.store(feature: allConfigs.applock.asFeature)
            } catch {
                zmLog.error("Failed to decode feature config response: \(error)")
            }

        default:
            break
        }
    }
}

// MARK: - Fetch configurations
extension FeatureConfigRequestStrategy {
    private func fetchAllConfigsRequest() -> ZMTransportRequest? {
        guard let teamId = ZMUser.selfUser(in: managedObjectContext).teamIdentifier?.uuidString else {
            return nil
        }
        return ZMTransportRequest(getFromPath: "/teams/\(teamId)/features")
    }
    
    private func fetchConfigRequestFor(_ feature: String) -> ZMTransportRequest? {
        guard let teamId = ZMUser.selfUser(in: managedObjectContext).teamIdentifier?.uuidString else {
            return nil
        }
        return ZMTransportRequest(getFromPath: "/teams/\(teamId)/features/\(feature)")
    }
}

// MARK: - Private methods
extension FeatureConfigRequestStrategy {
    private func requestConfig(with note: NotificationInContext) {
        if let featureName = note.object as? String {
            pendingItems.append(.singleFeature(name: featureName))
            fetchSingleConfigSync.readyForNextRequestIfNotBusy()
        } else {
            pendingItems.append(.allFeatures)
            fetchAllConfigsSync.readyForNextRequestIfNotBusy()
        }
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
}

private extension FeatureConfigRequestStrategy {

    struct ConfigResponse<T: FeatureLike>: Decodable {

        let status: Feature.Status
        let config: T.Config

        var asFeature: T {
            return T(status: status, config: config)
        }
    }

    struct AllConfigsResponse: Decodable {

        var applock: ConfigResponse<Feature.AppLock>

    }

}
