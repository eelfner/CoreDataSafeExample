//
//  CoreDataTests.swift
//  Fliptop
//
//  Created by Eric Elfner on 2015-11-25.
//  Copyright © 2015 Eric Elfner. All rights reserved.
//

import XCTest
import CoreData
@testable import CoreDataSafeExample

class CoreDataTests: XCTestCase
{
    var coreDataMgr:CoreDataSafe!

    override func setUp()
    {
        super.setUp()

        let expectation = expectationWithDescription("setupSuccess")
        let testBundle = NSBundle(forClass: CoreDataTests.self)
        coreDataMgr = CoreDataSafe(dbName:"TestModel", bundle:testBundle) {_ in
             self.deleteAllBooks() { _ in expectation.fulfill() }
        }
        
        waitForExpectationsWithTimeout(10, handler: nil)
}
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    func testCRUDOnMain() {
        let expectionCreate = expectationWithDescription("created")
        let expectionRead = expectationWithDescription("read")
        let expectionUpdate = expectationWithDescription("updated")
        let expectionDelete = expectationWithDescription("deleted")
        
        // Create
        let book:Book = coreDataMgr.createEntity("Book") as! Book
        let time = NSDate().timeIntervalSince1970
        let title = "Title at \(time)"
        book.title = title
        XCTAssertNotNil(book)
        try! coreDataMgr.mainMoc.save()
        expectionCreate.fulfill()

        // Read
        let fetchRequest1 = NSFetchRequest(entityName:"Book")
        let titleSearchPredicate1 = NSPredicate(format:"title=%@", title)
        fetchRequest1.predicate = titleSearchPredicate1

        let results1 =  try! coreDataMgr.mainMoc.executeFetchRequest(fetchRequest1)
        XCTAssert(results1.count == 1)
        let bookRead = (results1 as! [Book])[0]
        if bookRead.title == title { expectionRead.fulfill() }

        // Update
        let title2 = "\(title)2"
        bookRead.title = title2
        try! coreDataMgr.mainMoc.save()
        
        let fetchRequest2 = NSFetchRequest(entityName:"Book")
        let titleSearchPredicate2 = NSPredicate(format:"title=%@", title2)
        fetchRequest2.predicate = titleSearchPredicate2
        
        let results2 =  try! coreDataMgr.mainMoc.executeFetchRequest(fetchRequest2)
        XCTAssert(results2.count == 1)
        let bookRead2 = (results2 as! [Book])[0]
        if bookRead2.title == title2 { expectionUpdate.fulfill() }
        
        // Delete
        coreDataMgr.mainMoc.deleteObject(bookRead2)
        try! coreDataMgr.mainMoc.save()
        
        let results3 =  try! coreDataMgr.mainMoc.executeFetchRequest(fetchRequest2)
        XCTAssert(results3.count == 0)
        expectionDelete.fulfill()
        
        waitForExpectationsWithTimeout(0, handler: nil) // Should all be synchronous
    }

    func testHammerCoreDataFromBackground() {
        // Configured for lots of contention on a few objects. Results in lost updates, but no errors. Per design.
        let MAX_BOOKS = 10     // Few books (like 10) will create a lot of contention (threads updating the same object at same time.
        let MAX_THREADS = 10   // More threads (like 10+) will create more contention.
        let MAX_OPS = 100      // More operations (like 100+) will create more contention.
        
        print("Testing with [\(MAX_BOOKS)] books, [\(MAX_THREADS)] worker threads running [\(MAX_OPS)] updates each.")
        
        for i in 0 ..< MAX_BOOKS {
            let book:Book = coreDataMgr.createEntity("Book") as! Book
            book.title = "Book\(String(format: "%03d", i))"
        }
        try! coreDataMgr.mainMoc.save()
        print("Created [\(MAX_BOOKS)] books.")
        
        var delayNsec = 0
        let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        for j in 0 ..< MAX_THREADS {
            let expectation = expectationWithDescription("runBookUpdates\(j)Completed")
            delayNsec += Int(arc4random_uniform(UInt32(1_000_000))) // If you make this 100,000,000 you'll see many more updates.
            let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(delayNsec))
            dispatch_after(delayTime, backGroundQueue) {
                self.runBookUpdates(j, maxOps:MAX_OPS)
                expectation.fulfill()
                print("\(expectation)")
            }
        }
        print("Started [\(MAX_THREADS)] update threads.")
        waitForExpectationsWithTimeout(10, handler: nil)
        let updates = showBooks()
        let maxUpdates = MAX_THREADS * MAX_OPS
        let missedUpdates = maxUpdates - updates
        print("Missed updates: \(missedUpdates)/\(maxUpdates)")
    }
    private func runBookUpdates(threadId:Int, maxOps:Int) {
        
        let moc = coreDataMgr.temporaryBackgroundMOC(name:"T\(threadId)")
        
        let fetchRequest = NSFetchRequest(entityName:"Book")
        do {
            let results =  try moc.executeFetchRequest(fetchRequest)
            let books = results as! [Book]
            for _ in 1...maxOps {
                let randInt = Int(arc4random_uniform(UInt32(books.count)))
                let randomBook = books[randInt]
                randomBook.title = (randomBook.title ?? "") + "-\(threadId)"
                try moc.save()
            }
        }
        catch let error as NSError {
            print("runBookUpdates error: \(error), \(error.userInfo)")
        }
    }

    // This test shows that background thread updates and deletes propogate to main context.
    // Note that NSManagedObjects on the main thread that have been deleted elsewhere (background)
    // have their property values return nil and the managedObjectContext set to nil. Also note,
    // (but not shown here) that the isDeleted property of these objects will be false (nil) and
    // cannot be used to determine if the object has been deleted. This property essentially says
    // that the object still exists and will be deleted on the moc.save().
    func testBackgroundUpdateAndDelete() {
        let kNanoSecsPerMillisec = Int64(1_000_000)
        
        let expectionCreate = expectationWithDescription("created")
        // Note: update and delete expectations are created as optional so they can be removed after first encountered.
        var expectionUpdatePropogated:XCTestExpectation? = expectationWithDescription("expectionUpdatePropogated")
        var expectionDeletePropogated:XCTestExpectation? = expectationWithDescription("expectionDeletePropogated")
        let expectionCheckedAll = expectationWithDescription("expectionCheckedAll")
        
        // Create
        let book:Book = coreDataMgr.createEntity("Book") as! Book
        let time = NSDate().timeIntervalSince1970
        let title = "Title at \(time)"
        book.title = title
        XCTAssertNotNil(book)
        try! coreDataMgr.mainMoc.save()
        expectionCreate.fulfill()
        
        // Setup intervals
        let delayMsecs:[Int64] = [0, 10, 1_000, 2_000, 3_000]
        let delayTimes = delayMsecs.map() { dispatch_time(DISPATCH_TIME_NOW, Int64($0 * kNanoSecsPerMillisec)) }
        
        // Read at intervals
        let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(backGroundQueue) {
            for delayTime in delayTimes {
                dispatch_after(delayTime, dispatch_get_main_queue()) {
                    print("Delay:\(delayTime)ns - Book: \(book.title ?? "nil") hasMoc: \(book.managedObjectContext != nil)")
                    
                    // Check test expectations
                    if ((book.title?.containsString("updated")) != nil) { expectionUpdatePropogated?.fulfill(); expectionUpdatePropogated = nil }
                    if (book.managedObjectContext == nil)          { expectionDeletePropogated?.fulfill(); expectionDeletePropogated = nil }
                    if delayTime == delayTimes.last                { expectionCheckedAll.fulfill() }
                }
            }
        }
        
        // Update in background
        let timeAfter1 = dispatch_time(delayTimes[1], Int64(1 * kNanoSecsPerMillisec))
        dispatch_after(timeAfter1, dispatch_get_main_queue()) {
            self.updateRandomBookInBackground()
        }
        
        // Delete in background
        let timeAfter2 = dispatch_time(delayTimes[2], Int64(1 * kNanoSecsPerMillisec))
        dispatch_after(timeAfter2, dispatch_get_main_queue()) {
            self.deleteRandomBookInBackground()
        }

        waitForExpectationsWithTimeout(5, handler: nil) // Should all be synchronous
    }

    private func updateRandomBookInBackground() {
        let backgroundMoc1 = coreDataMgr.temporaryBackgroundMOC(name:"T-BackgroundUpdate")
        
        let fetchRequest1 = NSFetchRequest(entityName:"Book")
        do {
            let results =  try backgroundMoc1.executeFetchRequest(fetchRequest1)
            let books = results as! [Book]
            
            let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
            let randomBook = books[randomIndex]
            randomBook.title = (randomBook.title ?? "") + "-Updated"
            try backgroundMoc1.save()
            print("book[\(randomIndex)] updated")
        }
        catch let error as NSError {
            print("runBookUpdates error: \(error), \(error.userInfo)")
        }

    }
    private func deleteRandomBookInBackground() {
        let backgroundMoc2 = coreDataMgr.temporaryBackgroundMOC(name:"T-BackgroundDelete")
        
        let fetchRequest2 = NSFetchRequest(entityName:"Book")
        do {
            let results =  try backgroundMoc2.executeFetchRequest(fetchRequest2)
            let books = results as! [Book]
            
            let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
            let randomBook = books[randomIndex]
            backgroundMoc2.deleteObject(randomBook)
            try backgroundMoc2.save()
            print("book[\(randomIndex)] deleted")
        }
        catch let error as NSError {
            print("runBookUpdates error: \(error), \(error.userInfo)")
        }
        
    }
    // MARK: Helper methods
    private func showBooks() -> Int {
        var charCount = 0
        let fetchRequest = NSFetchRequest(entityName:"Book")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key:"title", ascending:true)]
        do {
            let results =  try coreDataMgr.mainMoc.executeFetchRequest(fetchRequest)
            let books = results as! [Book]
            for book in books {
                print(book.title!)
                charCount += book.title!.characters.count
            }
            let updateCount = (charCount - books.count * 7) / 2
            return updateCount
        }
        catch let error as NSError {
            print("showBooks error: \(error), \(error.userInfo)")
            return 0
        }
    }
    private func deleteAllBooks(completion:(bSuccess:Bool) -> Void) {
        let fetchRequest = NSFetchRequest(entityName:"Book")
        do {
            let backgroundMoc = coreDataMgr.temporaryBackgroundMOC(name: "DeleteBooks")
            let results =  try backgroundMoc.executeFetchRequest(fetchRequest)
            let books = results as! [Book]
            for book in books {
                backgroundMoc.deleteObject(book)
            }
            try backgroundMoc.save()
            print("Deleted [\(books.count)] books.")
            completion(bSuccess: true)
        }
        catch let error as NSError {
            print("deleteAll error: \(error), \(error.userInfo)")
            completion(bSuccess: false)
        }
    }
//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        self.measureBlock {
//            // Put the code you want to measure the time of here.
//        }
//    }
}







