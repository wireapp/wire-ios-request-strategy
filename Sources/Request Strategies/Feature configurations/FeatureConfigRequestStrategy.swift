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

public enum Feature: String, Equatable {
  case applock = "applock"
}

@objcMembers
public final class FeatureConfigRequestStrategy: AbstractRequestStrategy {
    
    public static let needsToUpdateFeatureConfigNotificationName = Notification.Name("ZMNeedsToUpdateFeatureConfigNotification")
    
    private var observers: [Any] = []
    private var fetchSingleConfigSync: ZMSingleRequestSync?
    private var fetchAllConfigsSync: ZMSingleRequestSync?
    private var feature: Feature?
    
    // MARK: - Init
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.configuration = [.allowsRequestsWhileOnline,
                              .allowsRequestsDuringQuickSync,
                              .allowsRequestsWhileInBackground]
        
        self.fetchSingleConfigSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                     groupQueue: managedObjectContext)
        self.fetchAllConfigsSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                       groupQueue: managedObjectContext)
        self.observers.append(NotificationInContext.addObserver(
            name: FeatureConfigRequestStrategy.needsToUpdateFeatureConfigNotificationName,
            context: self.managedObjectContext.notificationContext,
            object: nil) { [weak self] in
                self?.requestConfig(with: $0)
        })
    }
    
    private func requestConfig(with note: NotificationInContext) {
        feature = note.object as? Feature
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return (feature == nil) ? fetchAllConfigsSync?.nextRequest() : fetchSingleConfigSync?.nextRequest()
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
        guard let responseData = response.rawData,
            (response.result == .permanentError || response.result == .success) else {
            return
        }

        switch sync {
        case fetchSingleConfigSync:
            processFeatureConfigResponseSuccess(with: responseData)
        case fetchAllConfigsSync:
            processAllConfigsResponseSuccess(with: responseData)
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
    
    private func fetchConfigRequestFor(_ feature: Feature) -> ZMTransportRequest? {
        guard let teamId = ZMUser.selfUser(in: managedObjectContext).teamIdentifier?.uuidString else {
            return nil
        }
        return ZMTransportRequest(getFromPath: "/teams/\(teamId)/features/\(feature)")
    }
    
    private func processAllConfigsResponseSuccess(with data: Data) {
        if let response = try? JSONDecoder().decode(FeatureConfigsResponse.self, from: data) {
            updateAppLockFeature(with: response.applock)
        }
    }
    
    private func processFeatureConfigResponseSuccess(with data: Data) {
        var decodedResponse: BaseFeatureConfig?
        switch feature {
        case .applock:
            decodedResponse = try? JSONDecoder().decode(AppLockFeatureConfigResponse.self, from: data)
        default:
            decodedResponse = nil
        }
        
        if let decodedResponse = decodedResponse {
            update(with: decodedResponse)
        }
    }
    
    private func update(with decodedResponse: BaseFeatureConfig) {
        switch feature {
        case .applock:
            if let responce = decodedResponse as? AppLockFeatureConfigResponse {
                updateAppLockFeature(with: responce)
            }
        default:
            break
        }
    }
    
    private func updateAppLockFeature(with schema: AppLockFeatureConfigResponse) {
        AppLock.isActive = schema.status
        AppLock.rules.forceAppLock = schema.config.enforceAppLock
        AppLock.rules.appLockTimeout = schema.config.inactivityTimeoutSecs
    }
}

// MARK: - FeatureConfigResponses
//protocol FeatureConfig: Decodable {}

protocol BaseFeatureConfig: Decodable {
    var status: Bool { get set }
    func convertToBool(_ statusStr: String) -> Bool
}

extension BaseFeatureConfig {
    func convertToBool(_ statusStr: String) -> Bool {
        switch statusStr {
        case "enabled":
            return true
        case "disabled":
            return false
        default:
            return false
        }
    }
}

//"applock": {
//  "status": "disabled",
//  "config": {
//     "enforce_app_lock": true,
//     "inactivity_timeout_secs": 30
//  }
//}
struct FeatureConfigsResponse: Decodable {
    public var applock: AppLockFeatureConfigResponse
    
    private enum CodingKeys: String, CodingKey {
        case applock
    }
}

struct AppLockFeatureConfigResponse: BaseFeatureConfig {
    private var statusStr: String {
        didSet {
            self.status = convertToBool(statusStr)
        }
    }
    public var status: Bool = false
    public var config: AppLockConfig
    
    private enum CodingKeys: String, CodingKey {
        case statusStr = "status"
        case config = "config"
    }
}

struct AppLockConfig: Decodable {
    let enforceAppLock: Bool
    let inactivityTimeoutSecs: UInt
    
    private enum CodingKeys: String, CodingKey {
        case enforceAppLock = "enforce_app_lock"
        case inactivityTimeoutSecs = "inactivity_timeout_secs"
    }
}
