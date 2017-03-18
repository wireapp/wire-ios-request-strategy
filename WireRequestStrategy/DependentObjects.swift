//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

@objc public class DependentObjects: NSObject {
    
    private var dependenciesToDependants: [AnyHashable: Set<AnyHashable>] = [:]
    private var dependantsToDependencies: [AnyHashable: Set<AnyHashable>] = [:] // inverse of the previous one
    
    public override init() {
    }
 
    @objc(addDependentObject:dependency:)
    public func add(dependent: ZMManagedObject, dependency: AnyHashable) {
        var toDependants = self.dependenciesToDependants[dependency] ?? Set()
        _ = toDependants.insert(dependent)
        self.dependenciesToDependants[dependency] = toDependants
        
        var toDependencies = self.dependantsToDependencies[dependent] ?? Set()
        toDependencies.insert(dependency)
        self.dependantsToDependencies[dependent] = toDependencies
    }
    
    @objc(anyDependencyForObject:)
    public func anyDependency(for object: ZMManagedObject) -> Any? {
        return self.dependantsToDependencies[object]?.first
    }
    
    /// Removes from dependencies those objects for which the `block` returns true
    public func enumerateAndRemoveObjects(for dependency: AnyHashable, block: (Any)->Bool) {
        guard let objects = self.dependenciesToDependants[dependency] else { return }
        let filteredObjects = objects.filter { !block($0) }
        if filteredObjects.isEmpty {
            self.dependenciesToDependants.removeValue(forKey: dependency)
        } else {
            self.dependenciesToDependants[dependency] = Set(filteredObjects)
        }
    }
}
