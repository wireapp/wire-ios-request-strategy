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
import WireDataModel

public class ConversationEventProcessor: NSObject, ConversationEventProcessorProtocol {

    // MARK: - Properties

    let context: NSManagedObjectContext

    // MARK: - Life cycle

    public init(context: NSManagedObjectContext) {
        self.context = context
        super.init()
    }

    // MARK: - Methods

    public func processConversationEvents(_ events: [ZMUpdateEvent]) {
        context.performAndWait {
            for event in events {
                switch event.type {
                case .conversationCreate:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.Conversation>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationDelete:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationDeleted>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationMemberLeave:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConverationMemberLeave>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationMemberJoin:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConverationMemberJoin>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationRename:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationName>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationMemberUpdate:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.ConversationMember>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationAccessModeUpdate:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationAccess>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationMessageTimerUpdate:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationMessageTimer>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationReceiptModeUpdate:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationReceiptMode>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationConnectRequest:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationConnectionRequest>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                case .conversationMLSWelcome:
                    guard let data = payloadData(from: event) else { break }
                    let conversationEvent = Payload.ConversationEvent<Payload.UpdateConversationMLSWelcome>(data)
                    conversationEvent?.process(in: context, originalEvent: event)

                default:
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private func payloadData(from event: ZMUpdateEvent) -> Data? {
        guard
            let payloadAsDictionary = event.payload as? [String: Any],
            let payloadData = try? JSONSerialization.data(withJSONObject: payloadAsDictionary, options: [])
        else {
            return nil
        }

        return payloadData
    }

}
