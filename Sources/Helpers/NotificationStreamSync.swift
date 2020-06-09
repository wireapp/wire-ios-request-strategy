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

public class NotificationStreamSync: NSObject, ZMRequestGenerator, ZMSimpleListRequestPaginatorSync {
    
    private var paginator: ZMSimpleListRequestPaginator?
    private var notificationsTracker: NotificationsTracker?
    private var listPaginator: ZMSimpleListRequestPaginator!
    private var managedObjectContext: NSManagedObjectContext!

    public init(moc: NSManagedObjectContext,
                notificationsTracker: NotificationsTracker) {
        super.init()
        managedObjectContext = moc
        listPaginator = ZMSimpleListRequestPaginator.init(basePath: "/notifications",
                                                          startKey: "since",
                                                          pageSize: 500,
                                                          managedObjectContext: moc,
                                                          includeClientID: true,
                                                          transcoder: self)
        self.notificationsTracker = notificationsTracker
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
    
    
    
    public func nextUUID(from response: ZMTransportResponse!, forListPaginator paginator: ZMSimpleListRequestPaginator!) -> UUID! {
        
//              SyncStatus *syncStatus = self.syncStatus;
//              OperationStatus *operationStatus = self.operationStatus;
//

        if let timestamp = response.payload?.asDictionary()?["time"] {
            updateServerTimeDeltaWith(timestamp: timestamp as! String)
        }
        
//
//              NSUUID *latestEventId = [self processUpdateEventsAndReturnLastNotificationIDFromPayload:response.payload];
//
//              if (operationStatus.operationState == SyncEngineOperationStateBackgroundFetch) {
//                  // This call affects the `isFetchingStreamInBackground` property and should never preceed
//                  // the call to `processUpdateEventsAndReturnLastNotificationIDFromPayload:syncStrategy`.
//                  [self updateBackgroundFetchResultWithResponse:response];
//              }
//
//              if (latestEventId != nil) {
//                  if (response.HTTPStatus == 404 && self.isSyncing) {
//                      // If we fail during quick sync we need to re-enter slow sync and should not store the lastUpdateEventID until after the slowSync has been completed
//                      // Otherwise, if the device crashes or is restarted during slow sync, we lose the information that we need to perform a slow sync
//                      [syncStatus updateLastUpdateEventIDWithEventID:latestEventId];
//                      // TODO Sabine: What happens when we receive a 404 when we are fetching the notification for a push notification? In theory we would have to enter slow sync as well or at least not store the lastUpdateEventID until the next proper sync in the foreground
//                  }
//                  else {
//                      self.lastUpdateEventID = latestEventId;
//                  }
//              }
//
//              if (!self.listPaginator.hasMoreToFetch) {
//                  [self.previouslyReceivedEventIDsCollection discardListOfAlreadyReceivedPushEventIDs];
//              }
//
//              [self appendPotentialGapSystemMessageIfNeededWithResponse:response];
//
//              if (response.result == ZMTransportResponseStatusPermanentError && self.isSyncing){
//                  [syncStatus failCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
//              }
//
//              if (!self.listPaginator.hasMoreToFetch && self.isSyncing) {
//
//                  // The fetch of the notification stream was initiated after the push channel was established
//                  // so we must restart the fetching to be sure that we haven't missed any notifications.
//                  if (syncStatus.pushChannelEstablishedDate.timeIntervalSinceReferenceDate < self.listPaginator.lastResetFetchDate.timeIntervalSinceReferenceDate) {
//                      [syncStatus finishCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
//                  }
//              }
//
//              return self.lastUpdateEventID;
        return nil
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
}
