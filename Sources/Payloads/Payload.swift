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
    typealias PrekeyByClientID = [String: Prekey?]
    typealias PrekeyByUserID = [String: PrekeyByClientID]
    typealias PrekeyByQualifiedUserID = [String: PrekeyByUserID]
    typealias ClientList = [String]
    typealias ClientListByUserID = [String: ClientList]
    typealias ClientListByQualifiedUserID = [String: ClientListByUserID]
    typealias UserProfiles = [Payload.UserProfile]

    struct QualifiedUserIDList: Codable, Hashable {

        enum CodingKeys: String, CodingKey {
            case qualifiedIDs = "qualified_ids"
        }

        var qualifiedIDs: [QualifiedUserID]
    }

    struct Prekey: Codable {
        let key: String
        let id: Int?
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

        enum CodingKeys: String, CodingKey, CaseIterable {
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
        let name: String?
        let handle: String?
        let phone: String?
        let email: String?
        let assets: [Asset]?
        let managedBy: String?
        let accentColor: Int?
        let isDeleted: Bool?
        let expiresAt: Date?
        let legalholdStatus: LegalholdStatus?

        /// All keys which were present in the original payload even if they
        /// contained a null value.
        ///
        /// This is used to distinguish when a delta user profile update does not
        /// contain a field from when it sets the field to nil.
        let updatedKeys: Set<CodingKeys>

        init(id: UUID? = nil,
             qualifiedID: QualifiedUserID? = nil,
             teamID: UUID? = nil,
             serviceID: ServiceID? = nil,
             SSOID: SSOID? = nil,
             name: String? = nil,
             handle: String? = nil,
             phone: String? = nil,
             email: String? = nil,
             assets: [Asset] = [],
             managedBy: String? = nil,
             accentColor: Int? = nil,
             isDeleted: Bool? = nil,
             expiresAt: Date? = nil,
             legalholdStatus: LegalholdStatus? = nil,
             updatedKeys: Set<CodingKeys>? = nil) {

            self.id = id
            self.qualifiedID = qualifiedID
            self.teamID = teamID
            self.serviceID = serviceID
            self.SSOID = SSOID
            self.name = name
            self.handle = handle
            self.phone = phone
            self.email = email
            self.assets = assets
            self.managedBy = managedBy
            self.accentColor = accentColor
            self.isDeleted = isDeleted
            self.expiresAt = expiresAt
            self.legalholdStatus = legalholdStatus
            self.updatedKeys = updatedKeys ?? Set(CodingKeys.allCases)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id)
            self.qualifiedID = try container.decodeIfPresent(QualifiedUserID.self, forKey: .qualifiedID)
            self.teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID)
            self.serviceID = try container.decodeIfPresent(ServiceID.self, forKey: .serviceID)
            self.SSOID = try container.decodeIfPresent(Payload.SSOID.self, forKey: .SSOID)
            self.name = try container.decodeIfPresent(String.self, forKey: .name)
            self.handle = try container.decodeIfPresent(String.self, forKey: .handle)
            self.phone = try container.decodeIfPresent(String.self, forKey: .phone)
            self.email = try container.decodeIfPresent(String.self, forKey: .email)
            self.assets = try container.decodeIfPresent([Payload.Asset].self, forKey: .assets)
            self.managedBy = try container.decodeIfPresent(String.self, forKey: .managedBy)
            self.accentColor = try container.decodeIfPresent(Int.self, forKey: .accentColor)
            self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
            self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            self.legalholdStatus = try container.decodeIfPresent(LegalholdStatus.self, forKey: .legalholdStatus)
            self.updatedKeys = Set(container.allKeys)
        }
    }

    struct ResponseFailure: Codable {

        enum Label: String, Codable {
            case notFound = "not-found"
            case noEndpoint = "no-endpoint"
            case unknownClient = "unknown-client"
            case missingLegalholdConsent = "missing-legalhold-consent"
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

    struct MessageSendingStatus: Codable {

        enum CodingKeys: String, CodingKey {
            case time
            case missing
            case redundant
            case deleted
            case failedToSend = "failed_to_send"
        }

        /// Time of sending message.
        let time: Date

        /// Clients that the message should have been encrypted for, but wasn't.
        let missing: ClientListByQualifiedUserID

        /// Clients that the message was encrypted for, but isn't necessary. For
        /// example for a client who's user has been removed from the conversation.
        let redundant: ClientListByQualifiedUserID

        /// Clients that the message was encrypted for, but has since been deleted.
        let deleted: ClientListByQualifiedUserID

        /// When a message is partially sent contains the list of clients which
        /// didn't receive the message.
        let failedToSend: ClientListByQualifiedUserID
    }

    struct Service: Codable {
        let id: UUID
        let provider: UUID
    }

    struct ConversationMember: Codable {

        enum CodingKeys: String, CodingKey {
            case id
            case qualifiedID = "qualified_id"
            case target
            case service
            case mutedStatus = "otr_muted_status"
            case mutedReference = "otr_muted_ref"
            case archived = "otr_archived"
            case archivedReference = "otr_archived_ref"
            case hidden = "otr_hidden"
            case hiddenReference = "otr_hidden_ref"
            case conversationRole = "conversation_role"
        }

        let id: UUID?
        let qualifiedID: QualifiedUserID?
        let target: UUID?
        let service: Service?
        let mutedStatus: Int?
        let mutedReference: Date?
        let archived: Bool?
        let archivedReference: Date?
        let hidden: Bool?
        let hiddenReference: String?
        let conversationRole: String?
    }

    struct ConversationMembers: Codable {
        enum CodingKeys: String, CodingKey {
            case selfMember = "self"
            case others
        }

        let selfMember: ConversationMember
        let others: [ConversationMember]
    }

    struct ConversationTeamInfo: Codable {
        enum CodingKeys: String, CodingKey {
            case teamID = "teamid"
            case managed
        }

        init (teamID: UUID, managed: Bool = false) {
            self.teamID = teamID
            self.managed = managed
        }

        let teamID: UUID
        let managed: Bool?
    }

    struct UpdateConverationMemberLeave: Codable {
        enum CodingKeys: String, CodingKey {
            case userIDs = "user_ids"
            case qualifiedUserIDs = "qualified_user_ids"
        }

        let userIDs: [UUID]?
        let qualifiedUserIDs: [QualifiedUserID]?
    }

    struct UpdateConverationMemberJoin: Codable {
        enum CodingKeys: String, CodingKey {
            case userIDs = "user_ids"
            case users
        }

        let userIDs: [UUID]?
        let users: [ConversationMember]?
    }

    struct UpdateConversationConnectionRequest: Codable { }
    
    struct UpdateConversationDeleted: Codable { }

    struct UpdateConversationReceiptMode: Codable {
        enum CodingKeys: String, CodingKey {
            case readReceiptMode = "receipt_mode"
        }

        let readReceiptMode: Int
    }

    struct UpdateConversationMessageTimer: Codable {
        enum CodingKeys: String, CodingKey {
            case messageTimer = "message_timer"
        }

        let messageTimer: TimeInterval?
    }

    struct UpdateConversationAccess: Codable {
        enum CodingKeys: String, CodingKey {
            case access
            case accessRole = "access_role"
        }

        let access: [String]
        let accessRole: String
    }

    struct UpdateConversationName: Codable {
        var name: String

        init?(_ conversation: ZMConversation) {
            guard
                conversation.hasLocalModifications(forKey: ZMConversationUserDefinedNameKey),
                let userDefinedName = conversation.userDefinedName
            else {
                return nil
            }

            name = userDefinedName
        }
    }

    struct UpdateConversationStatus: Codable {
        enum CodingKeys: String, CodingKey {
            case mutedStatus = "otr_muted_status"
            case mutedReference = "otr_muted_ref"
            case archived = "otr_archived"
            case archivedReference = "otr_archived_ref"
            case hidden = "otr_hidden"
            case hiddenReference = "otr_hidden_ref"
        }

        var mutedStatus: Int?
        var mutedReference: Date?
        var archived: Bool?
        var archivedReference: Date?
        var hidden: Bool?
        var hiddenReference: String?

        init(_ conversation: ZMConversation) {

            if conversation.hasLocalModifications(forKey: ZMConversationSilencedChangedTimeStampKey) {
                let reference = conversation.silencedChangedTimestamp ?? Date()
                conversation.silencedChangedTimestamp = reference

                mutedStatus = Int(conversation.mutedMessageTypes.rawValue)
                mutedReference = reference
            }

            if conversation.hasLocalModifications(forKey: ZMConversationArchivedChangedTimeStampKey) {
                let reference = conversation.archivedChangedTimestamp ?? Date()
                conversation.archivedChangedTimestamp = reference

                archived = conversation.isArchived
                archivedReference = reference
            }
        }
    }

    struct NewConversation: Codable {
        enum CodingKeys: String, CodingKey {
            case users
            case qualifiedUsers = "qualified_users"
            case access
            case accessRole = "access_role"
            case name
            case team
            case messageTimer = "message_timer"
            case readReceiptMode = "receipt_mode"
            case conversationRole = "conversation_role"
        }

        let users: [UUID]?
        let qualifiedUsers: QualifiedUserIDList?
        let access: [String]?
        let accessRole: String?
        let name: String?
        let team: ConversationTeamInfo?
        let messageTimer: TimeInterval?
        let readReceiptMode: Int?
        let conversationRole: String?

        init(_ conversation: ZMConversation) {
            users = conversation.localParticipantsExcludingSelf.map(\.remoteIdentifier)
            qualifiedUsers = nil
            name = conversation.userDefinedName
            access = conversation.accessMode?.stringValue
            accessRole = conversation.accessRole?.rawValue
            conversationRole = ZMConversation.defaultMemberRoleName
            team = conversation.team?.remoteIdentifier.map({ ConversationTeamInfo(teamID: $0) })
            readReceiptMode = conversation.hasReadReceiptsEnabled ? 1 : 0
            messageTimer = nil
        }
    }

    struct Conversation: Codable {

        enum CodingKeys: String, CodingKey {
            case qualifiedID = "qualified_id"
            case id
            case type
            case creator
            case access
            case accessRole = "access_role"
            case name
            case members
            case lastEvent = "last_event"
            case lastEventTime = "last_event_time"
            case teamID = "team"
            case messageTimer = "message_timer"
            case readReceiptMode = "read_receipt_mode"
        }

        let qualifiedID: QualifiedUserID?
        let id: UUID?
        let type: Int?
        let creator: UUID?
        let access: [String]?
        let accessRole: String?
        let name: String?
        let members: ConversationMembers?
        let lastEvent: String?
        let lastEventTime: String?
        let teamID: UUID?
        let messageTimer: TimeInterval?
        let readReceiptMode: Int?
    }

    struct ConversationList: Codable {
        enum CodingKeys: String, CodingKey {
            case conversations
            case hasMore = "has_more"
        }

        let conversations: [Conversation]
        let hasMore: Bool?
    }

    struct ConversationEvent<T: Codable>: Codable {

        enum CodingKeys: String, CodingKey {
            case id = "conversation"
            case qualifiedID = "qualified_conversation"
            case from
            case qualifiedFrom = "qualified_from"
            case timestamp = "time"
            case data
        }

        let id: UUID?
        let qualifiedID: QualifiedUserID?
        let from: UUID?
        let qualifiedFrom: QualifiedUserID?
        let timestamp: Date?
        let data: T
    }

    struct PaginatedConversationIDList: Paginatable {

        enum CodingKeys: String, CodingKey {
            case conversations
            case hasMore = "has_more"
        }

        var nextStartReference: String? {
            return conversations.last?.transportString()
        }

        let conversations: [UUID]
        let hasMore: Bool
    }
}

