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
import WireDataModel

let VoIPIdentifierSuffix = "-voip"
let TokenKey = "token"
let PushTokenPath = "/push/tokens"

public class PushTokenStrategy: AbstractRequestStrategy, ZMUpstreamTranscoder, ZMContextChangeTrackerSource, ZMEventConsumer, ZMRequestGeneratorSource {

    @objc public static let registerCurrentPushTokenNotificationName = Notification.Name(rawValue: "ZMUserSessionResetPushTokensNotification")

    enum Keys {
        static let UserClientPushTokenKey = "pushToken"
        static let UserClientLegacyPushTokenKey = "legacyPushToken"
        static let RequestTypeKey = "requestType"
    }

    enum RequestType: String {
        case getToken
    }

    private let registerPushTokenActionHandler: RegisterPushTokenActionHandler
    private let actionSync: EntityActionSync

    public var requestGenerators: [ZMRequestGenerator] {
        return [
            actionSync,
            pushKitTokenSync
        ]
    }

    fileprivate var pushKitTokenSync: ZMUpstreamModifiedObjectSync!
    fileprivate var notificationsTracker: NotificationsTracker?

    private func modifiedPredicate() -> NSPredicate {
        guard let basePredicate = UserClient.predicateForObjectsThatNeedToBeUpdatedUpstream() else {
            fatal("basePredicate is nil!")
        }

        let nonNilPushToken = NSPredicate(format: "%K != nil", Keys.UserClientPushTokenKey)

        return NSCompoundPredicate(andPredicateWithSubpredicates: [basePredicate, nonNilPushToken])
    }

    @objc
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                applicationStatus: ApplicationStatus,
                analytics: AnalyticsType?) {

        registerPushTokenActionHandler = RegisterPushTokenActionHandler(context: managedObjectContext)

        actionSync = EntityActionSync(actionHandlers: [
            registerPushTokenActionHandler
        ])

        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        pushKitTokenSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: UserClient.entityName(),
            update: modifiedPredicate(),
            filter: nil,
            keysToSync: [Keys.UserClientPushTokenKey, Keys.UserClientLegacyPushTokenKey],
            managedObjectContext: managedObjectContext
        )

        if let analytics = analytics {
            self.notificationsTracker = NotificationsTracker(analytics: analytics)
        }
    }

    public override func nextRequestIfAllowed(for apiVersion: APIVersion) -> ZMTransportRequest? {
        return requestGenerators.nextRequest(for: apiVersion)
    }

// MARK: - ZMUpstreamTranscoder

    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>, apiVersion: APIVersion) -> ZMUpstreamRequest? {
        guard let client = managedObject as? UserClient else { return nil }
        guard client.isSelfClient() else { return nil }
        guard let clientIdentifier = client.remoteIdentifier else { return nil }

        let request: ZMTransportRequest
        let requestType: RequestType

        if let pushToken = client.pushToken, pushToken.isMarkedForDownload {
            request = ZMTransportRequest(path: "\(PushTokenPath)", method: .methodGET, payload: nil, apiVersion: apiVersion.rawValue)
            requestType = .getToken
        } else {
            return nil
        }

        return ZMUpstreamRequest(keys: keys,
                                 transportRequest: request,
                                 userInfo: [Keys.RequestTypeKey: requestType.rawValue])
    }

    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?, apiVersion: APIVersion) -> ZMUpstreamRequest? {
        return nil
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable: Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let client = managedObject as? UserClient else { return false }
        guard client.isSelfClient() else { return false }
        guard let userInfo = requestUserInfo as? [String: String] else { return false }
        guard let requestTypeValue = userInfo[Keys.RequestTypeKey], let requestType = RequestType(rawValue: requestTypeValue) else { return false }

        switch requestType {
        case .getToken:
            guard let pushToken = client.pushToken,
                  let responseData = response.rawData else { return false }
            guard let payload = try? JSONDecoder().decode([String: [PushTokenPayload]].self, from: responseData) else { return false }
            guard let tokens = payload["tokens"] else { return false }

            if tokens.first(where: { $0.client == client.remoteIdentifier && $0.token == pushToken.deviceTokenString }) != nil // We found one token that matches what we have locally
            {
                // Clear the flags and we are done
                client.pushToken = pushToken.resetFlags()
                return false
            } else {
                // There is something wrong, local token doesn't match the remotely registered

                // We should remove the local token
                client.pushToken = nil

                notificationsTracker?.registerTokenMismatch()

                // Make sure UI tries to get re-register a new one
                NotificationInContext(name: Self.registerCurrentPushTokenNotificationName,
                                      context: managedObjectContext.notificationContext,
                                      object: nil,
                                      userInfo: nil).post()

                return false
            }
        }
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }

    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }

    // MARK: - ZMContextChangeTrackerSource

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.pushKitTokenSync]
    }

    // MARK: - ZMEventConsumer

    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        guard liveEvents else { return }

        events.forEach { process(updateEvent: $0) }
    }

    func process(updateEvent event: ZMUpdateEvent) {
        if event.type != .userPushRemove {
            return
        }
        // expected payload:
        // { "type: "user.push-remove",
        //   "token":
        //    { "transport": "APNS",
        //            "app": "name of the app",
        //          "token": "the token you get from apple"
        //    }
        // }
        // we ignore the payload and remove the locally saved copy
        let client = ZMUser.selfUser(in: self.managedObjectContext).selfClient()
        client?.pushToken = nil
    }
}

private struct PushTokenPayload: Codable {

    init(pushToken: PushToken, clientIdentifier: String) {
        token = pushToken.deviceTokenString
        app = pushToken.appIdentifier
        transport = pushToken.transportType
        client = clientIdentifier
    }

    let token: String
    let app: String
    let transport: String
    let client: String
}
