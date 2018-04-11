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

        let expectation = self.expectation(description: "setupSuccess")
        let testBundle = Bundle(for: CoreDataTests.self)
        coreDataMgr = CoreDataSafe(dbName:"TestModel", bundle:testBundle) {
             self.deleteAllBooks() { _ in expectation.fulfill() }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
}
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    func testCRUDOnMain() {
        let expectionCreate = expectation(description: "created")
        let expectionRead = expectation(description: "read")
        let expectionUpdate = expectation(description: "updated")
        let expectionDelete = expectation(description: "deleted")
        
        // Create
        let book:Book = coreDataMgr.createEntity()
        let time = Date().timeIntervalSince1970
        let title = "Title at \(time)"
        book.title = title
        XCTAssertNotNil(book)
        try! coreDataMgr.mainMoc.save()
        expectionCreate.fulfill()

        // Read
        let fetchRequest1 = NSFetchRequest<Book>(entityName:"Book")
        let titleSearchPredicate1 = NSPredicate(format:"title=%@", title)
        fetchRequest1.predicate = titleSearchPredicate1

        let results1 =  try! coreDataMgr.mainMoc.fetch(fetchRequest1)
        XCTAssert(results1.count == 1)
        let bookRead = results1[0]
        if bookRead.title == title { expectionRead.fulfill() }

        // Update
        let title2 = "\(title)2"
        bookRead.title = title2
        try! coreDataMgr.mainMoc.save()
        
        let fetchRequest2 = NSFetchRequest<Book>(entityName:"Book")
        let titleSearchPredicate2 = NSPredicate(format:"title=%@", title2)
        fetchRequest2.predicate = titleSearchPredicate2
        
        let results2 =  try! coreDataMgr.mainMoc.fetch(fetchRequest2)
        XCTAssert(results2.count == 1)
        let bookRead2 = results2[0]
        if bookRead2.title == title2 { expectionUpdate.fulfill() }
        
        // Delete
        coreDataMgr.mainMoc.delete(bookRead2)
        try! coreDataMgr.mainMoc.save()
        
        let results3 =  try! coreDataMgr.mainMoc.fetch(fetchRequest2)
        XCTAssert(results3.count == 0)
        expectionDelete.fulfill()
        
        waitForExpectations(timeout: 0, handler: nil) // Should all be synchronous
    }

    func testHammerCoreDataFromBackground() {
        // Configured for lots of contention on a few objects. Results in lost updates, but no errors. Per design.
        let MAX_BOOKS = 10     // Few books (like 10) will create a lot of contention (threads updating the same object at same time.
        let MAX_THREADS = 10   // More threads (like 10+) will create more contention.
        let MAX_OPS = 100      // More operations (like 100+) will create more contention.
        
        print("Testing with [\(MAX_BOOKS)] books, [\(MAX_THREADS)] worker threads running [\(MAX_OPS)] updates each.")
        
        for i in 0 ..< MAX_BOOKS {
            let book:Book = coreDataMgr.createEntity()
            book.title = "Book\(String(format: "%03d", i))"
        }
        try! coreDataMgr.mainMoc.save()
        print("Created [\(MAX_BOOKS)] books.")
        
        var delayNsec = 0
        let backGroundQueue = DispatchQueue.global(qos: .background)
        for j in 0 ..< MAX_THREADS {
            let expectation = self.expectation(description: "runBookUpdates\(j)Completed")
            delayNsec += Int(arc4random_uniform(UInt32(1_000_000))) // If you make this 100,000,000 you'll see many more updates.
            let delayTime = DispatchTime.now() + Double(Int64(delayNsec)) / Double(NSEC_PER_SEC)
            backGroundQueue.asyncAfter(deadline: delayTime) {
                self.runBookUpdates(j, maxOps:MAX_OPS)
                expectation.fulfill()
                print("\(expectation)")
            }
        }
        print("Started [\(MAX_THREADS)] update threads.")
        waitForExpectations(timeout: TimeInterval(max(10, MAX_THREADS * MAX_OPS / 100)) , handler: nil)
        let updates = showBooks()
        let maxUpdates = MAX_THREADS * MAX_OPS
        let missedUpdates = maxUpdates - updates
        print("Missed updates: \(missedUpdates)/\(maxUpdates)")
    }
    fileprivate func runBookUpdates(_ threadId:Int, maxOps:Int) {
        
        let moc = coreDataMgr.temporaryBackgroundMOC(name:"T\(threadId)")
        
        let fetchRequest = NSFetchRequest<Book>(entityName:"Book")
        do {
            let books =  try moc.fetch(fetchRequest)
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
        
        let expectionCreate = expectation(description: "created")
        // Note: update and delete expectations are created as optional so they can be removed after first encountered.
        var expectionUpdatePropogated:XCTestExpectation? = expectation(description: "expectionUpdatePropogated")
        var expectionDeletePropogated:XCTestExpectation? = expectation(description: "expectionDeletePropogated")
        let expectionCheckedAll = expectation(description: "expectionCheckedAll")
        
        // Create
        let book:Book = coreDataMgr.createEntity()
        let time = Date().timeIntervalSince1970
        let title = "Title at \(time)"
        book.title = title
        XCTAssertNotNil(book)
        try! coreDataMgr.mainMoc.save()
        expectionCreate.fulfill()
        
        // Setup intervals
        let delayMsecs:[Int64] = [0, 10, 1_000, 2_000, 3_000]
        let delayTimes = delayMsecs.map() { DispatchTime.now() + Double(Int64($0 * kNanoSecsPerMillisec)) / Double(NSEC_PER_SEC) }
        
        // Read at intervals
        let backGroundQueue = DispatchQueue.global(qos: .background)
        backGroundQueue.async {
            for delayTime in delayTimes {
                DispatchQueue.main.asyncAfter(deadline: delayTime) {
                    print("Delay:\(delayTime)ns - Book: \(book.title ?? "nil") hasMoc: \(book.managedObjectContext != nil)")
                    
                    // Check test expectations
                    if ((book.title?.contains("updated")) != nil) { expectionUpdatePropogated?.fulfill(); expectionUpdatePropogated = nil }
                    if (book.managedObjectContext == nil)          { expectionDeletePropogated?.fulfill(); expectionDeletePropogated = nil }
                    if delayTime == delayTimes.last                { expectionCheckedAll.fulfill() }
                }
            }
        }
        
        // Update in background
        let timeAfter1 = delayTimes[1] + Double(Int64(1 * kNanoSecsPerMillisec)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: timeAfter1) {
            self.updateRandomBookInBackground()
        }
        
        // Delete in background
        let timeAfter2 = delayTimes[2] + Double(Int64(1 * kNanoSecsPerMillisec)) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: timeAfter2) {
            self.deleteRandomBookInBackground()
        }

        waitForExpectations(timeout: 5, handler: nil) // Should all be synchronous
    }

    fileprivate func updateRandomBookInBackground() {
        let backgroundMoc1 = coreDataMgr.temporaryBackgroundMOC(name:"T-BackgroundUpdate")
        
        let fetchRequest1 = NSFetchRequest<Book>(entityName:"Book")
        do {
            let books =  try backgroundMoc1.fetch(fetchRequest1)
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
    fileprivate func deleteRandomBookInBackground() {
        let backgroundMoc2 = coreDataMgr.temporaryBackgroundMOC(name:"T-BackgroundDelete")
        
        let fetchRequest2 = NSFetchRequest<Book>(entityName:"Book")
        do {
            let books =  try backgroundMoc2.fetch(fetchRequest2)
            let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
            let randomBook = books[randomIndex]
            backgroundMoc2.delete(randomBook)
            try backgroundMoc2.save()
            print("book[\(randomIndex)] deleted")
        }
        catch let error as NSError {
            print("runBookUpdates error: \(error), \(error.userInfo)")
        }
        
    }
    // MARK: Helper methods
    fileprivate func showBooks() -> Int {
        var charCount = 0
        let fetchRequest = NSFetchRequest<Book>(entityName:"Book")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key:"title", ascending:true)]
        do {
            let books =  try coreDataMgr.mainMoc.fetch(fetchRequest)
            for book in books {
                print(book.title!)
                charCount += book.title!.count
            }
            let updateCount = (charCount - books.count * 7) / 2
            return updateCount
        }
        catch let error as NSError {
            print("showBooks error: \(error), \(error.userInfo)")
            return 0
        }
    }
    fileprivate func deleteAllBooks(_ completion:(_ bSuccess:Bool) -> Void) {
        let fetchRequest = NSFetchRequest<Book>(entityName:"Book")
        do {
            let backgroundMoc = coreDataMgr.temporaryBackgroundMOC(name: "DeleteBooks")
            let books = try backgroundMoc.fetch(fetchRequest)
            for book in books {
                backgroundMoc.delete(book)
            }
            try backgroundMoc.save()
            print("Deleted [\(books.count)] books.")
            completion(true)
        }
        catch let error as NSError {
            print("deleteAll error: \(error), \(error.userInfo)")
            completion(false)
        }
    }
//    func testPerformanceExample() {
//        // This is an example of a performance test case.
//        self.measureBlock {
//            // Put the code you want to measure the time of here.
//        }
//    }
}







