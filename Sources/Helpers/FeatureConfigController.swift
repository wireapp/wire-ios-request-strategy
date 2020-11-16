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

public class FeatureConfigController: NSObject {
    
    public func saveSingleConfig(for featureName: FeatureName, data: Data) {
        let newType = FeatureConfigResponse<AppLockConfig>.self
        if let features = try? JSONDecoder().decode(newType, from: data) {
        }
    }
    
    public func saveConfigs(_ data: Data) {
        if let features = try? JSONDecoder().decode(FeatureConfigsResponse.self, from: data) {
        }
        
       
    }
    
    struct FeatureConfigsResponse: Decodable {
        var applock: FeatureConfigResponse<AppLockConfig>
        
        private enum CodingKeys: String, CodingKey {
            case applock
        }
    }
    
    struct FeatureConfigResponse<ConfigType: Decodable>: Decodable {
        var status: String
        var config: ConfigType?
        
        private enum CodingKeys: String, CodingKey {
            case status
            case config
        }
    }
}

enum Feature<T> {
    case digitalSignature(T)
    case appLock(T)
    
    var name: FeatureName {
        switch self {
        case .appLock:
            return .applock
        case .digitalSignature:
            return .unknown
        }
    }
    
    var type: T.Type? {
        switch self {
        case .appLock:
            return T.self
        case .digitalSignature:
            return T.self
        }
    }
}

