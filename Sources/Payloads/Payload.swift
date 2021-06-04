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

enum Payload {

    typealias UserClients = [Payload.UserClient]
    typealias UserClientByUserID = [String: UserClients]
    typealias UserClientByDomain = [String: UserClientByUserID]
    typealias UserProfiles = [Payload.UserProfile]

    struct QualifiedUserIDList: Codable, Hashable {

        enum CodingKeys: String, CodingKey {
            case qualifiedIDs = "qualified_ids"
        }

        var qualifiedIDs: [QualifiedUserID]
    }
    
    struct QualifiedUserID: Codable, Hashable {
        
        enum CodingKeys: String, CodingKey {
            case uuid = "id"
            case domain
        }
        
        let uuid: UUID
        let domain: String
    }
        
    struct Location: Codable {
        
        enum CodingKeys: String, CodingKey {
            case longitude = "lon"
            case latitide = "lat"
        }
        
        let longitude: Double
        let latitide: Double
    }
    
    struct UserClient: Codable {
        
        enum CodingKeys: String, CodingKey {
            case id
            case type
            case creationDate = "time"
            case label
            case location
            case deviceClass = "class"
            case deviceModel = "model"
        }
        
        let id: String
        let type: String?
        let creationDate: Date?
        let label: String?
        let location: Location?
        let deviceClass: String?
        let deviceModel: String?

        init(id: String,
             deviceClass: String,
             type: String? = nil,
             creationDate: Date? = nil,
             label: String? = nil,
             location: Location? = nil,
             deviceModel: String? = nil) {
            self.id = id
            self.type = type
            self.creationDate = creationDate
            self.label = label
            self.location = location
            self.deviceClass = deviceClass
            self.deviceModel = deviceModel
        }
        
    }

    struct Asset: Codable {

        enum AssetSize: String, Codable {
            case preview
            case complete
        }

        enum AssetType: String, Codable {
            case image
        }

        let key: String
        let size: AssetSize
        let type: AssetType
    }

    struct ServiceID: Codable {
        let id: UUID
        let provider: UUID
    }

    struct SSOID: Codable {

        enum CodingKeys: String, CodingKey {
            case tenant
            case subject
            case scimExternalID = "scim_external_id"
        }

        let tenant: String?
        let subject: String?
        let scimExternalID: String?
    }

    enum LegalholdStatus: String, Codable {
        case enabled
        case pending
        case disabled
        case noConsent = "no_consent"
    }

    struct UserProfile: Codable {

        enum CodingKeys: String, CodingKey {
            case id
            case qualifiedID = "qualified_id"
            case teamID = "team"
            case serviceID = "service"
            case SSOID = "sso_id"
            case name
            case handle
            case phone
            case email
            case assets
            case managedBy = "managed_by"
            case accentColor = "accent_id"
            case isDeleted = "deleted"
            case expiresAt = "expires_at"
            case legalholdStatus = "legalhold_status"
        }

        let id: UUID?
        let qualifiedID: QualifiedUserID?
        let teamID: UUID?
        let serviceID: ServiceID?
        let SSOID: SSOID?
        let name: String
        let handle: String?
        let phone: String?
        let email: String?
        let assets: [Asset]
        let managedBy: String?
        let accentColor: Int?
        let isDeleted: Bool?
        let expiresAt: Date?
        let legalholdStatus: LegalholdStatus?
    }

    struct ResponseFailure: Codable {

        enum Label: String, Codable {
            case notFound = "not-found"
            case noEndpoint = "no-endpoint"
            case unknown

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let label = try container.decode(String.self)
                self = Label(rawValue: label) ?? .unknown
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(self.rawValue)
            }
        }

        let code: Int
        let label: Label
        let message: String

    }
}

