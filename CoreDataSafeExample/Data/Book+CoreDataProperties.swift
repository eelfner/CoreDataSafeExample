//
//  Book+CoreDataProperties.swift
//  CoreDataSafeExample
//
//  Created by Eric Elfner on 2016-02-02.
//  Copyright © 2016 Eric Elfner. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Book {

    @NSManaged var title: String?
    @NSManaged var pageCount: NSNumber?
    @NSManaged var comment: String?
    @NSManaged var author: Author?

}
