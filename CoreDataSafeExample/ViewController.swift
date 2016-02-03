//
//  ViewController.swift
//  CoreDataSafeExample
//
//  Created by Eric Elfner on 2016-01-31.
//  Copyright © 2016 Eric Elfner. All rights reserved.
//

import UIKit
import CoreData

private let kTestAuthors = ["Joan Slater", "William Newman", "Ella Nash", "Penelope Bower", "Neil Cameron"]
private let kMaxTestBooksPerAuthor = 5
private let kTestBooksWords = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum".characters.split(" ").map(String.init)

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate {

    private let coreDataSafe = CoreDataSafe(dbName: "Books")
    
    private let operationQueue = NSOperationQueue()
    private var operationThreadCount = 0
    private var operationSpeed = 0
    private var operationUpdateUI = true
    
    private var logTimer:NSTimer!
    private var logTimerEvents = 0
    
    //private var authors : [Author]!

    @IBOutlet weak var tableView:UITableView!
    @IBOutlet weak var notesLabel: UILabel!
    @IBOutlet weak var threadSegmentedControl: UISegmentedControl!
    @IBOutlet weak var speedSegmentedControl: UISegmentedControl!
    
    lazy private var fetchedResultsController: NSFetchedResultsController = self.currentFetchResultsController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        logTimer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: "logTimerAction", userInfo: nil, repeats: true)
        
        // The standard for CoreData is that for performance reasons, background context updates that are propagated to the mainContext
        // does _not_ result in object faults.
        NSNotificationCenter.defaultCenter().addObserverForName(NSManagedObjectContextObjectsDidChangeNotification, object: nil, queue: nil) { notification in
            if self.operationUpdateUI {
                if let sourceContext = notification.object as? NSManagedObjectContext {
                    if sourceContext == self.coreDataSafe.mainMoc {
                        self.tableView.reloadData()
                    }
                }
            }
        }

        
        //authors = createTestAuthors()
        try! fetchedResultsController.performFetch()
    }

    // MARK: - UITableViewDelegate and DataSource
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        var sectionCount = 0
        if let sections = fetchedResultsController.sections {
            sectionCount = sections.count
        }
        return max(1, sectionCount) // Never return 0 for section count
    }
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var rowCount = 0
        if let sections = fetchedResultsController.sections {
            if section < sections.count {
                let sectionInfo = sections[section]
                rowCount = sectionInfo.numberOfObjects
            }
        }
        return rowCount
    }
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var title = "No Books"
        if let sections = fetchedResultsController.sections {
            if section < sections.count {
                let currentSection = sections[section]
                title = currentSection.name
            }
        }
        return title
    }
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("cell")!
        configureCell(cell, indexPath:indexPath)
        return cell
    }
    func configureCell(cell:UITableViewCell, indexPath: NSIndexPath) {
        let book = fetchedResultsController.objectAtIndexPath(indexPath) as! Book
        
        cell.textLabel?.text = book.title
        cell.detailTextLabel?.text = "\(book.pageCount ?? 0)pp: " + (book.comment ?? "")
    }
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        tableView.beginUpdates()
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        tableView.endUpdates()
    }
    
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        if let indexPath = newIndexPath {
            switch (type) {
            case .Insert: tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
            case .Delete:
                //if tableView.numberOfRowsInSection(indexPath.section) > 1 {
                    tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
                //}
                //else if tableView.numberOfSections > 1 { // Don't delete last section
                //    tableView.deleteSections(NSIndexSet(index: indexPath.section), withRowAnimation: .Fade)
                //}
            case .Update:
                let cell = tableView.cellForRowAtIndexPath(indexPath)!
                configureCell(cell, indexPath:indexPath)
            case .Move:
                tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
                
                if let newIndexPath = newIndexPath {
                    tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation: .Fade)
                }
            }
        }
    }
    
    private func currentFetchResultsController() -> NSFetchedResultsController {
        let fetchRequest = NSFetchRequest(entityName:"Book")
        let sortDescriptor = NSSortDescriptor(key:"author.name", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest:fetchRequest, managedObjectContext:self.coreDataSafe.mainMoc, sectionNameKeyPath:"author.name", cacheName:nil)
        
        fetchedResultsController.delegate = self
        
        return fetchedResultsController
    }
    
    // MARK: - IBActions
    @IBAction func threadsSegChanged(segmentedControl: UISegmentedControl) {
        let kThreadSelections = [0, 1, 5, 10, 20]
        operationThreadCount = kThreadSelections[segmentedControl.selectedSegmentIndex]
        
        updateBackgroundActivity()
    }
    @IBAction func speedSegChanged(speedSegControl: UISegmentedControl) {
        operationSpeed = speedSegControl.selectedSegmentIndex
        updateBackgroundActivity()
    }
    
    @IBAction func infoAction() {
    }
    
    @IBAction func resetAction() {
        threadSegmentedControl.selectedSegmentIndex = 0
        operationThreadCount = 0
        updateBackgroundActivity() {
            self.reset()
        }
    }
    private func reset() {
        fetchedResultsController.delegate = nil
        deleteAllBooks() {bSuccess in
            if bSuccess {
                dispatch_async(dispatch_get_main_queue()) {
                    self.createTestAuthors()
                    self.fetchedResultsController = self.currentFetchResultsController() 
                    try! self.fetchedResultsController.performFetch()
                    self.tableView.reloadData()
                }
            }
        }
    }
    @IBAction func uiSegOnAction(segmentedControl: UISegmentedControl) {
        operationUpdateUI = (segmentedControl.selectedSegmentIndex == 0)
    }
    private func updateBackgroundActivity(completionBlock: (() -> ())? = nil) {
        
        let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(backGroundQueue) {
            self.operationQueue.cancelAllOperations()
            print("Stopping background operations")
            self.operationQueue.waitUntilAllOperationsAreFinished()
            print("Background operations stopped")
            self.operationQueue.maxConcurrentOperationCount = self.operationThreadCount
            
            for _ in 0 ..< self.operationThreadCount {
                let op = NSBlockOperation()
                op.addExecutionBlock() { self.backgroundUpdateWithSpeedLevel(self.operationSpeed, inOperation:op) }
                self.operationQueue.addOperation(op)
            }
            if completionBlock != nil {
                completionBlock!()
            }
        }
    }
    private func backgroundUpdateWithSpeedLevel(iSpeed:Int, inOperation:NSOperation) {
        while (!inOperation.cancelled) {
            let sleepTimes = [0.5, 0.05, 0.001]
            let sleepTime = sleepTimes[min(sleepTimes.count - 1, max(0, iSpeed))]
            NSThread.sleepForTimeInterval(sleepTime)
            updateRandomBookInBackground()
        }
    }
    func logTimerAction() {
        let speed = ["Slow","Mod","Fast"][operationSpeed]
        notesLabel.text = "\(operationThreadCount)T@\(speed): \(logTimerEvents) events/sec"
        logTimerEvents = 0
    }
    // MARK: - Helpers
    
    private func updateRandomBookInBackground() {
        let backgroundMoc1 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundUpdate")
        
        let fetchRequest1 = NSFetchRequest(entityName:"Book")
        do {
            let results =  try backgroundMoc1.executeFetchRequest(fetchRequest1)
            let books = results as! [Book]
            
            let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
            if randomIndex < books.count {
                let randomBook = books[randomIndex]
                
                let randomSize = 1 + Int(arc4random_uniform(UInt32(6)))
                randomBook.comment = randomWordPhraseOfLength(randomSize)
                try backgroundMoc1.save()
                //print("updateRandomBookInBackground book: \(randomBook.title)")
            }
        }
        catch let error as NSError {
            print("updateRandomBookInBackground error: \(error), \(error.userInfo)")
        }
        ++logTimerEvents
    }
//    private func deleteRandomBookInBackground() {
//        let backgroundMoc2 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundDelete")
//        
//        let fetchRequest2 = NSFetchRequest(entityName:"Book")
//        do {
//            let results =  try backgroundMoc2.executeFetchRequest(fetchRequest2)
//            let books = results as! [Book]
//            
//            let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
//            let randomBook = books[randomIndex]
//            backgroundMoc2.deleteObject(randomBook)
//            try backgroundMoc2.save()
//            print("book[\(randomIndex)] deleted")
//        }
//        catch let error as NSError {
//            print("runBookUpdates error: \(error), \(error.userInfo)")
//        }
//        
//    }

    private func deleteAllBooks(completion:(bSuccess:Bool) -> Void) {
        let fetchRequest = NSFetchRequest(entityName:"Book")
        do {
            let backgroundMoc = coreDataSafe.temporaryBackgroundMOC(name: "DeleteAll")
            let results =  try backgroundMoc.executeFetchRequest(fetchRequest)
            let books = results as! [Book]
            for book in books {
                backgroundMoc.deleteObject(book)
            }
            try backgroundMoc.save()
            print("Deleted [\(books.count)] books.")
            
            let fetchRequest2 = NSFetchRequest(entityName:"Author")
            let results2 =  try backgroundMoc.executeFetchRequest(fetchRequest2)
            let authors = results2 as! [Author]
            for author in authors {
                backgroundMoc.deleteObject(author)
            }
            try backgroundMoc.save()
            print("Deleted [\(authors.count)] authors.")
            
            completion(bSuccess: true)
        }
        catch let error as NSError {
            print("deleteAll error: \(error), \(error.userInfo)")
            completion(bSuccess: false)
        }
    }
    class BackroundUpdateOperation : NSOperation {
        
    }
}
// MARK: - Test Data Creation
extension ViewController {
    func createTestAuthors() -> [Author] {
        var authors = [Author]()
        
        for iAuthor in kTestAuthors {
            authors.append(createTestAuthor(iAuthor))
        }
        return authors
    }
    private func createTestAuthor(name:String) -> Author {
        let author:Author = coreDataSafe.createEntity()
        author.name = name
        coreDataSafe.saveMainMocAsync()
        
        var books = [Book]()
        let authorBookCount = 1 + Int(arc4random_uniform(UInt32(kMaxTestBooksPerAuthor)))
        for iBook in 0 ..< authorBookCount {
            books.append(createTestBook(iBook, forAuthor:author))
        }
        author.books = NSOrderedSet(array:books)
        coreDataSafe.saveMainMocAsync()
        return author
    }
    private func createTestBook(iBook:Int, forAuthor:Author) -> Book {
        let titleWordCount = 2 + Int(arc4random_uniform(UInt32(4)))
        
        let book:Book = coreDataSafe.createEntity()
        book.title = randomWordPhraseOfLength(titleWordCount).capitalizedString
        book.comment = randomWordPhraseOfLength(6 + titleWordCount)
        book.author = forAuthor
        book.pageCount = NSNumber(unsignedInt: 100 + arc4random_uniform(UInt32(500)))
        coreDataSafe.saveMainMocAsync()
        
        return book
    }
    private func randomWordPhraseOfLength(length:Int) -> String {
        var words = [String]()
        for _ in 0 ..< length {
            let wordIndex = Int(arc4random_uniform(UInt32(kTestBooksWords.count)))
            words.append(kTestBooksWords[wordIndex])
        }
        let phrase = words.joinWithSeparator(" ")
        return phrase
    }
}























