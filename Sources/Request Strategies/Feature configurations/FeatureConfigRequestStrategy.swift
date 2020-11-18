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
    
    public static let needsToFetchFeatureConfigNotificationName = Notification.Name("needsToFetchFeatureConfiguration")

    private let zmLog = ZMSLog(tag: "feature configurations")
    
    private var notificationToken: Any?
    private var fetchSingleConfigSync: ZMSingleRequestSync!
    private var fetchAllConfigsSync: ZMSingleRequestSync!
    private var featureController: FeatureController!
    
    // Have a queue feature names.
    private var feature: String?
    
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
        self.notificationToken = NotificationInContext.addObserver(
            name: FeatureConfigRequestStrategy.needsToFetchFeatureConfigNotificationName,
            context: self.managedObjectContext.notificationContext,
            object: nil) { [weak self] in
                self?.requestConfig(with: $0)
        }
    }
    
    private func requestConfig(with note: NotificationInContext) {
        feature = note.object as? String
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return (feature == nil) ? fetchAllConfigsSync.nextRequest() : fetchSingleConfigSync.nextRequest()
    }
}

// MARK: - ZMSingleRequestTranscoder
extension FeatureConfigRequestStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        switch sync {
        case fetchSingleConfigSync:
            guard let feature = feature else {
                return nil
            }
            return fetchConfigRequestFor(feature)
        case fetchAllConfigsSync:
            return fetchAllConfigsRequest()
        default:
            return nil
        }
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        guard response.result == .permanentError || response.result == .success else {
            zmLog.debug("error downloading feature configuration (\(response.httpStatus))")
            return
        }
        guard let responseData = response.rawData else {
            return
        }
        
        switch sync {
        case fetchSingleConfigSync:
            do {
                //TODO Katerina make it more general for all kind of features
                let configuration = try JSONDecoder().decode(FeatureConfigResponse<FeatureModel.AppLock>.self, from: responseData)
                featureController.save(FeatureModel.AppLock.self, configuration: configuration)
            } catch {
                zmLog.error("Failed to decode feature config response: \(error)")
            }
        case fetchAllConfigsSync:
            do {
                let allConfigs = try JSONDecoder().decode(AllFeatureConfigsResponse.self, from: responseData)
                featureController.saveAllFeatures(allConfigs)
            } catch {
                zmLog.error("Failed to decode feature config response: \(error)")
            }
        default:
            break
        }
    }
}

// MARK: - Private methods
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


