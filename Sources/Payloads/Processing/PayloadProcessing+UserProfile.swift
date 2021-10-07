//
//  PayloadProcessing+UserProfile.swift
//  WireRequestStrategy
//
//  Created by Jacob Persson on 07.10.21.
//  Copyright © 2021 Wire GmbH. All rights reserved.
//

import Foundation

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
