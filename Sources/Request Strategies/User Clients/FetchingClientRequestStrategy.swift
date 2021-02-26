// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
import WireSystem
import WireTransport
import WireUtilities
import WireCryptobox
import WireDataModel

private let zmLog = ZMSLog(tag: "fetchClientRS")


public let ZMNeedsToUpdateUserClientsNotificationUserObjectIDKey = "userObjectID"

extension Decodable {
    
    
    /// Initialize object from JSON Data
    ///
    /// - parameter jsonData: JSON data as raw bytes
    
    init?(_ jsonData: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
            let container = try decoder.singleValueContainer()
            let rawDate = try container.decode(String.self)
            
            if let date = NSDate(transport: rawDate) {
                return date as Date
            } else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Expected date string to be ISO8601-formatted with fractional seconds")
            }
        })
        
        do {
            self = try decoder.decode(Self.self, from: jsonData)
        } catch {
            print("Failed to decode payload: \(error)")
            return nil
        }
    }
    
}

extension Encodable {
    
    
    /// Initialize object from JSON Data
    ///
    /// - parameter jsonData: JSON data as raw bytes
    
    var jsonData: Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom({ (date, encoder) in
            var container = encoder.singleValueContainer()
            try container.encode((date as NSDate).transportString())
        })
        
        return try? encoder.encode(self)
    }
    
}

@objc public extension ZMUser {
    
    func fetchUserClients() {
        NotificationInContext(name: FetchingClientRequestStrategy.needsToUpdateUserClientsNotificationName,
                              context: self.managedObjectContext!.notificationContext,
                              object: self.objectID).post()
    }
}

@objc
public final class FetchingClientRequestStrategy : AbstractRequestStrategy {

    fileprivate static let needsToUpdateUserClientsNotificationName = Notification.Name("ZMNeedsToUpdateUserClientsNotification")

    fileprivate var userClientsObserverToken: Any? = nil
    fileprivate var userClientsByUserID: IdentifierObjectSync<UserClientByUserIDTranscoder>
    fileprivate var userClientsByUserClientID: IdentifierObjectSync<UserClientByUserClientIDTranscoder>
    fileprivate var userClientsByQualifiedUserID: IdentifierObjectSync<UserClientByQualifiedUserIDTranscoder>
    
    fileprivate var userClientByUserIDTranscoder: UserClientByUserIDTranscoder
    fileprivate var userClientByUserClientIDTranscoder: UserClientByUserClientIDTranscoder
    fileprivate var userClientByQualifiedUserIDTranscoder: UserClientByQualifiedUserIDTranscoder
    
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        
        self.userClientByUserIDTranscoder = UserClientByUserIDTranscoder(managedObjectContext: managedObjectContext)
        self.userClientByUserClientIDTranscoder = UserClientByUserClientIDTranscoder(managedObjectContext: managedObjectContext)
        self.userClientByQualifiedUserIDTranscoder = UserClientByQualifiedUserIDTranscoder(managedObjectContext: managedObjectContext)
        
        self.userClientsByUserID = IdentifierObjectSync(managedObjectContext: managedObjectContext, transcoder: userClientByUserIDTranscoder)
        self.userClientsByUserClientID = IdentifierObjectSync(managedObjectContext: managedObjectContext, transcoder: userClientByUserClientIDTranscoder)
        self.userClientsByQualifiedUserID = IdentifierObjectSync(managedObjectContext: managedObjectContext, transcoder: userClientByQualifiedUserIDTranscoder)
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.configuration = [.allowsRequestsWhileOnline,
                              .allowsRequestsDuringQuickSync,
                              .allowsRequestsWhileInBackground]
        self.userClientsObserverToken = NotificationInContext.addObserver(name: FetchingClientRequestStrategy.needsToUpdateUserClientsNotificationName,
                                                                          context: self.managedObjectContext.notificationContext,
                                                                          object: nil)
        { [weak self] note in
            guard let `self` = self, let objectID = note.object as? NSManagedObjectID else { return }
            self.managedObjectContext.performGroupedBlock {
                guard let user = (try? self.managedObjectContext.existingObject(with: objectID)) as? ZMUser, let remoteIdentifier = user.remoteIdentifier else { return }
                self.userClientsByUserID.sync(identifiers: Set(arrayLiteral: remoteIdentifier))
                RequestAvailableNotification.notifyNewRequestsAvailable(self)
            }
        }
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return
            userClientsByUserClientID.nextRequest() ??
            userClientsByUserID.nextRequest() ??
            userClientsByQualifiedUserID.nextRequest()
    }
    
}

extension FetchingClientRequestStrategy: ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self]
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return UserClient.sortedFetchRequest(with: UserClient.predicateForNeedingToBeUpdatedFromBackend()!)
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        let clientsNeedingToBeUpdated = objects.compactMap({ $0 as? UserClient})
        
        fetch(userClients: clientsNeedingToBeUpdated)
    }
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        let clientsNeedingToBeUpdated = object.compactMap({ $0 as? UserClient}).filter(\.needsToBeUpdatedFromBackend)
        
        fetch(userClients: clientsNeedingToBeUpdated)
    }
    
    private func fetch(userClients: [UserClient]) {
        let initialResult: ([Payload.QualifiedUserID], [UserClientByUserClientIDTranscoder.UserClientID]) = ([], [])
        let result = userClients.reduce(into: initialResult) { (result, userClient) in

            // We prefer to by qualifiedUserID since can be done in batches and is more efficent, but if the server
            // does not support it we need to fallback to fetching by userClientID
            if let userID = userClient.user?.remoteIdentifier, let domain = userClient.user?.domain {
                result.0.append(Payload.QualifiedUserID(uuid: userID, domain: domain))
            } else if let userID = userClient.user?.remoteIdentifier, let clientID = userClient.remoteIdentifier {
                result.1.append(UserClientByUserClientIDTranscoder.UserClientID(userId: userID, clientId: clientID))
            }
        }

        userClientsByQualifiedUserID.sync(identifiers: Set(result.0))
        userClientsByUserClientID.sync(identifiers: Set(result.1))
    }
    
}

fileprivate final class UserClientByUserClientIDTranscoder: IdentifierObjectSyncTranscoder {
    
    struct UserClientID: Hashable {
        let userId: UUID
        let clientId: String
    }
    
    public typealias T = UserClientID
    
    var managedObjectContext: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    var fetchLimit: Int {
        return 1
    }
    
    public func request(for identifiers: Set<UserClientID>) -> ZMTransportRequest? {
        guard let identifier = identifiers.first else { return nil }
        
        //GET /users/<user-id>/clients/<client-id>
        return ZMTransportRequest(path: "/users/\(identifier.userId.transportString())/clients/\(identifier.clientId)", method: .methodGET, payload: nil)
    }
    
    public func didReceive(response: ZMTransportResponse, for identifiers: Set<UserClientID>) {

        guard let identifier = identifiers.first,
              let user = ZMUser(remoteID: identifier.userId, createIfNeeded: true, in: managedObjectContext),
              let client = UserClient.fetchUserClient(withRemoteId: identifier.clientId, forUser:user, createIfNeeded: true) else { return }
        
        if response.result == .permanentError {
            client.deleteClientAndEndSession()
        } else if let payload = response.payload as? [String: AnyObject] {
            client.update(with: payload)
            
            let selfClient = ZMUser.selfUser(in: managedObjectContext).selfClient()
            
            selfClient?.updateSecurityLevelAfterDiscovering(Set(arrayLiteral: client))
        }
    }
}

fileprivate final class UserClientByQualifiedUserIDTranscoder: IdentifierObjectSyncTranscoder {
                
    public typealias T = Payload.QualifiedUserID
    
    var managedObjectContext: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    var fetchLimit: Int {
        return 100
    }
    
    public func request(for identifiers: Set<Payload.QualifiedUserID>) -> ZMTransportRequest? {
        let payloadAsString = String(bytes: identifiers.jsonData!, encoding: .utf8)
    
        // POST /users/list-clients
        let path = NSString.path(withComponents: ["/users/list-clients"])
        return ZMTransportRequest(path: path, method: .methodPOST, payload: payloadAsString as ZMTransportData?)
    }
    
    public func didReceive(response: ZMTransportResponse, for identifiers: Set<Payload.QualifiedUserID>) {
        
        let payload = Payload.UserClientByDomain(response.rawData!)!
        let selfClient = ZMUser.selfUser(in: managedObjectContext).selfClient()!
                
        for (_, users) in payload {
            for (userID, clientPayloads) in users {
                let user = ZMUser.fetchAndMerge(with: UUID(uuidString: userID)!, createIfNeeded: true, in: managedObjectContext)!
                let clients: [UserClient] = clientPayloads.map { $0.createOrUpdateClient(for: user) }

                // Remove clients that have not been included in the response
                let deletedClients = user.clients.subtracting(clients)
                deletedClients.forEach {
                    $0.deleteClientAndEndSession()
                }
                
                // Mark new clients as missed and ignore them
                let newClients = Set(clients.filter({ !$0.hasSessionWithSelfClient }))
                selfClient.missesClients(newClients)
                selfClient.addNewClientsToIgnored(newClients)
                selfClient.updateSecurityLevelAfterDiscovering(newClients)
            }
        }
    }
}

fileprivate final class UserClientByUserIDTranscoder: IdentifierObjectSyncTranscoder {
    
    public typealias T = UUID
    
    var managedObjectContext: NSManagedObjectContext
    
    init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    var fetchLimit: Int {
        return 1
    }
    
    public func request(for identifiers: Set<UUID>) -> ZMTransportRequest? {
        guard let userId = identifiers.first?.transportString() else { return nil }
        
        //GET /users/<user-id>/clients
        let path = NSString.path(withComponents: ["/users", "\(userId)", "clients"])
        return ZMTransportRequest(path: path, method: .methodGET, payload: nil)
    }
    
    public func didReceive(response: ZMTransportResponse, for identifiers: Set<UUID>) {
        
        guard let identifier = identifiers.first,
              let user = ZMUser(remoteID: identifier, createIfNeeded: true, in: managedObjectContext),
              let selfClient = ZMUser.selfUser(in: managedObjectContext).selfClient() else { return }
        
        // Create clients from the response
        var newClients = Set<UserClient>()
        guard let arrayPayload = response.payload?.asArray() else { return }
        
        let clients: [UserClient] = arrayPayload.compactMap {
            guard let payload = $0 as? [String: AnyObject], let remoteIdentifier = payload["id"] as? String else { return nil }
            guard let client = UserClient.fetchUserClient(withRemoteId: remoteIdentifier, forUser:user, createIfNeeded: true) else { return nil }
            
            if client.isInserted {
                newClients.insert(client)
            }
            
            client.update(with: payload)
            return client
        }
        
        // Remove clients that have not been included in the response
        let deletedClients = Set(user.clients).subtracting(Set(clients))
        deletedClients.forEach {
            $0.deleteClientAndEndSession()
        }
        
        for client in clients {
            if client.hasSessionWithSelfClient { continue }
            // Add clients without a session to missed clients
            newClients.insert(client)
        }
        
        guard newClients.count > 0 else { return }
        selfClient.missesClients(Set(newClients))
        
        // add missing clients to ignored clients
        selfClient.addNewClientsToIgnored(newClients)
        selfClient.updateSecurityLevelAfterDiscovering(newClients)
    }
}
