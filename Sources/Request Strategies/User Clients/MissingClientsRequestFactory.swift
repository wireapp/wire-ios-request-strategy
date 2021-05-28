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
import WireDataModel


extension Set where Set.Element == UserClient {

    var clientListByUserID: Payload.ClientListByUserID {

        let initial: Payload.ClientListByUserID = [:]

        return self.reduce(into: initial) { (result, client) in
            guard let userID = client.user?.remoteIdentifier.transportString(),
                  let clientID = client.remoteIdentifier
            else {
                return
            }

            var clientList = result[userID] ?? []
            clientList.append(clientID)
            result[userID] = clientList
        }
    }
}

public final class MissingClientsRequestFactory {
    
    let pageSize : Int

    public init(pageSize: Int = 128) {
        self.pageSize = pageSize
    }

    public func fetchPrekeys(for missingClients: Set<UserClient>) -> ZMUpstreamRequest {
        let payloadData = missingClients.clientListByUserID.takeFirst(pageSize).payloadData()!
        let payloadAsString = String(bytes: payloadData, encoding: .utf8)
        let request = ZMTransportRequest(path: "/users/prekeys",
                                         method: .methodPOST,
                                         payload: payloadAsString as ZMTransportData?)
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientMissingKey),
                                 transportRequest: request,
                                 userInfo: nil)
    }
    
}

public func identity<T>(value: T) -> T {
    return value
}
