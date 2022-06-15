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

class ClaimMLSKeyPackageActionHandler: ActionHandler<ClaimMLSKeyPackageAction> {

    // MARK: - Methods

    override func request(for action: ActionHandler<ClaimMLSKeyPackageAction>.Action, apiVersion: APIVersion) -> ZMTransportRequest? {
        let path = "/mls/key-packages/claim/\(action.domain)/\(action.userId.transportString())"

        var payload: ZMTransportData?
        if let skipOwn = action.skipOwn {
            payload = ["skip_own": skipOwn] as ZMTransportData
        }

        return ZMTransportRequest(
            path: path,
            method: .methodPOST,
            payload: payload,
            apiVersion: apiVersion.rawValue
        )
    }

    override func handleResponse(_ response: ZMTransportResponse, action: ActionHandler<ClaimMLSKeyPackageAction>.Action) {
        var action = action

        switch response.httpStatus {
        case 200:
            guard
                let data = response.rawData,
                let payload = try? JSONDecoder().decode(ResponsePayload.self, from: data)
            else {
                return action.notifyResult(.failure(.malformedResponse))
            }

            action.notifyResult(.success(payload.keyPackages))
        case 400:
            action.notifyResult(.failure(.invalidSkipOwn))
        case 404:
            action.notifyResult(.failure(.userOrDomainNotFound))
        default:
            action.notifyResult(.failure(.unknown(status: response.httpStatus)))
        }
    }
}

extension ClaimMLSKeyPackageActionHandler {

    // MARK: - Payload

    struct ResponsePayload: Codable {
        let keyPackages: [KeyPackage]

        enum CodingKeys: String, CodingKey {
            case keyPackages = "key_packages"
        }
    }

}
