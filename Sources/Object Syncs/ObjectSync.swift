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

/// An object source observes when objects needs to be synchronized
///
protocol ObjectSource {
    associatedtype Object

    typealias OnPublish = (_ object: Object) -> Void
    typealias OnUnpublish = (_ object: Object) -> Void

    var onPublish: OnPublish? { get set }
    var onUnpublish: OnUnpublish? { get set }
}

extension ObjectSource {

    mutating func onPublish(_ onPublish: @escaping OnPublish) {
        self.onPublish = onPublish
    }

    mutating func onUnpublish(_ onUnpublish: @escaping OnUnpublish) {
        self.onUnpublish = onUnpublish
    }

    /// Call when the objects needs to be synchronized
    func publish(_ object: Object) {
        onPublish?(object)
    }

    /// Call when the objects no longer needs to be synchronized
    func unpublish(_ object: Object) {
        onUnpublish?(object)
    }

}

/// An object filter temporarily filters objects have been selected to be be synchronized
///
protocol ObjectFilter {
    associatedtype Object

    func isIncluded(_ object: Object) -> Bool
}

/// An object transcoder turns an object into a HTTP request and handles the response
///
protocol ObjectTranscoder {
    associatedtype Object: Hashable

    /// How many objects the transcoder can synchronize in one request.
    ///
    /// The default is 1.
    var fetchLimit: Int { get }
    var supportBatchRequests: Bool { get }

    /// Returns a request for synchronzing a single object
    func requestFor(_ object: Object) -> ZMTransportRequest?

    /// /// Returns a request for synchronzing a set of objects
    func requestFor(_ objects: Set<Object>) -> ZMTransportRequest?

    /// Handle the response for synchronzing a single object
    func handleResponse(response: ZMTransportResponse, for object: Object)

    /// Handle the response for synchronzing a set of objects objects
    func handleResponse(response: ZMTransportResponse, for objects: Set<Object>)
}

extension ObjectTranscoder {

    var fetchLimit: Int {
        1
    }

    var supportBatchRequests: Bool {
        return fetchLimit > 1
    }

    func requestFor(_ objects: Set<Object>) -> ZMTransportRequest? {
        requestFor(objects.first!)
    }

    func handleResponse(response: ZMTransportResponse, for objects: Set<Object>) {
        handleResponse(response: response, for: objects.first!)
    }

}

struct AnyObjectFilter<P> {
    typealias Object = P

    let isIncluded: (P) -> Bool
}

/// Filters objects using a boolean keypath
struct KeyPathFilter<Object: ZMManagedObject>: ObjectFilter {
    typealias Object = Object

    let keyPath: WritableKeyPath<Object, Bool>

    init(keyPath: WritableKeyPath<Object, Bool>) {
        self.keyPath = keyPath
    }

    func isIncluded(_ object: Object) -> Bool {
        return object[keyPath: keyPath]
    }

}

/// Filters objects using a predicate
struct PredicateFilter<Object>: ObjectFilter {
    typealias Object = Object

    let predicate: NSPredicate

    init(predicate: NSPredicate) {
        self.predicate = predicate
    }

    func isIncluded(_ object: Object) -> Bool {
        return predicate.evaluate(with: object)
    }
}

/// Observes a boolean keypath on an entity and schedules them to be synchronize when `True`.
class KeyPathSource<T: ZMManagedObject>: NSObject, ObjectSource, ZMContextChangeTracker {
    typealias Object = T

    var onPublish: OnPublish?
    var onUnpublish: OnUnpublish?
    let keyPath: WritableKeyPath<T, Bool>

    init(keyPath: WritableKeyPath<T, Bool>) {
        self.keyPath = keyPath
    }

    func objectsDidChange(_ objects: Set<NSManagedObject>) {
        let objects = objects.compactMap({ $0 as? T })

        objects.forEach { object in
            if object[keyPath: keyPath] {
                publish(object)
            } else {
                unpublish(object)
            }
        }
    }

    func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let keypathExpression =  NSExpression(forKeyPath: keyPath)
        let valueExpression = NSExpression(forConstantValue: true)
        let predicate = NSComparisonPredicate(leftExpression: keypathExpression,
                              rightExpression: valueExpression,
                              modifier: .direct,
                              type: .equalTo)

        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: T.entityName())
        fetchRequest.predicate = predicate

        return fetchRequest
    }

    func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        objectsDidChange(objects)
    }
}

/// Observes an entity and schedules them to be synchronize when the predicate evaluates to `True`.
class PredicateSource<Object: ZMManagedObject>: NSObject, ObjectSource, ZMContextChangeTracker {
    typealias Object = Object

    let predicate: NSPredicate
    var onPublish: OnPublish?
    var onUnpublish: OnPublish?

    init(_ predicate: NSPredicate) {
        self.predicate = predicate
    }

    func objectsDidChange(_ objects: Set<NSManagedObject>) {
        let objects = objects.compactMap({ $0 as? Object })

        objects.filter({ predicate.evaluate(with: $0) }).forEach { object in
            publish(object)
        }
    }

    func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let fetchRequest = Object.fetchRequest()
        fetchRequest.predicate = predicate
        return fetchRequest
    }

    func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        objectsDidChange(objects)
    }

}

protocol ObjectSyncDelegate: AnyObject {

    /// Called when all scheduled objects have been synchronized
    func didFinishSyncingAllObjects()

    /// Called when any of scheduled objects failed to been synchronized
    func didFailToSyncAllObjects()

}

/// Synchronizes objects using a configurable sources, filters and transcoder.
///
class ObjectSync<Object, Trans: ObjectTranscoder>: NSObject, ZMRequestGenerator, ZMContextChangeTrackerSource where Trans.Object == Object {

    var pending: Set<Object> = Set()
    var downloading: Set<Object> = Set()
    var filters: [AnyObjectFilter<Object>] = []
    var sources: [Any] = []
    var transcoder: Trans
    var context: NSManagedObjectContext
    weak var delegate: ObjectSyncDelegate?

    var contextChangeTrackers: [ZMContextChangeTracker] {
        return sources.compactMap({ $0 as? ZMContextChangeTracker })
    }

    /// `True` is any objects are still waiting or is currently being synchronized.
    public var isSyncing: Bool {
        return !pending.isEmpty || !downloading.isEmpty
    }

    init(_ transcoder: Trans, context: NSManagedObjectContext) {
        self.transcoder = transcoder
        self.context = context
    }

    /// Add an object source
    ///
    /// - parameter source: source which will track when objects needs to be synchronized
    ///
    func addSource<S: ObjectSource>(_ source: S) where S.Object == Object {
        var source = source
        source.onPublish { [weak self] object in
            self?.synchronize(object)
        }
        source.onUnpublish { [weak self] object in
            self?.cancel(object)
        }

        sources.append(source)
    }

    /// Add a filter
    ///
    /// - parameter filter: filter which will prevent objects from being synchronized.
    func addFilter<F: ObjectFilter>(filter: F) where F.Object == Object {
        filters.append(AnyObjectFilter<Object>(isIncluded: filter.isIncluded))
    }

    /// Synchronize an object
    ///
    /// - parameter object: Object to synchronize.
    func synchronize(_ object: Object) {
        synchronize([object])
    }

    /// Synchronize a set of objects
    ///
    /// - parameter objects: Objects to synchronize.
    ///
    func synchronize<S: Sequence>(_ objects: S) where S.Element == Object {
        let newObjects = Set(objects)

        if newObjects.isEmpty && downloading.isEmpty && pending.isEmpty {
            delegate?.didFinishSyncingAllObjects()
        } else {
            pending.formUnion(Set(newObjects).subtracting(downloading))
        }
    }

    /// Cancel the synchronization of an object
    ///
    /// - parameter object: Object which will be canceled if it's not already in progress.
    ///
    func cancel(_ object: Object) {
        cancel([object])
    }

    /// Cancel the synchronization of a set of objects
    ///
    /// - parameter object: Objects which will be canceled if they are not already in progress.
    ///
    func cancel<S: Sequence>(_ objects: S) where S.Element == Object {
        pending.subtract(objects)
    }

    func nextRequest() -> ZMTransportRequest? {
        let nextObjects = pending.filter({ (foo) -> Bool in
            filters.reduce(true) { (result, filter) -> Bool in
                result && filter.isIncluded(foo)
            }
        })

        guard !nextObjects.isEmpty else { return nil }

        let scheduled = Set(nextObjects.prefix(transcoder.fetchLimit))

        pending.subtract(scheduled)
        downloading.formUnion(scheduled)

        let request = transcoder.requestFor(scheduled)

        request?.add(ZMCompletionHandler(on: context, block: { [weak self] (response) in
            guard let strongSelf = self else { return }

            switch response.result {
            case .permanentError, .success:
                strongSelf.downloading.subtract(scheduled)
                strongSelf.transcoder.handleResponse(response: response, for: scheduled)

                if case .permanentError = response.result {
                    self?.delegate?.didFailToSyncAllObjects()
                }
            default:
                strongSelf.downloading.subtract(scheduled)
                strongSelf.pending.formUnion(scheduled)
            }

            if !strongSelf.isSyncing {
                self?.delegate?.didFinishSyncingAllObjects()
            }

            strongSelf.transcoder.handleResponse(response: response, for: scheduled)
        }))

        return request
    }

}
