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

class MLSMessageSync<Message: MLSMessage>: NSObject, ZMContextChangeTrackerSource, ZMRequestGenerator {

    // MARK: - Properties

    let dependencySync: DependencyEntitySync<Transcoder<Message>>

    // MARK: - Life cycle

    init(context: NSManagedObjectContext) {
        dependencySync = DependencyEntitySync(
            transcoder: Transcoder(),
            context: context
        )

        super.init()
    }

    // MARK: - Change tracker

    var contextChangeTrackers: [ZMContextChangeTracker] {
        return [dependencySync]
    }

    // MARK: - Request generator

    func nextRequest(for apiVersion: APIVersion) -> ZMTransportRequest? {
        return dependencySync.nextRequest(for: apiVersion)
    }

    // MARK: - Methods

    func sync(_ message: Message, completion: @escaping EntitySyncHandler) {
        dependencySync.synchronize(entity: message, completion: completion)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }

    func expireMessages(withDependency dependency: NSObject) {
        dependencySync.expireEntities(withDependency: dependency)
    }

}


