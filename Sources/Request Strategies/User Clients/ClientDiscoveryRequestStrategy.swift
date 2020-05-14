// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

import Foundation

/// This strategy is used to get an up-to-date list of all clients in a given conversation.
/// It achieves this by posting an empty OTR message with no recipients in the coversation,
/// then parsing the 412 error response to discover the list of missing clients reported by
/// the backend.

public final class ClientDiscoveryRequestStrategy: NSObject, RequestStrategy {

  public typealias ClientIdsByUserId = [String: [String]]
  public typealias RequestCompletion = (ClientIdsByUserId) -> Void

  // MARK: - Private properties

  private let managedObjectContext: NSManagedObjectContext

  private let requestFactory = ClientMessageRequestFactory()
  private var requestSync: ZMSingleRequestSync!

  private var pendingRequest: ZMTransportRequest?
  private var pendingCompletion: RequestCompletion?

  // MARK: - Init

  public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext) {
    self.managedObjectContext = managedObjectContext
    super.init()
    requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: managedObjectContext)
  }

  // MARK: - Methods

  public func nextRequest() -> ZMTransportRequest? {
    return requestSync.nextRequest()
  }

  /// Triggers a request to fetch the list of clients in a given conversation.
  ///
  /// - Parameters:
  ///   - conversationId: the id of the conversation.
  ///   - completion: invoked with a map of user ids to an array of client ids.

  public func requestClientList(conversationId: UUID, completion: @escaping RequestCompletion) {
    managedObjectContext.performGroupedBlock { [unowned self] in
      guard let selfClient = ZMUser.selfUser(in: self.managedObjectContext).selfClient() else { return }

      self.pendingRequest = self.requestFactory.upstreamRequestForFetchingClients(conversationId: conversationId,
                                                                                  selfClient: selfClient)
      self.pendingCompletion = completion
      self.requestSync.readyForNextRequestIfNotBusy()
      RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
  }

}

// MARK: - Single Request Transcoder

extension ClientDiscoveryRequestStrategy: ZMSingleRequestTranscoder {

  public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
    defer { pendingRequest = nil }
    return pendingRequest
  }

  public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
    guard
      let payload = response.payload as? [String: AnyObject],
      let missingClients = payload["missing"] as? ClientIdsByUserId
      else { return }

    pendingCompletion?(missingClients)
    pendingCompletion = nil
  }

}
