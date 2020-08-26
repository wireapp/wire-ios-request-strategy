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
import UserNotifications

/// Creates and cancels local notifications
@objcMembers public class LocalNotificationDispatcher: NSObject {

    public static let ZMShouldHideNotificationContentKey = "ZMShouldHideNotificationContentKey"

    public let eventNotifications: ZMLocalNotificationSet
    public let callingNotifications: ZMLocalNotificationSet
    public let failedMessageNotifications: ZMLocalNotificationSet

    public var notificationCenter: UserNotificationCenter = UNUserNotificationCenter.current()

    public let syncMOC: NSManagedObjectContext
    fileprivate var observers: [Any] = []

    var localNotificationBuffer = [ZMLocalNotification]()

    @objc(initWithManagedObjectContext:)
    public init(in managedObjectContext: NSManagedObjectContext) {
        self.syncMOC = managedObjectContext
        self.eventNotifications = ZMLocalNotificationSet(archivingKey: "ZMLocalNotificationDispatcherEventNotificationsKey", keyValueStore: managedObjectContext)
        self.failedMessageNotifications = ZMLocalNotificationSet(archivingKey: "ZMLocalNotificationDispatcherFailedNotificationsKey", keyValueStore: managedObjectContext)
        self.callingNotifications = ZMLocalNotificationSet(archivingKey: "ZMLocalNotificationDispatcherCallingNotificationsKey", keyValueStore: managedObjectContext)
        super.init()
        observers.append(
            NotificationInContext.addObserver(name: ZMConversation.lastReadDidChangeNotificationName,
                                              context: managedObjectContext.notificationContext,
                                              using: { [weak self] in self?.cancelNotificationForLastReadChanged(notification: $0)})
        )
    }
    
    public func scheduleLocalNotification(_ note: ZMLocalNotification) {
        Logging.push.safePublic("Scheduling local notification with id=\(note.id)")
        
        notificationCenter.add(note.request, withCompletionHandler: nil)
    }

    /// Determines if the notification content should be hidden as reflected in the store
    /// metatdata for the given managed object context.
    ///
    public static func shouldHideNotificationContent(moc: NSManagedObjectContext?) -> Bool {
        let value = moc?.persistentStoreMetadata(forKey: ZMShouldHideNotificationContentKey) as? NSNumber
        return value?.boolValue ?? false
    }
}

// MARK: - Canceling notifications

extension LocalNotificationDispatcher {

    private var allNotificationSets: [ZMLocalNotificationSet] {
        return [self.eventNotifications,
                self.failedMessageNotifications,
                self.callingNotifications]
    }

    /// Can be used for cancelling all conversations if need
    public func cancelAllNotifications() {
        self.allNotificationSets.forEach { $0.cancelAllNotifications() }
    }

    /// Cancels all notifications for a specific conversation
    /// - note: Notifications for a specific conversation are otherwise deleted automatically when the message window changes and
    /// ZMConversationDidChangeVisibleWindowNotification is called
    public func cancelNotification(for conversation: ZMConversation) {
        self.allNotificationSets.forEach { $0.cancelNotifications(conversation) }
    }
    
    public func cancelMessageForEditingMessage(_ genericMessage: GenericMessage) {
        var idToDelete : UUID?
        
        if genericMessage.hasEdited {
            let replacingID = genericMessage.edited.replacingMessageID
            idToDelete = UUID(uuidString: replacingID)
        }
        else if genericMessage.hasDeleted {
            let deleted = genericMessage.deleted.messageID
            idToDelete = UUID(uuidString: deleted)
        }
        else if genericMessage.hasHidden {
            let hidden = genericMessage.hidden.messageID
            idToDelete = UUID(uuidString: hidden)
        }
        
        if let idToDelete = idToDelete {
            eventNotifications.cancelCurrentNotifications(messageNonce: idToDelete)
        }
    }

    /// Cancels all notification in the conversation that is speficied as object of the notification
    func cancelNotificationForLastReadChanged(notification: NotificationInContext) {
        guard let conversation = notification.object as? ZMConversation else { return }
        let isUIObject = conversation.managedObjectContext?.zm_isUserInterfaceContext ?? false

        self.syncMOC.performGroupedBlock {
            if isUIObject {
                // clear all notifications for this conversation
                if let syncConversation = (try? self.syncMOC.existingObject(with: conversation.objectID)) as? ZMConversation {
                    self.cancelNotification(for: syncConversation)
                }
            } else {
                self.cancelNotification(for: conversation)
            }
        }
    }
}
