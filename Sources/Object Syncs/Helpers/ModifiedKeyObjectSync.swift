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

protocol ModifiedKeyObjectSyncTranscoder: class {

    associatedtype Object: ZMManagedObject

    /// Called when the `ModifiedKeyObjectSync` request an object to be synchronized
    /// due to a key being modified.
    ///
    /// - Parameters:
    ///   - keys: key which has been modified
    ///   - object: object which has been modified
    ///   - completion: Completion handler which should be called when the modified
    ///                 object has been synchronzied with the backend.
    func synchronize(key: String, for object: Object, completion: @escaping () -> Void)
}

/**
 ModifiedKeyObjectSync synchronizes an object when a given property has been modified on
 the object.

 This only works for core data entities which inherit from `ZMManagedObject`.
 */
class ModifiedKeyObjectSync<Transcoder: ModifiedKeyObjectSyncTranscoder>: NSObject, ZMContextChangeTracker {

    let entity: NSEntityDescription
    let trackedKey: String
    let fetchPredicate: NSPredicate?
    var pending: Set<Transcoder.Object> = Set()

    weak var transcoder: Transcoder?

    /// - Parameters:
    ///   - entity: Entity which should be synchronized
    ///   - trackedKey: Key / property which should synchchronized when modified.
    ///   - fetchPredicate: Predicate used when fetching the initial entities when strategy is created. If omitted
    ///                     all entities will be fetched an evaluated.
    init(entity: NSEntityDescription,
         trackedKey: String,
         fetchPredicate: NSPredicate? = nil) {
        self.entity = entity
        self.trackedKey = trackedKey
        self.fetchPredicate = fetchPredicate
    }

    func objectsDidChange(_ object: Set<NSManagedObject>) {
        addTrackedObjects(object)
    }

    func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let moClass: AnyClass? = NSClassFromString(entity.managedObjectClassName)

        if let fetchPredicate = fetchPredicate {
            return moClass?.sortedFetchRequest(with: fetchPredicate)
        } else {
            return moClass?.sortedFetchRequest()
        }
    }

    func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        let trackedObjects = objects.compactMap({ $0 as? Transcoder.Object})

        for modifiedObject in trackedObjects {
            guard let modifiedKeys = modifiedObject.modifiedKeys,
                  modifiedKeys.contains(trackedKey),
                  !pending.contains(modifiedObject)
            else { continue }

            pending.insert(modifiedObject)
            transcoder?.synchronize(key: trackedKey, for: modifiedObject, completion: {
                modifiedObject.resetLocallyModifiedKeys(modifiedKeys)
                self.pending.remove(modifiedObject)
            })
        }
    }

}
