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

protocol Paginatable: Decodable {
    var hasMore: Bool { get }
    var nextStartReference: String? { get }
}

protocol PaginatableTranscoder: class {

    associatedtype Result: Paginatable

    func didReceiveResults(results: Result)
    func didPermanent(results: Result)

}

class PaginatedSync<Payload: Paginatable>: NSObject, ZMRequestGenerator {

    typealias CompletionHandler = (Swift.Result<Payload, PaginatedSyncError>) -> Void

    enum Status: Equatable {
        case fetching(_ state: String)
        case done
    }

    enum PaginatedSyncError: Error {
        case permanentError
    }

    let context: NSManagedObjectContext
    let basePath: String
    let pageSize: Int
    var status: Status = .done
    var request: ZMTransportRequest? = nil
    var completionHandler: CompletionHandler?

    init(basePath: String, pageSize: Int, context: NSManagedObjectContext) {
        self.basePath = basePath
        self.pageSize = pageSize
        self.context = context
    }

    func fetch(_ completionHandler: @escaping CompletionHandler) {
        self.completionHandler = completionHandler
        status = .fetching("")
    }

    func nextRequest() -> ZMTransportRequest? {
        guard request == nil, case .fetching(let start) = status else {
            return nil
        }

        var queryItems = [URLQueryItem(name: "size", value: String(pageSize))]

        if !start.isEmpty {
            queryItems.append(URLQueryItem(name: "start", value: start))
        }

        var urlComponents = URLComponents(string: basePath)
        urlComponents?.queryItems = queryItems

        guard let path = urlComponents?.string else {
            return nil
        }

        self.request = ZMTransportRequest(getFromPath: path)

        request?.add(ZMCompletionHandler(on: context, block: { (response) in
            self.request = nil

            guard let result = Payload(response, decoder: .defaultDecoder) else {
                if response.result == .permanentError {
                    self.completionHandler?(.failure(.permanentError))
                    self.status = .done
                }
                return
            }

            self.completionHandler?(.success(result))

            if result.hasMore, let nextStartReference = result.nextStartReference {
                self.status = .fetching(nextStartReference)
            } else {
                self.status = .done
            }
        }))

        return request
    }

}

public class ConversationRequestStrategy: AbstractRequestStrategy, ZMRequestGeneratorSource, ZMContextChangeTrackerSource {

    let syncProgress: SyncProgress
    let syncIDs: PaginatedSync<Payload.PaginatedConversationIDList>

    let conversationByIDTranscoder: ConversationByIDTranscoder
    let conversationByIDSync: IdentifierObjectSync<ConversationByIDTranscoder>

    let conversationByIDListTranscoder: ConversationByIDListTranscoder
    let conversationByIDListSync: IdentifierObjectSync<ConversationByIDListTranscoder>

    var insertSync: ZMUpstreamInsertedObjectSync!

    var isFetchingAllConversations: Bool = false

    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
         applicationStatus: ApplicationStatus,
         syncProgress: SyncProgress) {

        self.syncProgress = syncProgress
        self.syncIDs = PaginatedSync<Payload.PaginatedConversationIDList>(basePath: "/conversations/ids",
                                                                          pageSize: 32,
                                                                          context: managedObjectContext)

        self.conversationByIDListTranscoder = ConversationByIDListTranscoder(context: managedObjectContext)
        self.conversationByIDListSync = IdentifierObjectSync(managedObjectContext: managedObjectContext,
                                                             transcoder: conversationByIDListTranscoder)

        self.conversationByIDTranscoder = ConversationByIDTranscoder(context: managedObjectContext)
        self.conversationByIDSync = IdentifierObjectSync(managedObjectContext: managedObjectContext,
                                                         transcoder: conversationByIDTranscoder)

        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)

        self.insertSync = ZMUpstreamInsertedObjectSync(transcoder: self,
                                                       entityName: ZMConversation.entityName(),
                                                       managedObjectContext: managedObjectContext)

        self.configuration = [.allowsRequestsWhileOnline,
                              .allowsRequestsDuringSlowSync]

        self.conversationByIDListSync.delegate = self
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        if syncProgress.currentSyncPhase == .fetchingConversations {
            fetchAllConversations()
        }

        return requestGenerators.nextRequest()
    }

    func fetch(_ converations: Set<ZMConversation>) {
        conversationByIDSync.sync(identifiers: converations.compactMap(\.remoteIdentifier))
    }

    func fetchAllConversations() {
        guard !isFetchingAllConversations else { return }

        isFetchingAllConversations = true
        syncIDs.fetch { [weak self] (result) in
            switch result {
            case .success(let converationIDList):
                self?.conversationByIDListSync.sync(identifiers: converationIDList.conversations)
            case .failure:
                self?.syncProgress.failCurrentSyncPhase(phase: .fetchingConversations)
            }
        }
    }

    public var requestGenerators: [ZMRequestGenerator] {
        if syncProgress.currentSyncPhase == .fetchingConversations {
            return [syncIDs, conversationByIDListSync]
        } else {
            return [syncIDs, conversationByIDListSync, insertSync]
        }

    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self, insertSync]
    }
    
}

extension ConversationRequestStrategy: ZMContextChangeTracker {

    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        let conversationNeedingToBeUpdated = objects.compactMap({ $0 as? ZMConversation}).filter(\.needsToBeUpdatedFromBackend)

        fetch(Set(conversationNeedingToBeUpdated))
    }

    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return ZMConversation.sortedFetchRequest(with: ZMConversation.predicateForNeedingToBeUpdatedFromBackend()!)
    }

    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        guard let conversations = objects as? Set<ZMConversation> else {
            return
        }

        fetch(conversations)
    }

}

extension ConversationRequestStrategy: IdentifierObjectSyncDelegate {

    public func didFinishSyncingAllObjects() {
        guard
            syncProgress.currentSyncPhase == .fetchingConversations,
            syncIDs.status == .done,
            !conversationByIDListSync.isSyncing
        else {
            return
        }

        syncProgress.finishCurrentSyncPhase(phase: .fetchingConversations)
        isFetchingAllConversations = false
    }

    public func didFailToSyncAllObjects() {
        if syncProgress.currentSyncPhase == .fetchingConversations {
            syncProgress.failCurrentSyncPhase(phase: .fetchingConversations)
        }
    }

}

extension ConversationRequestStrategy: ZMUpstreamTranscoder {

    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }

    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject,
                                             request upstreamRequest: ZMUpstreamRequest,
                                             response: ZMTransportResponse,
                                             keysToParse keys: Set<String>) -> Bool {

        guard let newConversation = managedObject as? ZMConversation else {
            return false
        }

        if let responseFailure = Payload.ResponseFailure(response, decoder: .defaultDecoder),
           responseFailure.code == 412 && responseFailure.label == .missingLegalholdConsent {
            newConversation.notifyMissingLegalHoldConsent()
        }

        return false
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject,
                                     request upstreamRequest: ZMUpstreamRequest,
                                     response: ZMTransportResponse) {

        guard
            let newConversation = managedObject as? ZMConversation,
            let rawData = response.rawData,
            let payload = Payload.Conversation(rawData, decoder: .defaultDecoder),
            let conversationID = payload.id
        else {
            Logging.network.warn("Can't process response, aborting.")
            return
        }

        var deletedDuplicate = false
        if let existingConversation = ZMConversation.fetch(with: conversationID,
                                                           domain: payload.qualifiedID?.domain,
                                                           in: managedObjectContext) {
            managedObjectContext.delete(existingConversation)
            deletedDuplicate = true
        }

        newConversation.remoteIdentifier = conversationID
        payload.updateOrCreate(in: managedObjectContext)
        newConversation.needsToBeUpdatedFromBackend = deletedDuplicate
    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject,
                                    requestUserInfo: [AnyHashable : Any]? = nil,
                                    response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {

        return false
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }

    public func request(forUpdating managedObject: ZMManagedObject,
                        forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        return nil
    }

    public func request(forInserting managedObject: ZMManagedObject,
                        forKeys keys: Set<String>?) -> ZMUpstreamRequest? {

        guard let conversation = managedObject as? ZMConversation else {
            return nil
        }

        let payload = Payload.NewConversation(conversation)

        guard
            let payloadData = payload.payloadData(encoder: .defaultEncoder),
            let payloadAsString = String(bytes: payloadData, encoding: .utf8)
        else {
            return nil
        }

        let request = ZMTransportRequest(path: "/conversations",
                                         method: .methodPOST,
                                         payload: payloadAsString as ZMTransportData?)

        return ZMUpstreamRequest(transportRequest: request)
    }

}

class ConversationByIDTranscoder: IdentifierObjectSyncTranscoder {
    public typealias T = UUID

    var fetchLimit: Int = 1
    var isAvailable: Bool = true

    let context: NSManagedObjectContext
    let decoder: JSONDecoder = .defaultDecoder
    let encoder: JSONEncoder = .defaultEncoder

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func request(for identifiers: Set<UUID>) -> ZMTransportRequest? {
        guard let converationID = identifiers.first.map({ $0.transportString() }) else { return nil }

        // GET /conversations/<UUID>
        return ZMTransportRequest(getFromPath: "/conversations/\(converationID)")
    }

    func didReceive(response: ZMTransportResponse, for identifiers: Set<UUID>) {

        guard response.result != .permanentError else {
            if let responseFailure = Payload.ResponseFailure(response, decoder: decoder) {
                if responseFailure.code == 404, case .notFound = responseFailure.label {
                    deleteConversations(identifiers)
                    return
                }

                if responseFailure.code == 403 {
                    removeSelfUser(identifiers)
                    return
                }
            }

            markConversationsAsFetched(identifiers)
            return
        }
        

        guard
            let rawData = response.rawData,
            let payload = Payload.Conversation(rawData, decoder: decoder)
        else {
            Logging.network.warn("Can't process response, aborting.")
            return
        }

        payload.updateOrCreate(in: context)
    }

    private func deleteConversations(_ conversations: Set<UUID>) {
        for conversationID in conversations {
            guard
                let conversation = ZMConversation.fetch(with: conversationID, domain: nil, in: context),
                conversation.conversationType == .group
            else {
                continue
            }
            context.delete(conversation)
        }
    }

    private func removeSelfUser(_ conversations: Set<UUID>) {
        for conversationID in conversations {
            guard
                let conversation = ZMConversation.fetch(with: conversationID, domain: nil, in: context),
                conversation.conversationType == .group,
                conversation.isSelfAnActiveMember
            else {
                continue
            }
            let selfUser = ZMUser.selfUser(in: context)
            conversation.removeParticipantAndUpdateConversationState(user: selfUser, initiatingUser: selfUser)
            conversation.needsToBeUpdatedFromBackend = false
        }
    }

    private func markConversationsAsFetched(_ conversations: Set<UUID>) {
        for conversationID in conversations {
            guard
                let conversation = ZMConversation.fetch(with: conversationID, domain: nil, in: context)
            else {
                continue
            }
            conversation.needsToBeUpdatedFromBackend = false
        }
    }
}

class ConversationByIDListTranscoder: IdentifierObjectSyncTranscoder {

    public typealias T = UUID

    var fetchLimit: Int = 32
    var isAvailable: Bool = true

    let context: NSManagedObjectContext
    let decoder: JSONDecoder = .defaultDecoder
    let encoder: JSONEncoder = .defaultEncoder

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func request(for identifiers: Set<UUID>) -> ZMTransportRequest? {
        // GET /conversations?ids=?
        let converationIDs = identifiers.map({ $0.transportString() }).joined(separator: ",")
        return ZMTransportRequest(getFromPath: "/conversations?ids=\(converationIDs)")
    }

    func didReceive(response: ZMTransportResponse, for identifiers: Set<UUID>) {

        guard
            let rawData = response.rawData,
            let payload = Payload.ConversationList(rawData, decoder: decoder)
        else {
            Logging.network.warn("Can't process response, aborting.")
            return
        }

        payload.updateOrCreateConverations(in: context)

        let missingIdentifiers = identifiers.subtracting(payload.conversations.compactMap(\.id))
        queryStatusForMissingConversations(missingIdentifiers)
    }

    /// Query the backend if a converation is deleted or the self user has been removed
    private func queryStatusForMissingConversations(_ conversations: Set<UUID>) {
        for conversationID in conversations {
            let conversation = ZMConversation.fetch(with: conversationID, in: context)
            conversation?.needsToBeUpdatedFromBackend = true
        }
    }

}
