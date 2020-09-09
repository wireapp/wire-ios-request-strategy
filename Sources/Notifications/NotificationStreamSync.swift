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

@objc
public protocol UpdateEventProcessor: class {
            
    @objc(storeUpdateEvents:ignoreBuffer:)
    func storeUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool)
    
    @objc(storeAndProcessUpdateEvents:ignoreBuffer:)
    func storeAndProcessUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool)
}

public protocol NotificationStreamSyncDelegate: class {
    func fetchedEvents(_ events: [ZMUpdateEvent], hasMoreToFetch: Bool)
    func failedFetchingEvents()
}

public class NotificationStreamSync: NSObject, ZMRequestGenerator, ZMSimpleListRequestPaginatorSync {
    
    private var notificationsTracker: NotificationsTracker?
    private var listPaginator: ZMSimpleListRequestPaginator!
    private var managedObjectContext: NSManagedObjectContext!
    private var notificationStreamSyncDelegate: NotificationStreamSyncDelegate?
    private var pushNotificationStatus: PushNotificationStatus!

    public init(moc: NSManagedObjectContext,
                notificationsTracker: NotificationsTracker?,
                delegate: NotificationStreamSyncDelegate,
                pushNotificationStatus: PushNotificationStatus) {
        super.init()
        managedObjectContext = moc
        listPaginator = ZMSimpleListRequestPaginator.init(basePath: "/notifications",
                                                          startKey: "since",
                                                          pageSize: 500,
                                                          managedObjectContext: moc,
                                                          includeClientID: true,
                                                          transcoder: self)
        self.notificationsTracker = notificationsTracker
        notificationStreamSyncDelegate = delegate
        self.pushNotificationStatus = pushNotificationStatus
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        
        if isFetchingStreamForAPNS /*|| isFetchingStreamInBackground*/ {
            // We only reset the paginator if it is neither in progress nor has more pages to fetch.
            if listPaginator.status != ZMSingleRequestProgress.inProgress && !listPaginator.hasMoreToFetch {
                listPaginator.resetFetching()
            }
            
            guard let request = listPaginator.nextRequest() else {
                return nil
            }
            if isFetchingStreamForAPNS {
                request.forceToVoipSession()
                notificationsTracker?.registerStartStreamFetching()
                request.add(ZMCompletionHandler(on: self.managedObjectContext, block: { (response) in
                    self.notificationsTracker?.registerFinishStreamFetching()
                }))
            }
            return request
        } else {
            return nil
        }
    }
    
    private var lastUpdateEventID: UUID? {
        set {
            self.managedObjectContext.zm_lastNotificationID = newValue
        }
        get {
            return self.managedObjectContext.zm_lastNotificationID
        }
    }
    
    public var isFetchingStreamForAPNS: Bool {
        return self.pushNotificationStatus.hasEventsToFetch
    }
    
//    public var isFetchingStreamInBackground: Bool {
//        return self.operationStatus.operationState == OperationState.background
//    }
    
    @objc(nextUUIDFromResponse:forListPaginator:)
    public func nextUUID(from response: ZMTransportResponse!, forListPaginator paginator: ZMSimpleListRequestPaginator!) -> UUID! {
        if let timestamp = response.payload?.asDictionary()?["time"] {
            updateServerTimeDeltaWith(timestamp: timestamp as! String)
        }
        let latestEventId = processUpdateEventsAndReturnLastNotificationID(from: response.payload)
        
        if latestEventId != nil && response.httpStatus != 404 {
            return latestEventId
        }
        
        appendPotentialGapSystemMessageIfNeeded(with: response)
        return lastUpdateEventID
    }
    
    public func startUUID() -> UUID? {
        return self.lastUpdateEventID
    }
    
    @objc(processUpdateEventsAndReturnLastNotificationIDFromPayload:)
    func processUpdateEventsAndReturnLastNotificationID(from payload: ZMTransportData?) -> UUID? {
        
        let tp = ZMSTimePoint.init(interval: 10, label: NSStringFromClass(type(of: self)))
        
        var eventIds: [UUID] = []
        var latestEventId: UUID? = nil
        let source = self.isFetchingStreamForAPNS/* || self.isFetchingStreamInBackground*/ ? ZMUpdateEventSource.pushNotification : ZMUpdateEventSource.download
        
        guard let eventsDictionaries = eventDictionariesFrom(payload: payload) else {
            return nil
        }
        for eventDictionary in eventsDictionaries {
            guard let events = ZMUpdateEvent.eventsArray(from: eventDictionary as ZMTransportData, source: source) else {
                return nil
            }
            notificationStreamSyncDelegate?.fetchedEvents(events, hasMoreToFetch: !self.listPaginator.hasMoreToFetch)
            latestEventId = events.last(where: { !$0.isTransient })?.uuid
            eventIds += events.compactMap { $0.uuid }
        }
        
        //        ZMLogWithLevelAndTag(ZMLogLevelInfo, ZMTAG_EVENT_PROCESSING, @"Downloaded %lu event(s)", (unsigned long)parsedEvents.count);
        pushNotificationStatus.didFetch(eventIds: eventIds, lastEventId: latestEventId, finished: !self.listPaginator.hasMoreToFetch)
        tp?.warnIfLongerThanInterval()
        return latestEventId
    }
    
    @objc(shouldParseErrorForResponse:)
    public func shouldParseError(for response: ZMTransportResponse) -> Bool {
        notificationStreamSyncDelegate?.failedFetchingEvents()
        pushNotificationStatus.didFailToFetchEvents()
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
                
                timestamp = event?.timestamp?.addingTimeInterval(-offset)
            }
            ZMConversation.appendNewPotentialGapSystemMessage(at: timestamp, inContext: self.managedObjectContext)
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
