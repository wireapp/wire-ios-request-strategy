////
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

public class UserRichProfileRequestStrategy : AbstractRequestStrategy {
    
    var modifiedSync: ZMUpstreamModifiedObjectSync!
    
    override public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.modifiedSync = ZMUpstreamModifiedObjectSync(transcoder: self,
                                                         entityName: ZMUser.entityName(),
                                                         update: nil,
                                                         filter: ZMUser.predicateForSelfUser(),
                                                         keysToSync: [],
                                                         managedObjectContext: managedObjectContext)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return modifiedSync.nextRequest()
    }
}

extension UserRichProfileRequestStrategy : ZMUpstreamTranscoder {
    
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        return nil
//        guard let selfUser = managedObject as? ZMUser else { return nil }
//
//        let allProperties = Set(UserProperty.allCases.map(\.propertyName))
//
//        let intersect = allProperties.intersection(keys)
//
//        guard let first = intersect.first,
//            let property = UserProperty(propertyName: first) else {
//                return nil
//        }
//
//        let request: ZMTransportRequest
//
//        switch property {
//        case .readReceiptsEnabled:
//            request = property.upstreamRequest(newValue: property.transportValue(for: selfUser))
//        }
//
//        return ZMUpstreamRequest(keys: keys, transportRequest: request)
    }
    
    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> Any? {
        return nil
    }
    
    public func updateUpdatedObject(_ managedObject: ZMManagedObject,
                                    requestUserInfo: [AnyHashable : Any]? = nil,
                                    response: ZMTransportResponse,
                                    keysToParse: Set<String>) -> Bool {
        return false
    }
    
    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject,
                                             request upstreamRequest: ZMUpstreamRequest,
                                             response: ZMTransportResponse,
                                             keysToParse keys: Set<String>) -> Bool {
        return false
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil // we will never insert objects
    }
    
    public func updateInsertedObject(_ managedObject: ZMManagedObject,
                                     request upstreamRequest: ZMUpstreamRequest,
                                     response: ZMTransportResponse) {
        // we will never insert objects
    }
    
    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
}


extension UserRichProfileRequestStrategy : ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [modifiedSync]
    }
}
