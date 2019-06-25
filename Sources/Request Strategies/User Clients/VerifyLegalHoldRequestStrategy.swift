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

/// This strategy observes the `needsToVerifyLegalHold` flag on conversations and fetches an updated list of available clients
/// and verifies that the legal hold status is correct.

@objc
public final class VerifyLegalHoldRequestStrategy: AbstractRequestStrategy {
    
    fileprivate let requestFactory =  ClientMessageRequestFactory()
    fileprivate var conversationSync: IdentifierObjectSync<VerifyLegalHoldRequestStrategy>!
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return conversationSync.nextRequest()
    }
    
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        configuration = [.allowsRequestsDuringEventProcessing, .allowsRequestsDuringNotificationStreamFetch, .allowsRequestsWhileInBackground]
        conversationSync = IdentifierObjectSync(managedObjectContext: managedObjectContext, transcoder: self)
    }
    
}

extension VerifyLegalHoldRequestStrategy:  ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self]
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return ZMConversation.sortedFetchRequest(with: NSPredicate(format: "needsToVerifyLegalHold != 0"))
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        let conversationsNeedingToVerifyClients = objects.compactMap({ $0 as? ZMConversation})
        
        conversationSync.sync(identifiers: conversationsNeedingToVerifyClients)
    }
    
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        let conversationsNeedingToVerifyClients = object.compactMap({ $0 as? ZMConversation}).filter(\.needsToVerifyLegalHold)
        
        if !conversationsNeedingToVerifyClients.isEmpty {
            conversationSync.sync(identifiers: conversationsNeedingToVerifyClients)
        }
    }
    
}

extension VerifyLegalHoldRequestStrategy: IdentifierObjectSyncTranscoder {
    public typealias T = ZMConversation
    
    public var fetchLimit: Int {
        return 1
    }
    
    public func request(for identifiers: Set<ZMConversation>) -> ZMTransportRequest? {
        guard let conversationID = identifiers.first?.remoteIdentifier, identifiers.count == 1,
              let selfClient = ZMUser.selfUser(in: managedObjectContext).selfClient()
        else { return nil }
        
        return requestFactory.upstreamRequestForFetchingClients(conversationId: conversationID, selfClient: selfClient)
    }
    
    public func didReceive(response: ZMTransportResponse, for identifiers: Set<ZMConversation>) {
        guard let conversation = identifiers.first else { return }
        
        let verifyClientsParser = VerifyClientsParser(context: managedObjectContext, conversation: conversation)

        let changeSet = verifyClientsParser.parseEmptyUploadResponse(response, in: conversation, clientRegistrationDelegate: applicationStatus!.clientRegistrationDelegate)
        conversation.updateSecurityLevelIfNeededAfterFetchingClients(changes: changeSet)
    }
    
}

fileprivate class VerifyClientsParser: OTREntity {
    
    var context: NSManagedObjectContext
    let conversation: ZMConversation
    
    init(context: NSManagedObjectContext, conversation: ZMConversation) {
        self.context = context
        self.conversation = conversation
    }
    
    func missesRecipients(_ recipients: Set<UserClient>!) {
        // no-op
    }
    
    func detectedRedundantClients() {
        conversation.needsToBeUpdatedFromBackend = true
    }
    
    func detectedMissingClient(for user: ZMUser) {
        // no-op
    }
    
    var dependentObjectNeedingUpdateBeforeProcessing: NSObject? = nil
    
    var isExpired: Bool = false
    
    func expire() {
        // no-op
    }
    
}
