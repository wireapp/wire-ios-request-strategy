//
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
import WireCryptobox

private let zmLog = ZMSLog(tag: "cryptobox")

extension EncryptionSessionsDirectory {
    
    /// Decrypts an event (if needed) and return a decrypted copy (or the original if no
    /// decryption was needed) and information about the decryption result.
    ///
    public func decryptAndAddClient(_ event: ZMUpdateEvent, in moc: NSManagedObjectContext) -> ZMUpdateEvent? {
        guard !event.wasDecrypted else { return event }
        guard event.type == .conversationOtrMessageAdd || event.type == .conversationOtrAssetAdd else {
            fatal("Can't decrypt event of type \(event.type) as it's not supposed to be encrypted")
        }
        
        // is it for the current client?
        let selfUser = ZMUser.selfUser(in: moc)
        guard let recipientIdentifier = event.recipientIdentifier, selfUser.selfClient()?.remoteIdentifier == recipientIdentifier else {
            return nil
        }

        // client
        guard let senderClient = self.createClientIfNeeded(from: event, in: moc) else { return nil }
        
        // decrypt
        let createdNewSession : Bool
        let decryptedEvent : ZMUpdateEvent
        
        func fail(error: CBoxResult? = nil) {
            if senderClient.isInserted {
                selfUser.selfClient()?.addNewClientToIgnored(senderClient)
            }
            self.appendFailedToDecryptMessage(after: error, for: event, sender: senderClient, in: moc)
        }
        
        do {
            guard let result = try self.decryptedUpdateEvent(for: event, sender: senderClient) else {
                fail()
                return nil
            }
            (createdNewSession, decryptedEvent) = result
        } catch let error as CBoxResult {
            fail(error: error)
            return nil
        } catch {
            fatalError("Unknown error in decrypting payload, \(error)")
        }

        // new client discovered?
        if createdNewSession {
            selfUser.selfClient()?.decrementNumberOfRemainingKeys()
            selfUser.selfClient()?.addNewClientToIgnored(senderClient)
            selfUser.selfClient()?.updateSecurityLevelAfterDiscovering(Set(arrayLiteral: senderClient))
        }
        
        return decryptedEvent
    }
}

extension EncryptionSessionsDirectory {
    
    /// Appends a system message for a failed decryption
    fileprivate func appendFailedToDecryptMessage(after error: CBoxResult?, for event: ZMUpdateEvent, sender: UserClient, in moc: NSManagedObjectContext) {
        zmLog.safePublic("Failed to decrypt message with error: \(error), client id <\(sender.safeRemoteIdentifier))>")
        zmLog.error("event debug: \(event.debugInformation)")
        if error == CBOX_OUTDATED_MESSAGE || error == CBOX_DUPLICATE_MESSAGE {
            return // do not notify the user if the error is just "duplicated"
        }
        
        var conversation : ZMConversation?
        if let conversationUUID = event.conversationUUID {
            conversation = ZMConversation.fetch(with: conversationUUID, domain: event.senderDomain, in: moc)
            conversation?.appendDecryptionFailedSystemMessage(at: event.timestamp, sender: sender.user!, client: sender, errorCode: Int(error?.rawValue ?? 0))
        }
        
        let userInfo: [String: Any] = [
            "cause": error?.rawValue as Any,
            "deviceClass" : sender.deviceClass ?? ""
        ]
        
        NotificationInContext(name: ZMConversation.failedToDecryptMessageNotificationName,
                              context: sender.managedObjectContext!.notificationContext,
                              object: conversation,
                              userInfo: userInfo).post()
    }
    
    /// Returns the decrypted version of an update event. This is generated by decrypting the encrypted version
    /// and creating a new event with the decrypted data in the expected payload keys
    fileprivate func decryptedUpdateEvent(for event: ZMUpdateEvent, sender: UserClient) throws -> (createdNewSession: Bool, event: ZMUpdateEvent)? {
        guard let result = try self.decryptedData(event, client: sender),
            let decryptedEvent = event.decryptedEvent(decryptedData: result.decryptedData)
        else { return nil }
        return (createdNewSession: result.createdNewSession, event: decryptedEvent)
    }
    
    /// Decrypted data from event
    private func decryptedData(_ event: ZMUpdateEvent, client: UserClient) throws -> (createdNewSession: Bool, decryptedData: Data)? {
        guard let encryptedData = try event.encryptedMessageData(),
            let sessionIdentifier = client.sessionIdentifier else { return nil }
        
        /// Check if it's the "bomb" message (gave encrypting on the sender)
        guard encryptedData != ZMFailedToCreateEncryptedMessagePayloadString.data(using: .utf8) else {
            zmLog.safePublic("Received 'failed to encrypt for your client' special payload (bomb) from \(sessionIdentifier). Current device might have invalid prekeys on the BE.")
            return nil
        }

        /// Decrypt and create session if needed
        if self.hasSession(for: sessionIdentifier) {
            return (createdNewSession: false, decryptedData: try self.decrypt(encryptedData, from: sessionIdentifier))
        } else {
            return (createdNewSession: true, decryptedData: try self.createClientSessionAndReturnPlaintext(for: sessionIdentifier, prekeyMessage: encryptedData))
        }
    }
    
    /// Create user and client if needed. The client will not be trusted
    fileprivate func createClientIfNeeded(from updateEvent: ZMUpdateEvent, in moc: NSManagedObjectContext) -> UserClient? {
        guard
            let senderUUID = updateEvent.senderUUID,
            let senderClientID = updateEvent.senderClientID
        else { return nil }

        let user = ZMUser.fetchOrCreate(with: senderUUID, domain: updateEvent.senderDomain, in: moc)
        let client = UserClient.fetchUserClient(withRemoteId: senderClientID, forUser: user, createIfNeeded: true)!
        
        client.discoveryDate = updateEvent.timestamp
        
        return client
    }
}

extension ZMUpdateEvent {

    /// Recipient identifier
    fileprivate var recipientIdentifier : String? {
        return self.eventData?["recipient"] as? String
    }
    
    /// Event payload
    private var eventData : [String: Any]? {
        guard let eventData = (self.payload as? [String:Any])?["data"] as? [String: Any] else {
            return nil
        }
        return eventData
    }
    
    /// Sender client identifier for asset and client messages
    fileprivate var senderClientRemoteIdentifier : String? {
        guard let eventData = self.eventData,
            let senderRemoteIdentifier = eventData["sender"] as? String
            else {
                return nil
        }
        return senderRemoteIdentifier
    }
    
    /// Message data payload
    fileprivate func encryptedMessageData() throws -> Data? {
        guard let key = payloadKey else { return nil }
        guard let string = eventData?[key] as? String, let data = Data(base64Encoded: string) else { return nil }

        // We need to check the size of the encrypted data payload for regular OTR and external messages
        let maxReceivingSize = Int(12_000 * 1.5)
        guard string.count <= maxReceivingSize, externalStringCount <= maxReceivingSize else { throw CBOX_DECODE_ERROR }
        return data
    }

    fileprivate var payloadKey: String? {
        switch type {
        case .conversationOtrMessageAdd: return "text"
        case .conversationOtrAssetAdd: return "key"
        default: return nil
        }
    }

    fileprivate var externalStringCount: Int {
        return (eventData?["data"] as? String)?.count ?? 0
    }
    
    /// Returns a decrypted version of self, injecting the decrypted data
    /// in its payload and wrapping the payload in a new updateEvent
    fileprivate func decryptedEvent(decryptedData: Data) -> ZMUpdateEvent? {
        guard var payload = self.payload as? [String: Any],
            var eventData = payload["data"] as? [String: Any] else {
                return nil
        }
        if self.type == .conversationOtrMessageAdd, let wrappedData = eventData["data"] as? String {
            payload["external"] = wrappedData
        }
        
        eventData[self.plaintextPayloadKey] = decryptedData.base64String()
        payload["data"] = eventData
        let decryptedEvent = ZMUpdateEvent.decryptedUpdateEvent(fromEventStreamPayload: payload as NSDictionary, uuid: self.uuid, transient: false, source: self.source)
        if !self.debugInformation.isEmpty {
            decryptedEvent?.appendDebugInformation(debugInformation)
        }
        return decryptedEvent
    }
    
    /// Payload dictionary key that holds the plaintext (protobuf) data
    fileprivate var plaintextPayloadKey : String {
        switch self.type {
        case .conversationOtrMessageAdd:
            return "text"
        case .conversationOtrAssetAdd:
            return "info"
        default:
            fatal("Decrypting wrong type of event")
        }
    }
}


