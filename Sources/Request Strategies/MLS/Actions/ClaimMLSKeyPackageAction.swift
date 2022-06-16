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

public class ClaimMLSKeyPackageAction: EntityAction {

    // MARK: - Types

    // Until we know what type is best for the result, we'll use [KeyPackage]
    public typealias Result = [KeyPackage]

    public enum Failure: LocalizedError, SafeForLoggingStringConvertible {

        case malformedResponse
        case invalidSkipOwn
        case userOrDomainNotFound
        case unknown(status: Int)

        public var errorDescription: String? {
            switch self {
            case .malformedResponse:
                return "Malformed response"
            case .invalidSkipOwn:
                return "Invalid parameter: skip own."
            case .userOrDomainNotFound:
                return "User domain or user not found."
            case .unknown(let status):
                return "Unknown error (response status: \(status))"
            }
        }

        public var safeForLoggingDescription: String {
            return errorDescription ?? ""
        }
    }

    // MARK: - Properties

    /// the self client id to provide if we wish to avoid claiming the key package for that client
    public let skipOwn: String?
    public let domain: String
    public let userId: UUID
    public var resultHandler: ResultHandler?

    init(domain: String, userId: UUID, skipOwn: String? = nil, resultHandler: ResultHandler? = nil) {
        self.domain = domain
        self.userId = userId
        self.skipOwn = skipOwn
        self.resultHandler = resultHandler
    }
}

// Temporary solution until we know what we need from the result. Once we do, this should move to the action handler extension.
public struct KeyPackage: Codable, Equatable {
    let client: String
    let domain: String
    let keyPackage: String
    let keyPackageRef: String
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case client
        case domain
        case keyPackage = "key_package"
        case keyPackageRef = "key_package_ref"
        case userID = "user"
    }
}
