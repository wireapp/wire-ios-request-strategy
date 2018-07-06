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


import WireImages
import WireTransport

fileprivate let zmLog = ZMSLog(tag: "Asset V3")


@objcMembers public final class AssetV3DownloadRequestStrategy: AbstractRequestStrategy, ZMDownstreamTranscoder, ZMContextChangeTrackerSource {

    fileprivate var assetDownstreamObjectSync: ZMDownstreamObjectSync!
    private var notificationToken: Any? = nil

    private typealias DecryptionKeys = (otrKey: Data, sha256: Data)
    
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)

        zmLog.debug("Asset V3 file download logging set up.")
        registerForCancellationNotification()

        let downstreamPredicate = NSPredicate(format: "transferState == %d AND visibleInConversation != nil AND version == 3", ZMFileTransferState.downloading.rawValue)

        let filter = NSPredicate { object, _ in
            guard let message = object as? ZMAssetClientMessage else { return false }
            guard message.fileMessageData != nil else { return false }
            guard let asset = message.genericAssetMessage?.assetData else { return false }
            return asset.hasUploaded() && asset.uploaded.hasAssetId()
        }

        configuration = .allowsRequestsDuringEventProcessing

        self.assetDownstreamObjectSync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            predicateForObjectsToDownload: downstreamPredicate,
            filter: filter,
            managedObjectContext: managedObjectContext
        )
    }

    func registerForCancellationNotification() {
        self.notificationToken = NotificationInContext.addObserver(name: ZMAssetClientMessage.didCancelFileDownloadNotificationName,
                                                                   context: self.managedObjectContext.notificationContext,
                                                                   object: nil)
        {
            [weak self] note in
            guard let objectID = note.object as? NSManagedObjectID else { return }
            self?.cancelOngoingRequestForAssetClientMessage(objectID)
        }
    }

    func cancelOngoingRequestForAssetClientMessage(_ objectID: NSManagedObjectID) {
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let `self` = self  else { return }
            guard let message = self.managedObjectContext.registeredObject(for: objectID) as? ZMAssetClientMessage else { return }
            guard message.version == 3 else { return }
            guard let identifier = message.associatedTaskIdentifier else { return }
            self.applicationStatus?.requestCancellation.cancelTask(with: identifier)
            message.associatedTaskIdentifier = nil
        }
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return self.assetDownstreamObjectSync.nextRequest()
    }

    fileprivate func handleResponse(_ response: ZMTransportResponse, forMessage assetClientMessage: ZMAssetClientMessage) {
        if response.result == .success {
            guard let fileMessageData = assetClientMessage.fileMessageData,
                assetClientMessage.visibleInConversation != nil else { return }

            let decryptionSuccess = storeAndDecrypt(data: response.rawData!, for: assetClientMessage, fileMessageData: fileMessageData)
            if decryptionSuccess {
                assetClientMessage.transferState = .downloaded
            }
            else {
                assetClientMessage.transferState = .failedDownload
            }
        }
        else if response.result == .permanentError {
            if assetClientMessage.transferState == .downloading {
                zmLog.debug("asset unavailable on remote (\(response.httpStatus)), setting state to .unavailable")
                assetClientMessage.transferState = .unavailable
            }
        }
        else {
            if assetClientMessage.transferState == .downloading {
                zmLog.debug("error loading asset (\(response.httpStatus)), setting state to .failedDownload")
                assetClientMessage.transferState = .failedDownload
            }
        }

        //we've just downloaded some data, we need to refresh the category of the message.
        assetClientMessage.updateCategoryCache()
        let messageObjectId = assetClientMessage.objectID
        let downloadSuccess = assetClientMessage.transferState == .downloaded
        let uiMOC = self.managedObjectContext.zm_userInterface!
        uiMOC.performGroupedBlock({ () -> Void in
            let uiMessage = (try? uiMOC.existingObject(with: messageObjectId)) as? ZMAssetClientMessage

            let userInfo: [String: Any] = [AssetDownloadRequestStrategyNotification.downloadStartTimestampKey: response.startOfUploadTimestamp ?? Date()]
            if downloadSuccess {
                NotificationInContext(name: AssetDownloadRequestStrategyNotification.downloadFinishedNotificationName,
                                      context: self.managedObjectContext.notificationContext,
                                      object: uiMessage,
                                      userInfo: userInfo).post()
            }
            else {
                NotificationInContext(name: AssetDownloadRequestStrategyNotification.downloadFailedNotificationName,
                                      context: self.managedObjectContext.notificationContext,
                                      object: uiMessage,
                                      userInfo: userInfo).post()
            }
        })
    }

    private func storeAndDecrypt(data: Data, for message: ZMAssetClientMessage, fileMessageData: ZMFileMessageData) -> Bool {
        guard let genericMessage = message.genericAssetMessage,
              let asset = genericMessage.assetData
        else { return false }

        let keys = (asset.uploaded.otrKey!, asset.uploaded.sha256!)

        if asset.original.hasRasterImage {
            return storeAndDecryptImage(asset: asset, message: message, data: data, keys: keys)
        } else {
            return storeAndDecryptFile(asset: asset, message: message, data: data, keys: keys)
        }
    }

    private func storeAndDecryptImage(asset: ZMAsset, message: ZMAssetClientMessage, data: Data, keys: DecryptionKeys) -> Bool {
        precondition(asset.original.hasRasterImage, "Should only be called for assets with image")

        let cache = managedObjectContext.zm_fileAssetCache
        cache.storeAssetData(message, format: .medium, encrypted: true, data: data)
        let success = cache.decryptImageIfItMatchesDigest(message, format: .medium, encryptionKey: keys.otrKey, sha256Digest: keys.sha256)
        if !success {
            zmLog.error("Failed to decrypt v3 asset (image) message: \(asset), nonce:\(message.nonce!)")
        }
        return success
    }

    private func storeAndDecryptFile(asset: ZMAsset, message: ZMAssetClientMessage, data: Data, keys: DecryptionKeys) -> Bool {
        precondition(!asset.original.hasRasterImage, "Should not be called for assets with image")

        let cache = managedObjectContext.zm_fileAssetCache
        cache.storeAssetData(message, encrypted: true, data: data)
        let success = cache.decryptFileIfItMatchesDigest(message, encryptionKey: keys.otrKey, sha256Digest: keys.sha256)
        if !success {
            zmLog.error("Failed to decrypt v3 asset (file) message: \(asset), nonce:\(message.nonce!)")
        }
        return success
    }

    // MARK: - ZMContextChangeTrackerSource

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [assetDownstreamObjectSync]
    }

    // MARK: - ZMDownstreamTranscoder

    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        if let assetClientMessage = object as? ZMAssetClientMessage {

            let taskCreationHandler = ZMTaskCreatedHandler(on: managedObjectContext) { taskIdentifier in
                assetClientMessage.associatedTaskIdentifier = taskIdentifier
            }

            let completionHandler = ZMCompletionHandler(on: self.managedObjectContext) { response in
                self.handleResponse(response, forMessage: assetClientMessage)
            }

            let progressHandler = ZMTaskProgressHandler(on: self.managedObjectContext) { progress in
                assetClientMessage.progress = progress
                self.managedObjectContext.enqueueDelayedSave()
            }

            if let asset = assetClientMessage.genericAssetMessage?.assetData {
                let token = asset.uploaded.hasAssetToken() ? asset.uploaded.assetToken : nil
                if let request = AssetDownloadRequestFactory().requestToGetAsset(withKey: asset.uploaded.assetId, token: token) {
                    request.add(taskCreationHandler)
                    request.add(completionHandler)
                    request.add(progressHandler)
                    return request
                }
            }
        }

        fatalError("Cannot generate request for \(object)")
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
}
