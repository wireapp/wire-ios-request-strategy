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

public class LinkPreviewUpdateRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource, FederationAware {

    let messageSync: ProteusMessageSync<ZMClientMessage>

    public var useFederationEndpoint: Bool {
        set {
            messageSync.useFederationEndpoint = newValue
        }
        get {
            messageSync.useFederationEndpoint
        }
    }

    static func linkPreviewIsUploadedPredicate(context: NSManagedObjectContext) -> NSPredicate {
        return NSPredicate(format: "%K == %@ AND %K == %d",
                           #keyPath(ZMClientMessage.sender), ZMUser.selfUser(in: context),
                           #keyPath(ZMClientMessage.linkPreviewState), ZMLinkPreviewState.uploaded.rawValue)
    }

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                  applicationStatus: ApplicationStatus) {

        let modifiedPredicate = Self.linkPreviewIsUploadedPredicate(context: managedObjectContext)
        self.messageSync = ProteusMessageSync<ZMClientMessage>(context: managedObjectContext,
                                                               applicationStatus: applicationStatus)

        messageSync.onCompleted { object, _, _ in
            object.linkPreviewState = .done
            object.resetLocallyModifiedKeys(Set(arrayLiteral: ZMClientMessage.linkPreviewStateKey))
        }

        messageSync.addSource(ModifiedKeySource(trackedKey: ZMClientMessage.linkPreviewStateKey,
                                                modifiedPredicate: modifiedPredicate))

        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)

        self.configuration = .allowsRequestsWhileOnline
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return messageSync.contextChangeTrackers
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return messageSync.nextRequest()
    }

}
