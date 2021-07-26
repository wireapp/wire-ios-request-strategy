//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

private let zmLog = ZMSLog(tag: "feature configurations")

public extension Notification.Name {
    static let fetchAllConfigsTriggerNotification = Notification.Name("fetchAlLConfigsTriggerNotification")

    /// Notification to be fired when the feature configuration is changed.
    /// When firing this notification the event has to be included as object in the notification.
    static let featureConfigDidChangeNotification = Notification.Name("featureConfigDidChangeNotification")
}

@objcMembers
public final class FeatureConfigRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    // MARK: - Properties

    private var needsToFetchAllConfigs = false {
        didSet {
            guard needsToFetchAllConfigs else { return }
            fetchAllConfigsSync.readyForNextRequestIfNotBusy()
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }

    private var fetchSingleConfigSync: ZMDownstreamObjectSync!
    private var fetchAllConfigsSync: ZMSingleRequestSync!

    private var featureController: FeatureController!

    private var team: Team? {
        return ZMUser.selfUser(in: managedObjectContext).team
    }

    private var observerToken: Any?

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [fetchSingleConfigSync]
    }

    // MARK: - Init

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {

        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        configuration = [
            .allowsRequestsWhileOnline,
            .allowsRequestsDuringQuickSync,
            .allowsRequestsWhileWaitingForWebsocket,
            .allowsRequestsWhileInBackground
        ]
        
        featureController = FeatureController(managedObjectContext: managedObjectContext)

        fetchSingleConfigSync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: Feature.entityName(),
            predicateForObjectsToDownload: Feature.predicateForNeedingToBeUpdatedFromBackend(),
            managedObjectContext: managedObjectContext
        )

        fetchAllConfigsSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: managedObjectContext)

        observerToken = NotificationCenter.default.addObserver(
            forName: .fetchAllConfigsTriggerNotification,
            object: nil,
            queue: nil,
            using: { [weak self] _ in self?.needsToFetchAllConfigs = true }
        )
    }

    // MARK: - Overrides

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return fetchAllConfigsSync.nextRequest() ?? fetchSingleConfigSync.nextRequest()
    }

}

// MARK: - Single config transcoder

extension FeatureConfigRequestStrategy: ZMDownstreamTranscoder {

    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let feature = object as? Feature else { fatal("Wrong sync or object for: \(object.safeForLoggingDescription)") }
        return requestToFetchConfig(for: feature)
    }

    private func requestToFetchConfig(for feature: Feature) -> ZMTransportRequest? {
        guard let teamId = feature.team?.remoteIdentifier?.transportString() else { return nil }
        return ZMTransportRequest(getFromPath: "/teams/\(teamId)/features/\(feature.transportName)")
    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard
            (downstreamSync as? ZMDownstreamObjectSync) == self.fetchSingleConfigSync,
            let feature = object as? Feature,
            response.result == .success,
            let responseData = response.rawData
        else {
            return
        }

        do {
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()

            switch feature.name {
            case .appLock:
                let config = try decoder.decode(ConfigResponse<Feature.AppLock>.self, from: responseData)
                feature.status = config.status
                feature.config = try encoder.encode(config.config)
            case .fileSharing:
                let config = try decoder.decode(ConfigResponse<Feature.FileSharing>.self, from: responseData)
                feature.status = config.status
            }

            feature.needsToBeUpdatedFromBackend = false

        } catch {
            zmLog.error("Failed to process feature config response: \(error.localizedDescription)")
        }
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // No op
    }

}

// MARK: - All configs transcoder

extension FeatureConfigRequestStrategy: ZMSingleRequestTranscoder {

    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard sync == fetchAllConfigsSync else { return nil }
        return requestToFetchAllFeatureConfigs()
    }

    private func requestToFetchAllFeatureConfigs() -> ZMTransportRequest? {
        guard let teamId = team?.remoteIdentifier?.transportString() else { return nil }
        return ZMTransportRequest(getFromPath: "/teams/\(teamId)/features")
    }

    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        guard
            sync == fetchAllConfigsSync,
            let team = team,
            response.result == .success,
            let responseData = response.rawData
        else {
            return
        }

        do {
            let allConfigs = try JSONDecoder().decode(AllConfigsResponse.self, from: responseData)
            featureController.store(feature: allConfigs.applock.asFeature, in: team)
        } catch {
            zmLog.error("Failed to decode feature config response: \(error)")
        }
    }
}

//MARK: - ZMEventConsumer

extension FeatureConfigRequestStrategy: ZMEventConsumer {

    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        events.forEach(process)
    }

    private func process(_ event: ZMUpdateEvent) {
        switch event.type {
        case .featureConfigUpdate:
            updateFeature(with: event)

            NotificationCenter.default.post(name: .featureConfigDidChangeNotification, object: event)
        default: break
        }
    }

    private func updateFeature(with event: ZMUpdateEvent) {
        guard let payloadData = event.payload["data"] as? [String: Any],
              let statusString = payloadData["status"] as? String,
              let status = Feature.Status(rawValue: statusString),
              let nameString = event.payload["name"] as? String,
              let featureName = Feature.Name(rawValue: nameString) else {
            return
        }

        if let existing = Feature.fetch(name: featureName, context: managedObjectContext) {
            let config = payloadData["config"] as? [String: String]
            let configData = try? JSONEncoder().encode(config)

            existing.status = status
            existing.config = configData

        } else {
            if let team = team {
                Feature.createDefaultInstanceIfNeeded(name: featureName, team: team, context: managedObjectContext)
            }
        }
    }
}

// MARK: - Response models

private extension FeatureConfigRequestStrategy {

    struct ConfigResponse<T: FeatureLike>: Decodable {

        let status: Feature.Status
        let config: T.Config?

        var asFeature: T {
            return T(status: status, config: config)
        }

    }

    struct AllConfigsResponse: Decodable {

        var applock: ConfigResponse<Feature.AppLock>

    }

}

// MARK: - Helpers

private extension Feature {

    /// The name to use in the endpoint.

    var transportName: String {
        switch name {
        case .appLock:
            return "appLock"
        case .fileSharing:
            return "fileSharing"
        }
    }

}

public extension Feature {

    static func triggerBackendRefreshForAllConfigs() {
        NotificationCenter.default.post(
            name: .fetchAllConfigsTriggerNotification,
            object: nil
        )
    }

}
