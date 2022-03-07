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
import WireTransport
import WireImages
import WireDataModel
import SwiftProtobuf

private let zmLog = ZMSLog(tag: "Network")

public final class ClientMessageRequestFactory: NSObject {

    let protobufContentType = "application/x-protobuf"
    let octetStreamContentType = "application/octet-stream"

    public func upstreamRequestForFetchingClients(conversationId: UUID, selfClient: UserClient) -> ZMTransportRequest? {
        let path = "/" + ["conversations",
                          conversationId.transportString(),
                          "otr",
                          "messages"].joined(separator: "/")

        let newOtrMessage = Proteus_NewOtrMessage(
            withSender: selfClient,
            nativePush: false,
            recipients: []
        )

        return upstreamRequestForFetchingClients(
            path: path.pathWithMissingClientStrategy(strategy: .doNotIgnoreAnyMissingClient),
            message: newOtrMessage
        )
    }

    public func upstreamRequestForFetchingClients(conversationId: UUID, domain: String, selfClient: UserClient) -> ZMTransportRequest? {
        let path = "/" + ["conversations",
                          domain,
                          conversationId.transportString(),
                          "proteus",
                          "messages"].joined(separator: "/")

        let newOtrMessage = Proteus_QualifiedNewOtrMessage(
            withSender: selfClient,
            nativePush: false,
            recipients: [],
            missingClientsStrategy: .doNotIgnoreAnyMissingClient
        )

        return upstreamRequestForFetchingClients(path: path, message: newOtrMessage)
    }

    private func upstreamRequestForFetchingClients(path: String, message: SwiftProtobuf.Message) -> ZMTransportRequest? {
        guard let data = try? message.serializedData() else {
            zmLog.debug("failed to serialize message")
            return nil
        }

        return ZMTransportRequest(
            path: path,
            method: .methodPOST,
            binaryData: data,
            type: protobufContentType,
            contentDisposition: nil,
            apiVersion: APIVersion.v0.rawValue
        )
    }

    public func upstreamRequestForMessage(_ message: EncryptedPayloadGenerator, in conversation: ZMConversation, useFederationEndpoint: Bool, apiVersion: APIVersion) -> ZMTransportRequest? {
        if useFederationEndpoint {
            return upstreamRequestForQualifiedEncryptedMessage(message, in: conversation, apiVersion: apiVersion)
        } else {
            return upstreamRequestForEncryptedMessage(message, in: conversation, apiVersion: apiVersion)
        }
    }

    fileprivate func upstreamRequestForEncryptedMessage(_ message: EncryptedPayloadGenerator, in conversation: ZMConversation, apiVersion: APIVersion) -> ZMTransportRequest? {
        guard
            let conversationID = conversation.remoteIdentifier?.transportString()
        else {
            return nil
        }

        let originalPath = "/" + ["conversations", conversationID, "otr", "messages"].joined(separator: "/")
        guard let encryptedPayload = message.encryptForTransport() else { return nil }
        let path = originalPath.pathWithMissingClientStrategy(strategy: encryptedPayload.strategy)
        let request = ZMTransportRequest(path: path, method: .methodPOST, binaryData: encryptedPayload.data, type: protobufContentType, contentDisposition: nil, apiVersion: apiVersion.rawValue)
        request.addContentDebugInformation(message.debugInfo)
        return request
    }

    fileprivate func upstreamRequestForQualifiedEncryptedMessage(_ message: EncryptedPayloadGenerator, in conversation: ZMConversation, apiVersion: APIVersion) -> ZMTransportRequest? {
        guard
            let context = conversation.managedObjectContext,
            let conversationID = conversation.remoteIdentifier?.transportString(),
            let domain = conversation.domain ?? ZMUser.selfUser(in: context).domain
        else {
            return nil
        }

        let path = "/" + ["conversations", domain, conversationID, "proteus", "messages"].joined(separator: "/")
        guard let encryptedPayload = message.encryptForTransportQualified() else { return nil }
        let request = ZMTransportRequest(path: path, method: .methodPOST, binaryData: encryptedPayload.data, type: protobufContentType, contentDisposition: nil, apiVersion: apiVersion.rawValue)
        request.addContentDebugInformation(message.debugInfo)
        return request
    }

    public func requestToGetAsset(_ assetId: String, inConversation conversationId: UUID, apiVersion: APIVersion) -> ZMTransportRequest {
        let path = "/" + ["conversations", conversationId.transportString(), "otr", "assets", assetId].joined(separator: "/")
        let request = ZMTransportRequest.imageGet(fromPath: path, apiVersion: apiVersion.rawValue)
        request.forceToBackgroundSession()
        return request
    }

}

// MARK: - Downloading
extension ClientMessageRequestFactory {
    func downstreamRequestForEcryptedOriginalFileMessage(_ message: ZMAssetClientMessage, apiVersion: APIVersion) -> ZMTransportRequest? {
        guard let conversation = message.conversation, let identifier = conversation.remoteIdentifier else { return nil }
        let path = "/conversations/\(identifier.transportString())/otr/assets/\(message.assetId!.transportString())"

        let request = ZMTransportRequest(getFromPath: path, apiVersion: apiVersion.rawValue)
        request.addContentDebugInformation("Downloading file (Asset)\n\(String(describing: message.dataSetDebugInformation))")
        request.forceToBackgroundSession()
        return request
    }
}

extension String {

    func pathWithMissingClientStrategy(strategy: MissingClientsStrategy) -> String {
        switch strategy {
        case .doNotIgnoreAnyMissingClient,
             .ignoreAllMissingClientsNotFromUsers:
            return self
        case .ignoreAllMissingClients:
            return self + "?ignore_missing=true"
        }
    }
}
