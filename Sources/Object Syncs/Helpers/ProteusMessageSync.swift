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

public protocol ProteusMessage: OTREntity, EncryptedPayloadGenerator, Hashable {}

extension ZMClientMessage: ProteusMessage {}
extension ZMAssetClientMessage: ProteusMessage {}

class ProteusDependencyFilter<Message: ProteusMessage>: ObjectFilter {
    typealias Object = Message

    func isIncluded(_ object: Message) -> Bool {
        object.dependentObjectNeedingUpdateBeforeProcessing == nil
    }
}

class ProteusMessageTrancoder<Message: ProteusMessage>: NSObject, ObjectTranscoder, FederationAware {
    typealias Object = Message

    var shouldRetryOnExpiration: Bool = false
    var useFederationEndpoint: Bool = false
    let requestFactory = ClientMessageRequestFactory()
    let applicationStatus: ApplicationStatus
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        self.context = context
        self.applicationStatus = applicationStatus
    }

    func requestFor(_ entity: Message) -> ZMTransportRequest? {
        guard
            let conversation = entity.conversation,
            let request = requestFactory.upstreamRequestForMessage(entity,
                                                                   in: conversation,
                                                                   useFederationEndpoint: useFederationEndpoint)
        else {
            return nil
        }

        if let expirationDate = entity.expirationDate {
            request.expire(at: expirationDate)
        }

        return request
    }

    func handleResponse(response: ZMTransportResponse, for entity: Message) {
        entity.delivered(with: response)

        if useFederationEndpoint {
            let payload = Payload.MessageSendingStatus(response, decoder: .defaultDecoder)
            _ = payload?.updateClientsChanges(for: entity)
        } else {
            _ = entity.parseUploadResponse(response, clientRegistrationDelegate: applicationStatus.clientRegistrationDelegate)
        }
        purgeEncryptedPayloadCache()
    }

    fileprivate func purgeEncryptedPayloadCache() {
        guard let selfClient = ZMUser.selfUser(in: context).selfClient() else {
            return
        }
        selfClient.keysStore.encryptionContext.perform { (session) in
            session.purgeEncryptedPayloadCache()
        }
    }

    public func shouldTryToResend(_ object: Message, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        switch response.httpStatus {
        case 412:
            if useFederationEndpoint {
                let payload = Payload.MessageSendingStatus(response, decoder: .defaultDecoder)
                return payload?.updateClientsChanges(for: object) ?? false
            } else {
                return object.parseUploadResponse(response, clientRegistrationDelegate: applicationStatus.clientRegistrationDelegate).contains(.missing)
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
}

class ProteusMessageSync<Message: ProteusMessage>: ObjectSync<Message, ProteusMessageTrancoder<Message>>, FederationAware {

    let proteusMessageTrancoder: ProteusMessageTrancoder<Message>

    var useFederationEndpoint: Bool {
        get {
            proteusMessageTrancoder.useFederationEndpoint
        }
        set {
            proteusMessageTrancoder.useFederationEndpoint = newValue
        }
    }

    init(context: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        proteusMessageTrancoder = ProteusMessageTrancoder(context: context, applicationStatus: applicationStatus)

        super.init(proteusMessageTrancoder, context: context)

        addFilter(filter: ProteusDependencyFilter<Message>())
    }
}
