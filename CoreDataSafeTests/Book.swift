//
//  Book.swift
//  Fliptop
//
//  Created by Eric Elfner on 2015-11-25.
//  Copyright © 2015 Eric Elfner. All rights reserved.
//

import Foundation
import CoreData

//@objc(Book)
class Book: NSManagedObject
{
    @NSManaged var title: String?
}
