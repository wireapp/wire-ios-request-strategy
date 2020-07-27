//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

extension ZMUpdateEvent {
    
    private static let deliveryConfirmationDayThreshold = 7
    
    var conversationID: UUID? {
        return conversationUUID()
    }
    
    var senderID: UUID? {
        return senderUUID()
    }
    
    func needsDeliveryConfirmation(_ currentDate: Date = Date(),
                                   managedObjectContext: NSManagedObjectContext) -> Bool {
        guard
            let conversationID = conversationID,
            let conversation = ZMConversation.fetch(withRemoteIdentifier: conversationID, in: managedObjectContext), conversation.conversationType == .oneOnOne,
            let senderUUID = senderUUID(),
                senderUUID != ZMUser.selfUser(in: managedObjectContext).remoteIdentifier,
            let serverTimestamp = timeStamp(),
            let daysElapsed = Calendar.current.dateComponents([.day], from: serverTimestamp, to: currentDate).day
        else { return false }
        
        return daysElapsed <= ZMUpdateEvent.deliveryConfirmationDayThreshold
    }
}

@objcMembers
public final class DeliveryReceiptRequestStrategy: NSObject, RequestStrategy {
    
    private let managedObjectContext: NSManagedObjectContext
    private let genericMessageStrategy: GenericMessageRequestStrategy
    
    // MARK: - Init
    
    public init(managedObjectContext: NSManagedObjectContext,
                clientRegistrationDelegate: ClientRegistrationDelegate) {
        
        self.managedObjectContext = managedObjectContext
        self.genericMessageStrategy = GenericMessageRequestStrategy(context: managedObjectContext, clientRegistrationDelegate: clientRegistrationDelegate)
    }
    
    // MARK: - Methods
    
    public func nextRequest() -> ZMTransportRequest? {
        return genericMessageStrategy.nextRequest()
    }
}

// MARK: - Context Change Tracker

extension DeliveryReceiptRequestStrategy: ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.genericMessageStrategy]
    }
    
}

// MARK: - Event Consumer

extension DeliveryReceiptRequestStrategy: ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        
    }
    
    public func processEventsWhileInBackground(_ events: [ZMUpdateEvent]) {
        sendDeliveryReceipts(for: events)
    }
    
    private func sendDeliveryReceipts(for events: [ZMUpdateEvent]) {
        let messageByConversation = events.filter { (event) -> Bool in
            return event.type.isOne(of: .conversationOtrMessageAdd, .conversationOtrAssetAdd)
        }.partition(by: \.conversationID)
        
        messageByConversation.forEach { (key: UUID, value: [ZMUpdateEvent]) in
            guard let conversation = ZMConversation.fetch(withRemoteIdentifier: key,
                                                          in: managedObjectContext) else { return }
            
            let messagesBySender = value
                .filter({ $0.needsDeliveryConfirmation(managedObjectContext: managedObjectContext) })
                .partition(by: \.senderID)
            
            messagesBySender.forEach { (key: UUID, value: [ZMUpdateEvent]) in
                guard let sender = ZMUser.fetch(withRemoteIdentifier: key,
                                                in: managedObjectContext) else { return }
                
                guard let confirmation = Confirmation.init(messageIds: value.compactMap(\.messageNonce),
                                                           type: .delivered) else { return }
                
                genericMessageStrategy.schedule(message: GenericMessage(content: confirmation),
                                                inConversation: conversation,
                                                targetRecipients: .users(Set(arrayLiteral: sender)),
                                                completionHandler: nil)
            }
        }
    }
    
}
