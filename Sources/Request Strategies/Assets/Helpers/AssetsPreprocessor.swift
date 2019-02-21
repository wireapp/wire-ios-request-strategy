//
//  AssetsPreprocessor.swift
//  WireRequestStrategy
//
//  Created by Jacob Persson on 19.02.19.
//  Copyright © 2019 Wire GmbH. All rights reserved.
//

import Foundation

/*
 Prepares file to be uploaded
 It creates an encrypted version from the plain text version
 */
@objcMembers public final class AssetsPreprocessor : NSObject, ZMContextChangeTracker {
    
    /// Group to track preprocessing operations
    fileprivate let processingGroup : ZMSDispatchGroup
    
    /// List of objects currently being processed
    fileprivate var objectsBeingProcessed = Set<ZMAssetClientMessage>()
    
    /// Managed object context. Is is assumed that all methods of this class
    /// are called from the thread of this managed object context
    let managedObjectContext : NSManagedObjectContext
    
    /// Creates a file processor
    /// - note: All methods of this object should be called from the thread associated with the passed managedObjectContext
    public init(managedObjectContext: NSManagedObjectContext) {
        self.processingGroup = managedObjectContext.dispatchGroup
        self.managedObjectContext = managedObjectContext
    }
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        processObjects(object)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let predicate = NSPredicate(format: "version == 3 && %K == NO", DeliveredKey)
        return ZMAssetClientMessage.sortedFetchRequest(with: predicate)
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }
    
    private func processObjects(_ objects: Set<NSManagedObject>) {
        objects
            .compactMap(needsPreprocessing)
            .filter(!objectsBeingProcessed.contains)
            .forEach(startProcessing)
    }
    
    /// Starts processing the asset client message
    fileprivate func startProcessing(_ message: ZMAssetClientMessage) {
        objectsBeingProcessed.insert(message)
        self.processingGroup.enter()
        
        message.assets.forEach({ $0.skipPreprocessing() }) // TODO jacob
        message.assets.forEach({ $0.encrypt() })
        
        completeProcessing(message)
    }
    
    /// Removes the message from the list of messages being processed and update its values
    fileprivate func completeProcessing(_ message: ZMAssetClientMessage) {
        objectsBeingProcessed.remove(message)
        self.processingGroup.leave()
        message.managedObjectContext?.enqueueDelayedSave()
    }
    
    /// Returns the object as a ZMAssetClientMessage if it is asset that needs preprocessing
    private func needsPreprocessing(_ object: NSManagedObject) -> ZMAssetClientMessage? {
        guard let message = object as? ZMAssetClientMessage else { return nil }
        
        print("processingState = \(message.processingState.rawValue)")
        
        return message.processingState == .preprocessing || message.processingState == .encrypting ? message : nil
    }
}
