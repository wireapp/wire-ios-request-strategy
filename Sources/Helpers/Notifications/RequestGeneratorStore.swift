//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

public final class RequestGeneratorStore {
    
    let requestGenerators: [ZMTransportRequestGenerator]
    public let changeTrackers : [ZMContextChangeTracker]
    private var isTornDown = false
    
    private let strategies : [AnyObject]
    
    public init(strategies: [AnyObject]) {
        
        self.strategies = strategies
        
        var requestGenerators : [ZMTransportRequestGenerator] = []
        var changeTrackers : [ZMContextChangeTracker] = []
        
        for strategy in strategies {
            if let requestGeneratorSource = strategy as? ZMRequestGeneratorSource {
                for requestGenerator in requestGeneratorSource.requestGenerators {
                    requestGenerators.append({
                        return requestGenerator.nextRequest()
                    })
                }
            }
            
            if let contextChangeTrackerSource = strategy as? ZMContextChangeTrackerSource {
                changeTrackers.append(contentsOf: contextChangeTrackerSource.contextChangeTrackers)
            }
            
            if let contextChangeTracker = strategy as? ZMContextChangeTracker {
                changeTrackers.append(contextChangeTracker)
            }
            
            if let requestStrategy = strategy as? RequestStrategy {
                requestGenerators.append({
                    requestStrategy.nextRequest()
                })
            }
        }
        
        self.requestGenerators = requestGenerators
        self.changeTrackers = changeTrackers
    }

    deinit {
        precondition(isTornDown, "Need to call `tearDown` before deallocating this object")
    }

    public func tearDown() {
        strategies.forEach {
            if $0.responds(to: #selector(ZMObjectSyncStrategy.tearDown)) {
                ($0 as? ZMObjectSyncStrategy)?.tearDown()
            }
        }

        isTornDown = true
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        for requestGenerator in requestGenerators {
            if let request = requestGenerator() {
                return request
            }
        }
        
        return nil
    }
}
