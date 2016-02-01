//
//  Author+CoreDataProperties.swift
//  CoreDataSafeExample
//
//  Created by Eric Elfner on 2016-02-01.
//  Copyright © 2016 Eric Elfner. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Author {

    @NSManaged var name: String?
    @NSManaged var books: NSOrderedSet?

}
