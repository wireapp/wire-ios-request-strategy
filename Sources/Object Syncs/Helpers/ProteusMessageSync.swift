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

protocol ProteusMessage: OTREntity, EncryptedPayloadGenerator, Hashable {}

extension ZMClientMessage: ProteusMessage {}

/**
 ProteusMessageSync synchronizes messages with the backend using the using the Proteus encryption protocol.

 This only works with objects which implements the `ProteusMessage` protocol.
 */
class ProteusMessageSync<Message: ProteusMessage>: NSObject, EntityTranscoder, ZMContextChangeTrackerSource, ZMRequestGenerator {

    typealias Entity = Message
    typealias OnRequestScheduledHandler = (_ message: Message, _ request: ZMTransportRequest) -> Void

    var dependencySync: DependencyEntitySync<ProteusMessageSync>!
    let requestFactory = ClientMessageRequestFactory()
    let applicationStatus: ApplicationStatus
    let context: NSManagedObjectContext
    var onRequestScheduledHandler: OnRequestScheduledHandler?
    var isFederationEndpointAvailable = true

    init(context: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        self.context = context
        self.applicationStatus = applicationStatus

        super.init()

        self.dependencySync = DependencyEntitySync<ProteusMessageSync>(transcoder: self, context: context)
    }

    var contextChangeTrackers: [ZMContextChangeTracker] {
        return [dependencySync]
    }

    func nextRequest() -> ZMTransportRequest? {
        return dependencySync.nextRequest()
    }

    func onRequestScheduled(_ handler: @escaping OnRequestScheduledHandler) {
        onRequestScheduledHandler = handler
    }

    func sync(_ message: Message, completion: @escaping EntitySyncHandler) {
        dependencySync.synchronize(entity: message, completion: completion)
    }

    func request(forEntity entity: Message) -> ZMTransportRequest? {
        guard
            let request = requestFactory.upstreamRequestForMessage(entity,
                                                                   in: entity.conversation!,
                                                                   useFederationEndpoint: isFederationEndpointAvailable)
        else {
            return nil
        }

        if let expirationDate = entity.expirationDate {
            request.expire(at: expirationDate)
        }

        onRequestScheduledHandler?(entity, request)

        return request
    }

    func request(forEntity entity: Message, didCompleteWithResponse response: ZMTransportResponse) {
        if isFederationEndpointAvailable {
            let payload = Payload.MessageSendingStatus(response, decoder: .defaultDecoder)
            _ = payload?.updateClientsChanges(for: entity)
        } else {
            _ = entity.parseUploadResponse(response, clientRegistrationDelegate: applicationStatus.clientRegistrationDelegate)
        }
        purgeEncryptedPayloadCache()
    }

    func shouldTryToResend(entity: Message, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        switch response.httpStatus {
        case 404:
            let payload = Payload.ResponseFailure(response, decoder: .defaultDecoder)
            if payload?.label == .noEndpoint {
                isFederationEndpointAvailable = false
                return true
            }
            return false
        case 412:
            if isFederationEndpointAvailable {
                let payload = Payload.MessageSendingStatus(response, decoder: .defaultDecoder)
                return payload?.updateClientsChanges(for: entity) ?? false
            } else {
                return entity.parseUploadResponse(response, clientRegistrationDelegate: applicationStatus.clientRegistrationDelegate).contains(.missing)
            }

        default:
            let payload = Payload.ResponseFailure(response, decoder: .defaultDecoder)
            if payload?.label == .unknownClient {
                applicationStatus.clientRegistrationDelegate.didDetectCurrentClientDeletion()
            }

            if case .permanentError = response.result {
                return false
            } else {
                return true
            }
        }
    }

    fileprivate func purgeEncryptedPayloadCache() {
        guard let selfClient = ZMUser.selfUser(in: context).selfClient() else {
            return
        }
        selfClient.keysStore.encryptionContext.perform { (session) in
            session.purgeEncryptedPayloadCache()
        }
    }

}
