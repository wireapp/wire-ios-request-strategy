//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

/// An object that is able to send messages to the backend.
///
/// Each message belongs to a conversation that uses a specific message protocol.
/// This sync ensures that each message is sent to the backend using the appropriate
/// protocol.

class MessageSync<Message: ProteusMessage>: NSObject, ZMContextChangeTrackerSource, ZMRequestGenerator {

    typealias OnRequestScheduledHandler = (_ message: Message, _ request: ZMTransportRequest) -> Void

    // MARK: - Properties

    private let proteusMessageSync: ProteusMessageSync<Message>

    // MARK: - Life cycle

    init(context: NSManagedObjectContext, appStatus: ApplicationStatus) {
        proteusMessageSync = ProteusMessageSync(
            context: context,
            applicationStatus: appStatus
        )
    }

    // MARK: - Change tracker

    var contextChangeTrackers: [ZMContextChangeTracker] {
        return proteusMessageSync.contextChangeTrackers
    }

    // MARK: - Request generator

    func nextRequest(for apiVersion: APIVersion) -> ZMTransportRequest? {
        return proteusMessageSync.nextRequest(for: apiVersion)
    }

    // MARK: - Methods

    func onRequestScheduled(_ handler: @escaping OnRequestScheduledHandler) {
        proteusMessageSync.onRequestScheduled(handler)
    }

    func sync(_ message: Message, completion: @escaping EntitySyncHandler) {
        proteusMessageSync.sync(message, completion: completion)
    }

    func expireMessages(withDependency dependency: NSObject) {
        proteusMessageSync.expireMessages(withDependency: dependency)
    }

}
