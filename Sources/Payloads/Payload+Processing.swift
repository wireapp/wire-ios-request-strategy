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

        if (teamID != nil || authoritative) {
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

        if (phone != nil || authoritative) && !user.isAccountDeleted {
            user.phoneNumber = phone?.removingExtremeCombiningCharacters
        }

        if (email != nil || authoritative) && !user.isAccountDeleted {
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


    func updateUserProfiles(in context: NSManagedObjectContext) {

        for userProfile in self {
            guard
                let id = userProfile.id ?? userProfile.qualifiedID?.uuid,
                let user = ZMUser.fetchAndMerge(with: id, createIfNeeded: false, in: context)
            else {
                continue
            }

            userProfile.updateUserProfile(for: user)
        }
    }

}
