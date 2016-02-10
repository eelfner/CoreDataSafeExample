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

enum BackgroundDaemonState {case Stopped, Running, Stoping}

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate {

    private let coreDataSafe = CoreDataSafe(dbName: "Books")
    
    private let operationQueue = NSOperationQueue()
    private var operationThreadCount = 0
    private var operationSpeed = 0
    private var operationUpdateUI = true
    
    private var logTimer:NSTimer!
    private var logTimerEvents = 0
    
    @IBOutlet weak var tableView:UITableView!
    @IBOutlet weak var booksLabel:UILabel!
    @IBOutlet weak var notesLabel:UILabel!
    @IBOutlet weak var threadSegmentedControl: UISegmentedControl!
    @IBOutlet weak var speedSegmentedControl: UISegmentedControl!
    
    lazy private var fetchedResultsController: NSFetchedResultsController = self.currentFetchResultsController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        logTimer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: "logTimerAction", userInfo: nil, repeats: true)
        
        resetAction()
        self.runBackgroundDaemon()
    }

    // Force Settings to always show as Popover, even on iPhone because we like it that way.
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Simple class for
        if segue.identifier == "ShowInfo" {
            let popoverViewController = segue.destinationViewController
            popoverViewController.modalPresentationStyle = UIModalPresentationStyle.Popover
            popoverViewController.popoverPresentationController!.delegate = self
        }
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
    func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]? {
        return fetchedResultsController.sectionIndexTitles
    }
    func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        return fetchedResultsController.sectionForSectionIndexTitle(title, atIndex: index)
    }
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        tableView.beginUpdates()
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        tableView.endUpdates()
    }
    
    func controller(controller:NSFetchedResultsController, didChangeObject anObject:AnyObject, atIndexPath indexPath:NSIndexPath?, forChangeType type:NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch(type) {
        case .Insert:
            if let newIndexPath = newIndexPath {
                tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation:.Fade)
            }
        case .Delete:
            if let indexPath = indexPath {
                tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation:.Fade)
            }
        case .Update:
            if let indexPath = indexPath, cell = tableView.cellForRowAtIndexPath(indexPath) {
                configureCell(cell, indexPath:indexPath)
            }
        case .Move:
            if let indexPath = indexPath, newIndexPath = newIndexPath {
                tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation:.Fade)
                tableView.insertRowsAtIndexPaths([newIndexPath], withRowAnimation:.Fade)
                
            }
        }
    }
    
    func controller(controller:NSFetchedResultsController, didChangeSection sectionInfo:NSFetchedResultsSectionInfo, atIndex sectionIndex:Int, forChangeType type:NSFetchedResultsChangeType) {
        switch(type) {
        case .Insert:
            tableView.insertSections(NSIndexSet(index:sectionIndex), withRowAnimation:.Fade)
            
        case .Delete:
            tableView.deleteSections(NSIndexSet(index:sectionIndex), withRowAnimation: .Fade)
        default:
            break
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
        let threadCount = kThreadSelections[segmentedControl.selectedSegmentIndex]
        resetBackgroundDaemon(threadCount, completion: nil)
    }
    @IBAction func speedSegChanged(speedSegControl: UISegmentedControl) {
        operationSpeed = speedSegControl.selectedSegmentIndex
        // will be picked up automatically by backgroundDaemon
    }
    
    @IBAction func resetAction() {
        threadSegmentedControl.selectedSegmentIndex = 0
        resetBackgroundDaemon(0) {
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
    
    // MARK - BackgroundDaemon
    
    //Runs continuously - A curious path led me to this implementation. NSTimers need a run loop which is usually the
    //  main run loop. The timers were calling a selector (@objc func) here, but that would interfer with 
    //  NSOperationQueue.waitUntilAllOperationsAreFinished() also running on the main thread.
    private func runBackgroundDaemon() {
        let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(backGroundQueue) {
            NSThread.currentThread().name = "BackgroundDaemon"
            while (true) {
                while (self.operationQueue.operationCount < self.operationThreadCount) {
                    self.operationQueue.maxConcurrentOperationCount = self.operationThreadCount
                    let op = NSBlockOperation()
                    op.qualityOfService = .Background
                    op.queuePriority = .Normal
                    op.addExecutionBlock() { self.updateRandomBookInBackground() }
                    self.operationQueue.addOperation(op)
                }

                let sleepTimes = [0.5, 0.1, 0.05]
                let sleepTimeIndex = min(sleepTimes.count - 1, max(0, self.operationSpeed)) // 0...2
                let sleepTime = sleepTimes[sleepTimeIndex]

                NSThread.sleepForTimeInterval(sleepTime)
            }
        }
    }
    private func resetBackgroundDaemon(operationCount:Int, completion:(()->())? = nil) {
        let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(backGroundQueue) {
            NSThread.currentThread().name = "BackgroundReset"
            self.operationThreadCount = 0 // Stop filling
            self.operationQueue.cancelAllOperations()
            self.operationQueue.waitUntilAllOperationsAreFinished()
            
            self.operationThreadCount = operationCount // Restart filling
            if (completion != nil) {
                completion!()
            }
        }
    }
    func logTimerAction() {
        let speed = ["Slow","Mod","Fast"][operationSpeed]
        notesLabel.text = "\(operationThreadCount)T@\(speed): \(logTimerEvents) events/sec"
        booksLabel.text = "Books: \(self.fetchedResultsController.fetchedObjects?.count ?? 0)"
        logTimerEvents = 0
    }
    // MARK: - Helpers
    
    private func updateRandomBookInBackground() {
        let iRand = Int(arc4random_uniform(4))
        switch (iRand) {
        case 0: addRandomBookInBackground()
        case 1: deleteRandomBookInBackground()
        default: updateRandomBookTitle()
        }
    }
    private func updateRandomBookTitle() {
        //print(__FUNCTION__)
        let backgroundMoc1 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundUpdate")
        
        let fetchRequest1 = NSFetchRequest(entityName:"Book")
        do {
            let results =  try backgroundMoc1.executeFetchRequest(fetchRequest1)
            let books = results as! [Book]
            if books.count > 0 {
                let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
                if randomIndex < books.count {
                    let randomBook = books[randomIndex]
                    
                    let randomSize = 1 + Int(arc4random_uniform(UInt32(6)))
                    randomBook.comment = randomWordPhraseOfLength(randomSize)
                    try backgroundMoc1.save()
                    //print("updateRandomBookInBackground book: \(randomBook.title)")
                }
            }
        }
        catch let error as NSError {
            print("updateRandomBookInBackground error: \(error), \(error.userInfo)")
        }
        ++logTimerEvents
    }
    private func deleteRandomBookInBackground() {
        //print(__FUNCTION__)
        let backgroundMoc2 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundDelete")
        
        let fetchRequest2 = NSFetchRequest(entityName:"Book")
        do {
            let results =  try backgroundMoc2.executeFetchRequest(fetchRequest2)
            let books = results as! [Book]
            if books.count > 0 {
                let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
                let randomBook = books[randomIndex]
                backgroundMoc2.deleteObject(randomBook)
                try backgroundMoc2.save()
                //print("book[\(randomIndex)] deleted")
            }
        }
        catch let error as NSError {
            print("runBookUpdates error: \(error), \(error.userInfo)")
        }
    }
    private func addRandomBookInBackground() {
        //print(__FUNCTION__)
        let backgroundMoc2 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundAdd")
        
        let fetchRequest2 = NSFetchRequest(entityName:"Author")
        do {
            let results =  try backgroundMoc2.executeFetchRequest(fetchRequest2)
            let authors = results as! [Author]
            
            if authors.count > 0 {
                let randomIndex = Int(arc4random_uniform(UInt32(authors.count)))
                let randomAuthor = authors[randomIndex]
                
                let titleWordCount = 2 + Int(arc4random_uniform(UInt32(4)))
                let book:Book = coreDataSafe.createEntity(backgroundMoc2)
                book.title = randomWordPhraseOfLength(titleWordCount).capitalizedString
                book.comment = randomWordPhraseOfLength(6 + titleWordCount)
                book.author = randomAuthor
                book.pageCount = NSNumber(unsignedInt: 100 + arc4random_uniform(UInt32(500)))
                try backgroundMoc2.save()
                //print("book[\(book.title)] added for \(randomAuthor.name)")
            }
        }
        catch let error as NSError {
            print("addRandomBookInBackground error: \(error), \(error.userInfo)")
        }
    }

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
        for _ in 0 ..< authorBookCount {
            books.append(createTestBook(author))
        }
        author.books = NSOrderedSet(array:books)
        coreDataSafe.saveMainMocAsync()
        return author
    }
    private func createTestBook(forAuthor:Author) -> Book {
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
extension ViewController : UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyleForPresentationController(controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.None
    }
    func popoverPresentationControllerDidDismissPopover(popoverPresentationController: UIPopoverPresentationController) {
    }
}






















