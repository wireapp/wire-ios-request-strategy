//
//  PayloadProcessing+MessageSendingStatus.swift
//  WireRequestStrategy
//
//  Created by Jacob Persson on 07.10.21.
//  Copyright © 2021 Wire GmbH. All rights reserved.
//

import Foundation

// MARK: - Message sending

extension Payload.MessageSendingStatus {

    /// Updates the reported client changes after an attempt to send the message
    ///
    /// - Parameter message: message for which the message sending status was created
    /// - Returns *True* if the message was missing clients in the original payload.
    ///
    /// If a message was missing clients we should attempt to send the message again
    /// after establishing sessions with the missing clients.
    ///
    func updateClientsChanges(for message: OTREntity) -> Bool {

        let deletedClients = deleted.fetchClients(in: message.context)
        for (_, deletedClients) in deletedClients {
            deletedClients.forEach { $0.deleteClientAndEndSession() }
        }

        let redundantUsers = redundant.fetchUsers(in: message.context)
        if !redundantUsers.isEmpty {
            // if the BE tells us that these users are not in the
            // conversation anymore, it means that we are out of sync
            // with the list of participants
            message.conversation?.needsToBeUpdatedFromBackend = true

            // The missing users might have been deleted so we need re-fetch their profiles
            // to verify if that's the case.
            redundantUsers.forEach { $0.needsToBeUpdatedFromBackend = true }

            message.detectedRedundantUsers(redundantUsers)
        }

        let missingClients = missing.fetchOrCreateClients(in: message.context)
        for (user, userClients) in missingClients {
            userClients.forEach({ $0.discoveredByMessage = message as? ZMOTRMessage })
            message.registersNewMissingClients(Set(userClients))
            message.conversation?.addParticipantAndSystemMessageIfMissing(user, date: nil)
        }

        return !missingClients.isEmpty
    }

}
