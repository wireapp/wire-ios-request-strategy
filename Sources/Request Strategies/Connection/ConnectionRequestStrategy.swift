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

public class ConnectionRequestStrategy: AbstractRequestStrategy, FederationAware, ZMRequestGeneratorSource, ZMContextChangeTrackerSource {

    public var useFederationEndpoint: Bool = false {
        didSet {
            connectToUserActionHandler.useFederationEndpoint = useFederationEndpoint
            updateConnectionActionHandler.useFederationEndpoint = useFederationEndpoint
        }
    }

    let eventsToProcess: [ZMUpdateEventType] = [
        .userConnection
    ]

    var isFetchingAllConnections: Bool = false
    let syncProgress: SyncProgress
    let connectionByIDSync: IdentifierObjectSync<ConnectionByIDTranscoder>
    let connectionByIDTransoder: ConnectionByIDTranscoder
    let connectionByQualifiedIDSync: IdentifierObjectSync<ConnectionByQualifiedIDTranscoder>
    let connectionByQualifiedIDTranscoder: ConnectionByQualifiedIDTranscoder
    let localConnectionListSync: PaginatedSync<Payload.PaginatedLocalConnectionList>
    let connectionListSync: PaginatedSync<Payload.PaginatedConnectionList>
    let updateSync: KeyPathObjectSync<ConnectionRequestStrategy>
    let connectToUserActionHandler: ConnectToUserActionHandler
    let updateConnectionActionHandler: UpdateConnectionActionHandler
    let actionSync: EntityActionSync


    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                applicationStatus: ApplicationStatus,
                syncProgress: SyncProgress) {

        self.syncProgress = syncProgress
        self.localConnectionListSync =
            PaginatedSync<Payload.PaginatedLocalConnectionList>(basePath: "/connections",
                                                                pageSize: 200,
                                                                context: managedObjectContext)

        self.connectionListSync =
            PaginatedSync<Payload.PaginatedConnectionList>(basePath: "/list-connections",
                                                           pageSize: 200,
                                                           method: .post,
                                                           context: managedObjectContext)

        connectionByIDTransoder = ConnectionByIDTranscoder(context: managedObjectContext)
        connectionByIDSync = IdentifierObjectSync(managedObjectContext: managedObjectContext,
                                                  transcoder: connectionByIDTransoder)
        connectionByQualifiedIDTranscoder = ConnectionByQualifiedIDTranscoder(context: managedObjectContext)
        connectionByQualifiedIDSync = IdentifierObjectSync(managedObjectContext: managedObjectContext, transcoder: connectionByQualifiedIDTranscoder)

        self.updateSync = KeyPathObjectSync(entityName: ZMConnection.entityName(), \.needsToBeUpdatedFromBackend)

        self.connectToUserActionHandler = ConnectToUserActionHandler(context: managedObjectContext)
        self.updateConnectionActionHandler = UpdateConnectionActionHandler(context: managedObjectContext)
        self.actionSync = EntityActionSync(actionHandlers: [
            connectToUserActionHandler,
            updateConnectionActionHandler
        ])

        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)

        self.configuration = [.allowsRequestsWhileOnline,
                              .allowsRequestsDuringSlowSync]

        updateSync.transcoder = self
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        if syncProgress.currentSyncPhase == .fetchingConnections {
            fetchAllConnections()
        }

        return requestGenerators.nextRequest()
    }

    func fetchAllConnections() {
        guard !isFetchingAllConnections else { return }

        isFetchingAllConnections = true

        let context = self.managedObjectContext

        if useFederationEndpoint {
            connectionListSync.fetch { [weak self] result in
                switch result {
                case .success(let connectionList):
                    connectionList.connections.forEach { $0.updateOrCreate(in: context) }

                    if !connectionList.hasMore {
                        self?.syncProgress.finishCurrentSyncPhase(phase: .fetchingConnections)
                        self?.isFetchingAllConnections = false
                    }
                case .failure:
                    self?.syncProgress.failCurrentSyncPhase(phase: .fetchingConnections)
                }
            }
        } else {
            localConnectionListSync.fetch { [weak self] (result) in
                switch result {
                case .success(let connectionList):
                    connectionList.connections.forEach { $0.updateOrCreate(in: context) }

                    if !connectionList.hasMore {
                        self?.syncProgress.finishCurrentSyncPhase(phase: .fetchingConnections)
                        self?.isFetchingAllConnections = false
                    }
                case .failure:
                    self?.syncProgress.failCurrentSyncPhase(phase: .fetchingConnections)
                }
            }
        }
    }

    public var requestGenerators: [ZMRequestGenerator] {
        if syncProgress.currentSyncPhase == .fetchingConnections {
            return [connectionListSync,
                    localConnectionListSync]
        } else {
            return [connectionByIDSync,
                    connectionByQualifiedIDSync,
                    actionSync]
        }
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [updateSync]
    }
    
}

extension ConnectionRequestStrategy: KeyPathObjectSyncTranscoder {

    typealias T = ZMConnection

    func synchronize(_ object: ZMConnection, completion: @escaping () -> Void) {
        if useFederationEndpoint {
            if let qualifiedID = object.to.qualifiedID {
                connectionByQualifiedIDSync.sync(identifiers: Set(arrayLiteral: qualifiedID))
            }
        } else {
            if let userID = object.to.remoteIdentifier {
                connectionByIDSync.sync(identifiers: Set(arrayLiteral: userID))
            }
        }
    }

    func cancel(_ object: ZMConnection) {
        
    }

}

extension ConnectionRequestStrategy: ZMEventConsumer {

    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        for event in events {
            guard
                eventsToProcess.contains(event.type),
                let payloadAsDictionary = event.payload as? [String: Any],
                let payloadData = try? JSONSerialization.data(withJSONObject: payloadAsDictionary, options: [])
            else {
                continue
            }

            switch event.type {
            case .userConnection:
                let conversationEvent = Payload.UserConnectionEvent(payloadData)
                conversationEvent?.process(in: managedObjectContext)
            default:
                break
            }
        }
    }

}

class ConnectionByIDTranscoder: IdentifierObjectSyncTranscoder {
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
        guard let userID = identifiers.first.map({ $0 }) else { return nil }

        // GET /connections/<UUID>
        return ZMTransportRequest(getFromPath: "/connections/\(userID)")
    }

    func didReceive(response: ZMTransportResponse, for identifiers: Set<UUID>) {
        guard
            let userID = identifiers.first,
            let connection = ZMConnection.fetch(userID: userID, domain: nil, in: context)
        else {
            Logging.eventProcessing.error("Can't update connection since it was found, aborting...")
            return
        }

        guard response.result != .permanentError else {
            connection.needsToBeUpdatedFromBackend = false
            return
        }

        guard
            let rawData = response.rawData,
            let payload = Payload.Connection(rawData, decoder: decoder)
        else {
            Logging.network.warn("Can't process response, aborting.")
            return
        }

        payload.update(connection, in: context)
    }

}

class ConnectionByQualifiedIDTranscoder: IdentifierObjectSyncTranscoder {
    public typealias T = QualifiedID

    var fetchLimit: Int = 1
    var isAvailable: Bool = true

    let context: NSManagedObjectContext
    let decoder: JSONDecoder = .defaultDecoder
    let encoder: JSONEncoder = .defaultEncoder

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func request(for identifiers: Set<QualifiedID>) -> ZMTransportRequest? {
        guard let qualifiedID = identifiers.first.map({ $0 }) else { return nil }

        // GET /connections/domain/<UUID>
        return ZMTransportRequest(getFromPath: "/connections/\(qualifiedID.domain)/\(qualifiedID.uuid)")
    }

    func didReceive(response: ZMTransportResponse, for identifiers: Set<QualifiedID>) {
        guard
            let qualifiedID = identifiers.first,
            let connection = ZMConnection.fetch(userID: qualifiedID.uuid, domain: qualifiedID.domain, in: context)
        else {
            Logging.eventProcessing.error("Can't update connection since it was found, aborting...")
            return
        }

        guard response.result != .permanentError else {
            connection.needsToBeUpdatedFromBackend = false
            return
        }

        guard
            let rawData = response.rawData,
            let payload = Payload.Connection(rawData, decoder: decoder)
        else {
            Logging.network.error("Can't process response, aborting.")
            return
        }

        payload.update(connection, in: context)
    }

}

