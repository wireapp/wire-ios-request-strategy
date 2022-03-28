//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

public struct VOIPPushPayload: Codable {

    // MARK: - Properties

    let accountID: UUID
    let conversationID: UUID
    let conversationDomain: String?
    let senderID: UUID
    let senderDomain: String?
    let senderClientID: String
    let timestamp: Date
    let data: Data

    // MARK: - Life cycle

    public init?(from event: ZMUpdateEvent, accountID: UUID) {
        guard
            let message = GenericMessage(from: event),
            let data = message.calling.content.data(using: .utf8, allowLossyConversion: false),
            let conversationID = event.conversationUUID,
            let senderID = event.senderUUID,
            let senderClientID = event.senderClientID,
            let timestamp = event.timestamp
        else {
            return nil
        }

        self.accountID = accountID
        self.conversationID = conversationID
        self.conversationDomain = event.conversationDomain
        self.senderID = senderID
        self.senderDomain = event.senderDomain
        self.senderClientID = senderClientID
        self.timestamp = timestamp
        self.data = data
    }

    public init?(from dict: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
            let value = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return nil
        }

        self = value
    }

    // MARK: - Methods

    public var asDictionary: [String: Any]? {
        guard
            let data = try? JSONEncoder().encode(self),
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = json as? [String: Any]
        else {
            return nil
        }

        return dict
    }

}
