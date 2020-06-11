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

/// Holds a list of received event IDs
@objc public protocol PreviouslyReceivedEventIDsCollection: NSObjectProtocol {
    func discardListOfAlreadyReceivedPushEventIDs()
}

public protocol NotificationStreamSyncDelegate: class {
    func fetchedEvents(_ events: [ZMUpdateEvent], hasMoreToFetch: Bool)
    func failedFetchingEvents()
}

public class NotificationStreamSync: NSObject, ZMRequestGenerator, ZMSimpleListRequestPaginatorSync {
    
    private var paginator: ZMSimpleListRequestPaginator?
    private var notificationsTracker: NotificationsTracker?
    private var listPaginator: ZMSimpleListRequestPaginator!
    private var managedObjectContext: NSManagedObjectContext!
    private var previouslyReceivedEventIDsCollection: PreviouslyReceivedEventIDsCollection?
    private var notificationStreamSyncDelegate: NotificationStreamSyncDelegate?

    public init(moc: NSManagedObjectContext,
                notificationsTracker: NotificationsTracker,
                eventIDsCollection: PreviouslyReceivedEventIDsCollection,
                delegate: NotificationStreamSyncDelegate) {
        super.init()
        managedObjectContext = moc
        previouslyReceivedEventIDsCollection = eventIDsCollection
        listPaginator = ZMSimpleListRequestPaginator.init(basePath: "/notifications",
                                                          startKey: "since",
                                                          pageSize: 500,
                                                          managedObjectContext: moc,
                                                          includeClientID: true,
                                                          transcoder: self)
        self.notificationsTracker = notificationsTracker
        notificationStreamSyncDelegate = delegate
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        
       // We only reset the paginator if it is neither in progress nor has more pages to fetch.
        if listPaginator.status != ZMSingleRequestProgress.inProgress && !listPaginator.hasMoreToFetch {
            listPaginator.resetFetching()
        }
        
        guard let request = listPaginator.nextRequest() else {
            return nil
        }
        request.forceToVoipSession()
        notificationsTracker?.registerStartStreamFetching()
        request.add(ZMCompletionHandler(on: self.managedObjectContext, block: { (response) in
            self.notificationsTracker?.registerFinishStreamFetching()
        }))

        return request
    }
    
    private var lastUpdateEventID: UUID? {
        return self.managedObjectContext.zm_lastNotificationID
    }
    
    @objc(nextUUIDFromResponse:forListPaginator:)
    public func nextUUID(from response: ZMTransportResponse!, forListPaginator paginator: ZMSimpleListRequestPaginator!) -> UUID! {
        if let timestamp = response.payload?.asDictionary()?["time"] {
            updateServerTimeDeltaWith(timestamp: timestamp as! String)
        }
        let latestEventId = processUpdateEventsAndReturnLastNotificationID(from: response.payload)
        
        if latestEventId != nil && response.httpStatus != 404 {
            return latestEventId
        }
        
        if !listPaginator.hasMoreToFetch {
            previouslyReceivedEventIDsCollection?.discardListOfAlreadyReceivedPushEventIDs() //Check it!
        }
        
        appendPotentialGapSystemMessageIfNeeded(with: response)
        return lastUpdateEventID
    }
    
    @objc(processUpdateEventsAndReturnLastNotificationIDFromPayload:)
    func processUpdateEventsAndReturnLastNotificationID(from payload: ZMTransportData?) -> UUID? {
        
        let tp = ZMSTimePoint.init(interval: 10, label: NSStringFromClass(type(of: self)))
        
        var latestEventId: UUID? = nil
        let source = ZMUpdateEventSource.pushNotification
        
        guard let eventsDictionaries = eventDictionariesFrom(payload: payload) else {
            return nil
        }
        for eventDictionary in eventsDictionaries {
            guard let events = ZMUpdateEvent.eventsArray(from: eventDictionary as ZMTransportData, source: source) else {
                return nil
            }
            notificationStreamSyncDelegate?.fetchedEvents(events, hasMoreToFetch: !self.listPaginator.hasMoreToFetch)
            latestEventId = events.last(where: { !$0.isTransient })?.uuid
        }
        
        //        ZMLogWithLevelAndTag(ZMLogLevelInfo, ZMTAG_EVENT_PROCESSING, @"Downloaded %lu event(s)", (unsigned long)parsedEvents.count);
        
        tp?.warnIfLongerThanInterval()
        return latestEventId
    }
    
    @objc(shouldParseErrorForResponse:)
    public func shouldParseError(for response: ZMTransportResponse) -> Bool {
        notificationStreamSyncDelegate?.failedFetchingEvents()
        return response.httpStatus == 404 ? true : false
    }
    
    @objc(appendPotentialGapSystemMessageIfNeededWithResponse:)
    func appendPotentialGapSystemMessageIfNeeded(with response: ZMTransportResponse) {
        // A 404 by the BE means we can't get all notifications as they are not stored anymore
        // and we want to issue a system message. We still might have a payload with notifications that are newer
        // than the commissioning time, the system message should be inserted between the old messages and the potentional
        // newly received ones in the payload.
        
        if response.httpStatus == 404 {
            var timestamp: Date? = nil
            let offset = 0.1
            
            if let eventsDictionaries = eventDictionariesFrom(payload: response.payload),
                let firstEvent = eventsDictionaries.first  {
                
                let event = ZMUpdateEvent.eventsArray(fromPushChannelData: firstEvent as ZMTransportData)?.first
                // In case we receive a payload together with the 404 we set the timestamp of the system message
                // to be 1/10th of a second older than the oldest received notification for it to appear above it.
                
                timestamp = event?.timeStamp()?.addingTimeInterval(-offset)
            }
            
            guard let conversations = self.managedObjectContext.executeFetchRequestOrAssert(ZMConversation.sortedFetchRequest()) as? [ZMConversation] else {
                return
            }
            for conversation in conversations {
                if timestamp == nil {
                    // In case we did not receive a payload we will add 1/10th to the last modified date of
                    // the conversation to make sure it appears below the last message
                    timestamp = conversation.lastModifiedDate?.addingTimeInterval(offset) ?? Date()
                }
                if let timestamp = timestamp {
                    conversation.appendNewPotentialGapSystemMessage(users: conversation.localParticipants, timestamp: timestamp)
                }
            }
        }
    }
}

// MARK: Private

extension NotificationStreamSync {
    private func updateServerTimeDeltaWith(timestamp: String) {
        let serverTime = NSDate(transport: timestamp)
        guard let serverTimeDelta = serverTime?.timeIntervalSinceNow else {
            return
        }
        self.managedObjectContext.serverTimeDelta = serverTimeDelta
    }
    
    private func eventDictionariesFrom(payload: ZMTransportData?) -> [[String: Any]]? {
        return payload?.asDictionary()?["notifications"] as? [[String: Any]]
    }
}
