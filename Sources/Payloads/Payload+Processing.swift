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

extension Payload.UserClient {

    func update(_ client: WireDataModel.UserClient) {
        client.needsToBeUpdatedFromBackend = false

        guard
            client.user?.isSelfUser == false,
            let deviceClass = deviceClass
        else { return }

        client.deviceClass = DeviceClass(rawValue: deviceClass)
    }

    func createOrUpdateClient(for user: ZMUser) -> WireDataModel.UserClient {
        let client = WireDataModel.UserClient.fetchUserClient(withRemoteId: id, forUser: user, createIfNeeded: true)!

        update(client)

        return client
    }
    
}

extension Array where Array.Element == Payload.UserClient {

    func updateClients(for user: ZMUser, selfClient: UserClient) {
        let clients: [UserClient] = map { $0.createOrUpdateClient(for: user) }

        // Remove clients that have not been included in the response
        let deletedClients = user.clients.subtracting(clients)
        deletedClients.forEach {
            $0.deleteClientAndEndSession()
        }

        // Mark new clients as missed and ignore them
        let newClients = Set(clients.filter({ $0.isInserted || !$0.hasSessionWithSelfClient }))
        selfClient.missesClients(newClients)
        selfClient.addNewClientsToIgnored(newClients)
        selfClient.updateSecurityLevelAfterDiscovering(newClients)
    }

}

extension Payload.UserProfile {

    /// Update a user entity with the data from a user profile payload.
    ///
    /// A user profile payload comes in two variants: full and delta, a full update is
    /// used to initially sync the entity with the server state. After this the entity
    /// can be updated with delta updates, which only contain the fields which have changed.
    ///
    /// - parameter user: User entity which on which the update should be applied.
    /// - parameter authoritative: If **true** the update will be applied as if the update
    ///                            is a full update, any missing fields will be removed from
    ///                            the entity.
    func updateUserProfile(for user: ZMUser, authoritative: Bool = true) {

        if let qualifiedID = qualifiedID {
            precondition(user.remoteIdentifier == nil || user.remoteIdentifier == qualifiedID.uuid)
            precondition(user.domain == nil || user.domain == qualifiedID.domain)

            user.remoteIdentifier = qualifiedID.uuid
            user.domain = qualifiedID.domain
        } else if let id = id {
            precondition(user.remoteIdentifier == nil || user.remoteIdentifier == id)

            user.remoteIdentifier = id
        }

        if let serviceID = serviceID {
            user.serviceIdentifier = serviceID.id.transportString()
            user.providerIdentifier = serviceID.provider.transportString()
        }

        if (updatedKeys.contains(.teamID) || authoritative) {
            user.teamIdentifier = teamID
            user.createOrDeleteMembershipIfBelongingToTeam()
        }

        if SSOID != nil || authoritative {
            user.usesCompanyLogin = SSOID != nil
        }

        if isDeleted == true {
            user.markAccountAsDeleted(at: Date())
        }

        if (name != nil || authoritative) && !user.isAccountDeleted {
            user.name = name
        }

        if (updatedKeys.contains(.phone) || authoritative) && !user.isAccountDeleted {
            user.phoneNumber = phone?.removingExtremeCombiningCharacters
        }
        
        if (updatedKeys.contains(.email) || authoritative) && !user.isAccountDeleted {
            user.emailAddress = email?.removingExtremeCombiningCharacters
        }

        if (handle != nil || authoritative) && !user.isAccountDeleted {
            user.handle = handle
        }

        if (managedBy != nil || authoritative) {
             user.managedBy = managedBy
        }

        if let accentColor = accentColor, let accentColorValue = ZMAccentColor(rawValue: Int16(accentColor)) {
            user.accentColorValue = accentColorValue
        }

        if let expiresAt = expiresAt {
            user.expiresAt = expiresAt
        }

        updateAssets(for: user, authoritative: authoritative)

        if authoritative {
            user.needsToBeUpdatedFromBackend = false
        }

        user.updatePotentialGapSystemMessagesIfNeeded()
    }

    func updateAssets(for user: ZMUser, authoritative: Bool = true) {
        let assetKeys = Set(arrayLiteral: ZMUser.previewProfileAssetIdentifierKey, ZMUser.completeProfileAssetIdentifierKey)
        guard !user.hasLocalModifications(forKeys: assetKeys) else {
            return
        }

        let validAssets = assets?.filter(\.key.isValidAssetID)
        let previewAssetKey = validAssets?.first(where: {$0.size == .preview }).map(\.key)
        let completeAssetKey = validAssets?.first(where: {$0.size == .complete }).map(\.key)

        if previewAssetKey != nil || authoritative {
            user.previewProfileAssetIdentifier = previewAssetKey
        }

        if completeAssetKey != nil || authoritative {
            user.completeProfileAssetIdentifier = completeAssetKey
        }
    }

}

extension Payload.UserProfiles {


    /// Update all user entities with the data from the user profiles.
    ///
    /// - parameter context: `NSManagedObjectContext` on which the update should be performed.
    func updateUserProfiles(in context: NSManagedObjectContext) {

        for userProfile in self {
            guard
                let id = userProfile.id ?? userProfile.qualifiedID?.uuid,
                let user = ZMUser.fetch(with: id, domain: userProfile.qualifiedID?.domain, in: context)
            else {
                continue
            }

            userProfile.updateUserProfile(for: user)
        }
    }

}

extension Payload.PrekeyByUserID {

    /// Establish new sessions using the prekeys retreived for each client.
    ///
    /// - parameter selfClient: The self user's client
    /// - parameter context: The `NSManagedObjectContext` on which the operation should be performed
    /// - parameter domain: originating domain of the clients.
    ///
    /// - returns `True` if there's more sessions which needs to be established.
    func establishSessions(with selfClient: UserClient,
                           context: NSManagedObjectContext,
                           domain: String? = nil) -> Bool {
        for (userID, prekeyByClientID) in self {
            for (clientID, prekey) in prekeyByClientID {
                guard
                    let userID = UUID(uuidString: userID),
                    let user = ZMUser.fetch(with: userID, domain: domain, in: context),
                    let missingClient = UserClient.fetchUserClient(withRemoteId: clientID,
                                                                   forUser: user,
                                                                   createIfNeeded: true)
                else {
                    continue
                }

                if let prekey = prekey {
                    missingClient.establishSessionAndUpdateMissingClients(prekey: prekey,
                                                                          selfClient: selfClient)
                } else {
                    missingClient.markClientAsInvalidAfterFailingToRetrievePrekey(selfClient: selfClient)
                }


            }
        }

        let hasMoreMissingClients = (selfClient.missingClients?.count ?? 0) > 0

        return hasMoreMissingClients
    }

}

extension Payload.PrekeyByQualifiedUserID {

    /// Establish new sessions using the prekeys retreived for each client.
    ///
    /// - parameter selfClient: The self user's client
    /// - parameter context: The `NSManagedObjectContext` on which the operation should be performed
    ///
    /// - returns `True` if there's more sessions which needs to be established.
    func establishSessions(with selfClient: UserClient, context: NSManagedObjectContext) -> Bool {
        for (domain, prekeyByUserID) in self {
            _ = prekeyByUserID.establishSessions(with: selfClient, context: context, domain: domain)
        }

        let hasMoreMissingClients = (selfClient.missingClients?.count ?? 0) > 0

        return hasMoreMissingClients
    }

}

extension UserClient {

    /// Creates session and update missing clients and messages that depend on those clients
    fileprivate func establishSessionAndUpdateMissingClients(prekey: Payload.Prekey,
                                                             selfClient: UserClient) {

        let sessionCreated = selfClient.establishSessionWithClient(self,
                                                                   usingPreKey: prekey.key)

       // If the session creation failed, the client probably has corrupted prekeys,
       // we mark the client in order to send him a bogus message and not block all requests
       failedToEstablishSession = !sessionCreated
       clearMessagesMissingRecipient()
       selfClient.removeMissingClient(self)
   }

    fileprivate func markClientAsInvalidAfterFailingToRetrievePrekey(selfClient: UserClient) {
        failedToEstablishSession = true
        clearMessagesMissingRecipient()
        selfClient.removeMissingClient(self)
    }

    fileprivate func clearMessagesMissingRecipient() {
        messagesMissingRecipient.forEach {
            if let message = $0 as? ZMOTRMessage {
                message.doesNotMissRecipient(self)
            } else {
                mutableSetValue(forKey: "messagesMissingRecipient").remove($0)
            }
        }
    }

}
