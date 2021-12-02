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
    var shouldRetryOnExpiration: Bool { get }

    /// Returns a request for synchronzing a single object
    func requestFor(_ object: Object) -> ZMTransportRequest?

    /// /// Returns a request for synchronzing a set of objects
    func requestFor(_ objects: Set<Object>) -> ZMTransportRequest?

    /// Handle the response for synchronzing a single object
    func handleResponse(response: ZMTransportResponse, for object: Object)

    /// Handle the response for synchronzing a set of objects objects
    func handleResponse(response: ZMTransportResponse, for objects: Set<Object>)

    func shouldTryToResend(_ object: Object, afterFailureWithResponse: ZMTransportResponse) -> Bool
    func shouldTryToResend(_ objects: Set<Object>, afterFailureWithResponse: ZMTransportResponse) -> Bool
}

extension ObjectTranscoder {

    var fetchLimit: Int {
        1
    }

    var shouldRetryOnExpiration: Bool {
        return true
    }

    func requestFor(_ objects: Set<Object>) -> ZMTransportRequest? {
        guard let object = objects.first else {
            return nil
        }
        return requestFor(object)
    }

    func handleResponse(response: ZMTransportResponse, for objects: Set<Object>) {
        guard let object = objects.first else {
            return
        }
        handleResponse(response: response, for: object)
    }

    func shouldTryToResend(_ object: Object, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        return !response.isPermanentylUnavailableError()
    }

    func shouldTryToResend(_ objects: Set<Object>, afterFailureWithResponse response: ZMTransportResponse) -> Bool {
        guard let object = objects.first else {
            return false
        }
        return shouldTryToResend(object, afterFailureWithResponse: response)
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

        objects.forEach { object in
            if predicate.evaluate(with: object) {
                publish(object)
            } else {
                unpublish(object)
            }
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

/// Observes an entity and schedules them to be synchronize when the predicate evaluates to `True`.
class ModifiedKeySource<Object: ZMManagedObject>: NSObject, ObjectSource, ZMContextChangeTracker {
    typealias Object = Object

    let trackedKey: String
    let predicate: NSPredicate?
    var onPublish: OnPublish?
    var onUnpublish: OnPublish?

    /// - Parameters:
    ///   - trackedKey: Key / property which should synchchronized when modified.
    ///   - modifiedPredicate: Predicate which determine if an object has been modified or not. If omitted
    ///                        an object is considered modified in all cases when the tracked key has been changed.
    init(trackedKey: String,
         modifiedPredicate: NSPredicate? = nil) {
        self.trackedKey = trackedKey
        self.predicate = modifiedPredicate
    }

    func objectsDidChange(_ objects: Set<NSManagedObject>) {
        let objects = objects.compactMap({ $0 as? Object })

        objects.filter({ ($0.modifiedKeys?.contains(trackedKey) ?? false) &&
                         predicate?.evaluate(with: $0) ?? true }).forEach { object in
            publish(object)
        }
    }

    func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        if let predicate = predicate {
            return Object.sortedFetchRequest(with: predicate)
        } else {
            return Object.sortedFetchRequest()
        }
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

public enum ObjectSyncError: Error {
    case expired
    case gaveUpRetrying
}

public typealias ObjectSyncHandler = (_ result: Swift.Result<Void, ObjectSyncError>, _ response: ZMTransportResponse) -> Void

/// Synchronizes objects using a configurable sources, filters and transcoder.
///
class ObjectSync<Object, Trans: ObjectTranscoder>: NSObject, ZMRequestGenerator, ZMContextChangeTrackerSource where Trans.Object == Object {

    public typealias ScheduledHandler = (_ object: Object) -> Void
    public typealias CompletedHandler = (_ object: Object, _ result: Swift.Result<Void, ObjectSyncError>, _ response: ZMTransportResponse) -> Void

    var pending: Set<Object> = Set()
    var downloading: Set<Object> = Set()
    var filters: [AnyObjectFilter<Object>] = []
    var sources: [Any] = []
    var transcoder: Trans
    var context: NSManagedObjectContext
    var scheduledHandler: ScheduledHandler?
    var completedHandler: CompletedHandler?
    var completionHandlers: [Object: ObjectSyncHandler] = [:]
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

    /// Add handler which is called when objects are scheduled for synchronization
    func onScheduled(_ handler: @escaping ScheduledHandler) {
        scheduledHandler = handler
    }

    /// Add handler which is called when objects complete their synchronization
    func onCompleted(_ handler: @escaping CompletedHandler) {
        completedHandler = handler
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
    /// - parameter completion: Completion handler which is called when object has been synchronized.
    func synchronize(_ object: Object, completion completionHandler: ObjectSyncHandler? = nil) {
        completionHandlers[object] = completionHandler
        synchronize([object])
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
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
            case .success:
                strongSelf.clear(scheduled)
                strongSelf.transcoder.handleResponse(response: response, for: scheduled)
                strongSelf.reportResult(scheduled, result: .success(()), response)
            case .expired:
                if strongSelf.transcoder.shouldRetryOnExpiration {
                    strongSelf.reschedule(scheduled)
                } else {
                    strongSelf.clear(scheduled)
                    strongSelf.reportResult(scheduled, result: .failure(.expired), response)
                    self?.delegate?.didFailToSyncAllObjects()
                }
            default:
                if strongSelf.transcoder.shouldTryToResend(scheduled, afterFailureWithResponse: response) {
                    strongSelf.reschedule(scheduled)
                } else {
                    strongSelf.transcoder.handleResponse(response: response, for: scheduled)
                    strongSelf.clear(scheduled)
                    strongSelf.reportResult(scheduled, result: .failure(.gaveUpRetrying), response)
                    self?.delegate?.didFailToSyncAllObjects()
                }
            }

            if !strongSelf.isSyncing {
                self?.delegate?.didFinishSyncingAllObjects()
            }
        }))

        scheduled.forEach({ object in
            scheduledHandler?(object)
        })

        return request
    }

    private func clear(_ objects: Set<Object>) {
        downloading.subtract(objects)
    }

    private func reschedule(_ objects: Set<Object>) {
        downloading.subtract(objects)
        pending.formUnion(objects)
    }

    private func reportResult(_ objects: Set<Object>, result: Swift.Result<Void, ObjectSyncError>, _ response: ZMTransportResponse) {
        for object in objects {
            let completionHandler = completionHandlers.removeValue(forKey: object)
            completionHandler?(result, response)
            completedHandler?(object, result, response)
        }
    }

}
