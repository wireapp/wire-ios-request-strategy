//
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

public class ClientMessageRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    let insertedObjectSync: InsertedObjectSync<ClientMessageRequestStrategy>
    let messageSync: ProteusMessageSync<ZMClientMessage>
    let messageExpirationTimer: MessageExpirationTimer
    let linkAttachmentsPreprocessor: LinkAttachmentsPreprocessor
    let localNotificationDispatcher: PushMessageHandler

    static func shouldBeSentPredicate(context: NSManagedObjectContext) -> NSPredicate {
        let notDelivered = NSPredicate(format: "%K == FALSE", DeliveredKey)
        let notExpired = NSPredicate(format: "%K == 0", ZMMessageIsExpiredKey)
        let fromSelf = NSPredicate(format: "%K == %@", ZMMessageSenderKey, ZMUser.selfUser(in: context))
        return NSCompoundPredicate(andPredicateWithSubpredicates: [notDelivered, notExpired, fromSelf])
    }

    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         localNotificationDispatcher: PushMessageHandler,
                         applicationStatus: ApplicationStatus) {

        self.insertedObjectSync = InsertedObjectSync(entity: ZMClientMessage.entity(),
                                                     insertPredicate: Self.shouldBeSentPredicate(context: managedObjectContext))
        self.messageSync = ProteusMessageSync<ZMClientMessage>(context: managedObjectContext,
                                                               applicationStatus: applicationStatus)
        self.localNotificationDispatcher = localNotificationDispatcher
        self.messageExpirationTimer = MessageExpirationTimer(moc: managedObjectContext, entityNames: [ZMClientMessage.entityName(), ZMAssetClientMessage.entityName()], localNotificationDispatcher: localNotificationDispatcher)
        self.linkAttachmentsPreprocessor = LinkAttachmentsPreprocessor(linkAttachmentDetector: LinkAttachmentDetectorHelper.defaultDetector(), managedObjectContext: managedObjectContext)

        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)

        self.configuration = [.allowsRequestsWhileOnline,
                              .allowsRequestsWhileInBackground]

        self.insertedObjectSync.transcoder = self

        self.messageSync.onRequestScheduled { [weak self] (message, _) in
            self?.messageExpirationTimer.stop(for: message)
        }
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [insertedObjectSync, messageExpirationTimer, self.linkAttachmentsPreprocessor] + messageSync.contextChangeTrackers
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return messageSync.nextRequest()
    }

    deinit {
        self.messageExpirationTimer.tearDown()
    }

}

extension ClientMessageRequestStrategy: InsertedObjectSyncTranscoder {

    typealias Object = ZMClientMessage

    func insert(object: ZMClientMessage, completion: @escaping () -> Void) {
        messageSync.sync(object) { [weak self] (result, response) in
            switch result {
            case .success:
                object.markAsSent()
                object.update(withPostPayload: response.payload?.asDictionary() ?? [:], updatedKeys: nil)
                self?.deleteMessageIfNecessary(object)
            case .failure(let error):
                switch error {
                case .expired, .gaveUpRetrying:
                    object.expire()
                    self?.localNotificationDispatcher.didFailToSend(object)
                }
            }
        }
    }

    private func deleteMessageIfNecessary(_ message: ZMClientMessage) {
        if let underlyingMessage = message.underlyingMessage {
            if underlyingMessage.hasReaction {
                managedObjectContext.delete(message)
            }
            if underlyingMessage.hasConfirmation {
                // NOTE: this will only be read confirmations since delivery confirmations
                // are not sent using the ClientMessageTranscoder
                managedObjectContext.delete(message)
            }
        }
    }

}