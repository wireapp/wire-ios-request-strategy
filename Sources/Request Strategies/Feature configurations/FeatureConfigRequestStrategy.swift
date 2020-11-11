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
  case digitalSignature = "digital-signatures"
}

@objcMembers
public final class FeatureConfigRequestStrategy: AbstractRequestStrategy {
    
    private(set) var feature: Feature?
    private(set) var fetchSingleConfigSync: ZMSingleRequestSync?
    private(set) var fetchAllConfigsSync: ZMSingleRequestSync?
    
    // MARK: - Init
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus,
                         feature: Feature? = nil) {
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.feature = feature
        self.fetchSingleConfigSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                     groupQueue: managedObjectContext)
        self.fetchAllConfigsSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                       groupQueue: managedObjectContext)
    }
    
    // MARK: - Methods
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return (feature != nil)
            ? fetchSingleConfigSync?.nextRequest()
            : fetchAllConfigsSync?.nextRequest()
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
            return
        }
        switch sync {
        case fetchSingleConfigSync:
            processFeatureFlagResponseSuccess(with: response.rawData)
        case fetchAllConfigsSync:
            processFeatureFlagResponseSuccess(with: response.rawData)
        default:
            break
        }
    }
    
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
    
    private func processFeatureFlagResponseSuccess(with data: Data?) {
        guard let responseData = data else {
            return
        }
        switch feature {
        case .applock:
            break
        default:
            break
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(FeatureFlagResponse.self,
                                                           from: responseData)
            //            update(with: decodedResponse)
        } catch {
        }
    }
}

// MARK: - AppLockFeatureFlagResponse
//"status": "disabled",
//"config": {
//   "enforce_app_lock": true,
//   "inactivity_timeout_secs": 30
//}

struct FeatureFlagResponse: Decodable {
    struct AppLockConfig: Decodable {
        let enforceAppLock: Bool
        let inactivityTimeoutSecs: Int
        
        public init(enforceAppLock: Bool, inactivityTimeoutSecs: Int) {
           self.enforceAppLock = enforceAppLock
           self.inactivityTimeoutSecs = inactivityTimeoutSecs
        }
        
        private enum CodingKeys: String, CodingKey {
            case enforceAppLock = "enforce_app_lock"
            case inactivityTimeoutSecs = "inactivity_timeout_secs"
        }
    }
    
    public let status: Bool
    public let config: AppLockConfig? // TODO: should be required
    
    public init(status: Bool, config: AppLockConfig) {
       self.status = status
       self.config = config
    }
    
    private enum CodingKeys: String, CodingKey {
        case status
        case config
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let statusStr = try container.decodeIfPresent(String.self, forKey: .status)
        switch statusStr {
        case "enabled":
            status = true
        case "disabled":
            status = false
        default:
            status = false
        }
        
        self.config = try container.decodeIfPresent(AppLockConfig.self, forKey: .config)
    }
    
}
