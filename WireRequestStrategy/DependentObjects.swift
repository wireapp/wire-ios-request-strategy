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

fileprivate let zmLog = ZMSLog(tag: "Dependencies")


public class DependentObjects<OBJECT: Hashable, DEPENDENCY: Hashable> {
    
    public init() {
    }
    
    private var dependenciesToDependents: [DEPENDENCY: Set<OBJECT>] = [:]
    private var dependentsToDependencies: [OBJECT: Set<DEPENDENCY>] = [:] // inverse of the previous one
 
    /// Adds a dependency to an
    public func add(dependent: OBJECT, dependency: DEPENDENCY) {
        zmLog.debug("Adding dependency of type \(type(of: dependency)) to object \(type(of: dependent)), object is: \(dependent)")
        let toDependents = self.dependenciesToDependents[dependency] ?? Set()
        self.dependenciesToDependents[dependency] = toDependents.union([dependent])
        
        let toDependencies = self.dependentsToDependencies[dependent] ?? Set()
        self.dependentsToDependencies[dependent] = toDependencies.union([dependency])
    }
    
    
    /// Return any one dependency for the given dependent
    public func anyDependency(for dependent: OBJECT) -> DEPENDENCY? {
        return self.dependentsToDependencies[dependent]?.first
    }
    
    /// Removes from dependencies those objects for which the `block` returns true
    public func enumerateAndRemoveObjects(for dependency: DEPENDENCY, block: (OBJECT)->Bool) {
        guard let objects = self.dependenciesToDependents[dependency] else { return }
        let objectsToRemove = objects.filter { block($0) }
        guard !objectsToRemove.isEmpty else { return }
        objectsToRemove.forEach {
            self.remove(dependency: dependency, for: $0)
        }
    }
    
    public func dependencies(for dependent: OBJECT) -> Set<DEPENDENCY> {
        return self.dependentsToDependencies[dependent] ?? Set()
    }
    
    public func dependents(on dependency: DEPENDENCY) -> Set<OBJECT> {
        return self.dependenciesToDependents[dependency] ?? Set()
    }

    public func remove(dependency: DEPENDENCY, for dependent: OBJECT) {
        self.updateDependents(dependent: dependent, removing: dependency)
        self.updateDependencies(dependency: dependency, removing: dependent)
    }
    
    private func updateDependencies(dependency: DEPENDENCY, removing dependent: OBJECT) {
        guard let currentSet = dependenciesToDependents[dependency] else { return }
        let newSet = currentSet.subtracting([dependent])
        if newSet.isEmpty {
            dependenciesToDependents.removeValue(forKey: dependency)
        } else {
            dependenciesToDependents[dependency] = newSet
        }
    }
    
    private func updateDependents(dependent: OBJECT, removing dependency: DEPENDENCY) {
        guard let currentSet = dependentsToDependencies[dependent] else { return }
        let newSet = currentSet.subtracting([dependency])
        if newSet.isEmpty {
            dependentsToDependencies.removeValue(forKey: dependent)
        } else {
            dependentsToDependencies[dependent] = newSet
        }
    }
}


/// List of dependency.
/// This is an adapter class for Obj-c, because Obj-c can't use generics.
/// We will remove it as soon as all the clients of this class are ported to Swift
@objc public class DependentObjectsObjc: NSObject {
    
    let dependentObjects: DependentObjects<ZMManagedObject, ZMManagedObject>
    
    public override init() {
        self.dependentObjects = DependentObjects()
        super.init()
    }
    
    @objc(addDependentObject:dependency:)
    public func add(dependent: ZMManagedObject, dependency: ZMManagedObject) {
        self.dependentObjects.add(dependent: dependent, dependency: dependency)
    }
    
    @objc(anyDependencyForObject:)
    public func anyDependency(for object: ZMManagedObject) -> ZMManagedObject? {
        return dependentObjects.anyDependency(for: object)
    }
    
    public func enumerateAndRemoveObjects(for dependency: ZMManagedObject, block: (ZMManagedObject)->Bool) {
        self.dependentObjects.enumerateAndRemoveObjects(for: dependency, block: block)
    }
    
}
