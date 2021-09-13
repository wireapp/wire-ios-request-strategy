// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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

extension Payload {

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
