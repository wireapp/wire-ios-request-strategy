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
import WireSystem
import WireDataModel

/*
Prepares file to be uploaded
It creates an encrypted version from the plain text version
*/
@objcMembers public final class FilePreprocessor : NSObject, ZMContextChangeTracker {
    
    /// Queue to use for processing files
    fileprivate let processingQueue : DispatchQueue
    
    /// Group to track preprocessing operations
    fileprivate let processingGroup : ZMSDispatchGroup
    
    /// List of objects currently being processed
    fileprivate var objectsBeingProcessed = Set<ZMAssetClientMessage>()
    
    /// Managed object context. Is is assumed that all methods of this class
    /// are called from the thread of this managed object context
    let managedObjectContext : NSManagedObjectContext

    private let filter: NSPredicate
    
    /// Creates a file processor
    /// - note: All methods of this object should be called from the thread associated with the passed managedObjectContext
    public init(managedObjectContext: NSManagedObjectContext, filter: NSPredicate) {
        self.processingGroup = managedObjectContext.dispatchGroup
        self.processingQueue = DispatchQueue(label: "File processor")
        self.managedObjectContext = managedObjectContext
        self.filter = filter
    }
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        processObjects(object)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let predicate = NSPredicate(format: "%K == NO && %K == %d", DeliveredKey, #keyPath(ZMAssetClientMessage.transferState), ZMFileTransferState.uploading.rawValue)
        return ZMAssetClientMessage.sortedFetchRequest(with: predicate)
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }

    private func processObjects(_ objects: Set<NSManagedObject>) {
        objects
            .compactMap(fileAssetToPreprocess)
            .filter(!objectsBeingProcessed.contains)
            .forEach(startProcessing)
    }
    
    /// Starts processing the asset client message
    fileprivate func startProcessing(_ message: ZMAssetClientMessage) {
        objectsBeingProcessed.insert(message)
        self.processingGroup.enter()
        if let encryptionKeys = message.encryptFile() {
            completeProcessing(message, keys: encryptionKeys)
        }
    }
    
    /// Removes the message from the list of messages being processed and update its values
    fileprivate func completeProcessing(_ message: ZMAssetClientMessage, keys: ZMImageAssetEncryptionKeys) {
        objectsBeingProcessed.remove(message)
        message.addUploadedGenericMessage(keys)
        self.processingGroup.leave()
        message.managedObjectContext?.enqueueDelayedSave()
    }

    /// Returns the object as a ZMAssetClientMessage if it is asset that needs preprocessing
    private func fileAssetToPreprocess(_ obj: NSObject) -> ZMAssetClientMessage? {
        guard let message = obj as? ZMAssetClientMessage else { return nil }
        return message.needsEncryptedFile && filter.evaluate(with: message) ? message : nil
    }
}

extension ZMAssetClientMessage {
    
    /// Encrypts the plain text version of the file to the asset cache
    fileprivate func encryptFile() -> ZMImageAssetEncryptionKeys? {
        return self.managedObjectContext?.zm_fileAssetCache.encryptFileAndComputeSHA256Digest(self)
    }
    
    /// Returns whether the message needs an encrypted version of the file that is not there yet
    var needsEncryptedFile : Bool {
        return self.filename != nil
            && self.transferState == .uploading
            && self.imageMessageData == nil
            && !self.delivered
            && self.genericAssetMessage?.assetData?.original.hasImage() == false
            && self.genericAssetMessage?.assetData?.uploaded.hasOtrKey() == false
            && self.managedObjectContext != nil
            && self.managedObjectContext!.zm_fileAssetCache.assetData(self, encrypted: true) == nil
    }
    
    /// Adds Uploaded generic message
    fileprivate func addUploadedGenericMessage(_ keys: ZMImageAssetEncryptionKeys) {
        self.add(ZMGenericMessage.message(content: ZMAsset.asset(withUploadedOTRKey: keys.otrKey, sha256: keys.sha256!), nonce: nonce!, expiresAfter: deletionTimeout))
    }
}
