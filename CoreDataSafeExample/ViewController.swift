//
//  ViewController.swift
//  CoreDataSafeExample
//
//  Created by Eric Elfner on 2016-01-31.
//  Copyright © 2016 Eric Elfner. All rights reserved.
//

import UIKit
import CoreData

private let kTestAuthors = ["Joan Slater", "William Newman", "Ella Nash", "Penelope Bower", "Neil Cameron", "Patricia Murphy", "Vernon Rose", "Cary Hicks", "Edwin Osborne", "Jasmine Abbott", "Jared Collins"]
private let kMaxTestBooksPerAuthor = 5
private let kTestBooksWords = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum".characters.split(separator: " ").map(String.init)

enum BackgroundDaemonState {case stopped, running, stoping}

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate {

    fileprivate let coreDataSafe = CoreDataSafe(dbName: "Books")
    
    fileprivate let operationQueue = OperationQueue()
    fileprivate var operationThreadCount = 0
    fileprivate var operationSpeed = 0
    fileprivate var operationUpdateUI = true
    
    fileprivate var logTimer:Timer!
    fileprivate var logTimerEvents = 0
    
    @IBOutlet weak var tableView:UITableView!
    @IBOutlet weak var booksLabel:UILabel!
    @IBOutlet weak var notesLabel:UILabel!
    @IBOutlet weak var threadSegmentedControl: UISegmentedControl!
    @IBOutlet weak var speedSegmentedControl: UISegmentedControl!
    
    lazy fileprivate var fetchedResultsController: NSFetchedResultsController<Book> = self.currentFetchResultsController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        logTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(logTimerAction), userInfo: nil, repeats: true)
        
        resetAction()
        self.runBackgroundDaemon()
    }

    // Force Settings to always show as Popover, even on iPhone because we like it that way.
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Simple class for
        if segue.identifier == "ShowInfo" {
            let popoverViewController = segue.destination
            popoverViewController.modalPresentationStyle = UIModalPresentationStyle.popover
            popoverViewController.popoverPresentationController!.delegate = self
        }
    }

    // MARK: - UITableViewDelegate and DataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        var sectionCount = 0
        if let sections = fetchedResultsController.sections {
            sectionCount = sections.count
        }
        return max(1, sectionCount) // Never return 0 for section count
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var rowCount = 0
        if let sections = fetchedResultsController.sections {
            if section < sections.count {
                let sectionInfo = sections[section]
                rowCount = sectionInfo.numberOfObjects
            }
        }
        return rowCount
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var title = "No Books"
        if let sections = fetchedResultsController.sections {
            if section < sections.count {
                let currentSection = sections[section]
                title = currentSection.name
            }
        }
        return title
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")!
        configureCell(cell, indexPath:indexPath)
        return cell
    }
    func configureCell(_ cell:UITableViewCell, indexPath: IndexPath) {
        let book = fetchedResultsController.object(at: indexPath)
        cell.textLabel?.text = book.title
        cell.detailTextLabel?.text = "\(book.pageCount ?? 0)pp: " + (book.comment ?? "")
    }
    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return fetchedResultsController.sectionIndexTitles
    }
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return fetchedResultsController.section(forSectionIndexTitle: title, at: index)
    }
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
    
    func controller(_ controller:NSFetchedResultsController<NSFetchRequestResult>, didChange anObject:Any, at indexPath:IndexPath?, for type:NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch(type) {
        case .insert:
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with:.fade)
            }
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with:.fade)
            }
        case .update:
            if let indexPath = indexPath, let cell = tableView.cellForRow(at: indexPath) {
                configureCell(cell, indexPath:indexPath)
            }
        case .move:
            if let indexPath = indexPath, let newIndexPath = newIndexPath {
                tableView.deleteRows(at: [indexPath], with:.fade)
                tableView.insertRows(at: [newIndexPath], with:.fade)
                
            }
        }
    }
    
    func controller(_ controller:NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo:NSFetchedResultsSectionInfo, atSectionIndex sectionIndex:Int, for type:NSFetchedResultsChangeType) {
        switch(type) {
        case .insert:
            tableView.insertSections(IndexSet(integer:sectionIndex), with:.fade)
            
        case .delete:
            tableView.deleteSections(IndexSet(integer:sectionIndex), with: .fade)
        default:
            break
        }
    }
    
    fileprivate func currentFetchResultsController() -> NSFetchedResultsController<Book> {
        let fetchRequest = NSFetchRequest<Book>(entityName:"Book")
        let sortDescriptor = NSSortDescriptor(key:"author.name", ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest:fetchRequest, managedObjectContext:self.coreDataSafe.mainMoc, sectionNameKeyPath:"author.name", cacheName:nil)
        
        fetchedResultsController.delegate = self
        
        return fetchedResultsController
    }
    
    // MARK: - IBActions
    @IBAction func threadsSegChanged(_ segmentedControl: UISegmentedControl) {
        let kThreadSelections = [0, 1, 5, 10, 20]
        let threadCount = kThreadSelections[segmentedControl.selectedSegmentIndex]
        resetBackgroundDaemon(threadCount, completion: nil)
    }
    @IBAction func speedSegChanged(_ speedSegControl: UISegmentedControl) {
        operationSpeed = speedSegControl.selectedSegmentIndex
        // will be picked up automatically by backgroundDaemon
    }
    
    @IBAction func resetAction() {
        threadSegmentedControl.selectedSegmentIndex = 0
        resetBackgroundDaemon(0) {
            self.reset()
        }
    }
    fileprivate func reset() {
        fetchedResultsController.delegate = nil
        deleteAllBooks() {bSuccess in
            if bSuccess {
                DispatchQueue.main.async {
                    self.fetchedResultsController = self.currentFetchResultsController() // Moved before next (createTestAuthors) to prevent warning: "API Misues Attempt to serialize store access on non-owning coordinator"
                    let _ = self.createTestAuthors()
                    //try! self.fetchedResultsController.managedObjectContext.save()
                    try! self.fetchedResultsController.performFetch()
                    self.tableView.reloadData()
                }
            }
        }
    }
    @IBAction func uiSegOnAction(_ segmentedControl: UISegmentedControl) {
        operationUpdateUI = (segmentedControl.selectedSegmentIndex == 0)
    }
    
    // MARK - BackgroundDaemon
    
    //Runs continuously - A curious path led me to this implementation. NSTimers need a run loop which is usually the
    //  main run loop. The timers were calling a selector (@objc func) here, but that would interfer with 
    //  NSOperationQueue.waitUntilAllOperationsAreFinished() also running on the main thread.
    fileprivate func runBackgroundDaemon() {
        DispatchQueue.global(qos: .background).async {
            Thread.current.name = "BackgroundDaemon"
            while (true) {
                while (self.operationQueue.operationCount < self.operationThreadCount) {
                    self.operationQueue.maxConcurrentOperationCount = self.operationThreadCount
                    let op = BlockOperation()
                    op.qualityOfService = .background
                    op.queuePriority = .normal
                    op.addExecutionBlock() { self.updateRandomBookInBackground() }
                    self.operationQueue.addOperation(op)
                }

                let sleepTimes = [0.5, 0.1, 0.05]
                let sleepTimeIndex = min(sleepTimes.count - 1, max(0, self.operationSpeed)) // 0...2
                let sleepTime = sleepTimes[sleepTimeIndex]

                Thread.sleep(forTimeInterval: sleepTime)
            }
        }
    }
    fileprivate func resetBackgroundDaemon(_ operationCount:Int, completion:(()->())? = nil) {
        DispatchQueue.global(qos: .background).async {
            Thread.current.name = "BackgroundReset"
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
    
    fileprivate func updateRandomBookInBackground() {
        let iRand = Int(arc4random_uniform(4))
        switch (iRand) {
        case 0: addRandomBookInBackground()
        case 1: deleteRandomBookInBackground()
        default: updateRandomBookTitle()
        }
    }
    fileprivate func updateRandomBookTitle() {
        //print(__FUNCTION__)
        let backgroundMoc1 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundUpdate")
        
        let fetchRequest1 = NSFetchRequest<Book>(entityName:"Book")
        do {
            let books =  try backgroundMoc1.fetch(fetchRequest1)
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
        catch {
            print("updateRandomBookInBackground error: \(error)")
        }
        logTimerEvents += 1
    }
    fileprivate func deleteRandomBookInBackground() {
        //print(__FUNCTION__)
        let backgroundMoc2 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundDelete")
        
        let fetchRequest2 = NSFetchRequest<Book>(entityName:"Book")
        do {
            let books =  try backgroundMoc2.fetch(fetchRequest2)
            if books.count > 0 {
                let randomIndex = Int(arc4random_uniform(UInt32(books.count)))
                let randomBook = books[randomIndex]
                backgroundMoc2.delete(randomBook)
                try backgroundMoc2.save()
                //print("book[\(randomIndex)] deleted")
            }
        }
        catch {
            print("runBookUpdates error: \(error)")
        }
    }
    fileprivate func addRandomBookInBackground() {
        //print(__FUNCTION__)
        let backgroundMoc2 = coreDataSafe.temporaryBackgroundMOC(name:"T-BackgroundAdd")
        
        let fetchRequest2 = NSFetchRequest<Author>(entityName:"Author")
        do {
            let authors =  try backgroundMoc2.fetch(fetchRequest2)
            
            if authors.count > 0 {
                let randomIndex = Int(arc4random_uniform(UInt32(authors.count)))
                let randomAuthor = authors[randomIndex]
                
                let titleWordCount = 2 + Int(arc4random_uniform(UInt32(4)))
                let book:Book = coreDataSafe.createEntity(inContext: backgroundMoc2)
                book.title = randomWordPhraseOfLength(titleWordCount).capitalized
                book.comment = randomWordPhraseOfLength(6 + titleWordCount)
                book.author = randomAuthor
                book.pageCount = NSNumber(value: 100 + arc4random_uniform(UInt32(500)) as UInt32)
                try backgroundMoc2.save()
                //print("book[\(book.title)] added for \(randomAuthor.name)")
            }
        }
        catch {
            print("addRandomBookInBackground error: \(error)")
        }
    }

    fileprivate func deleteAllBooks(_ completion:(_ bSuccess:Bool) -> Void) {
        let fetchRequest = NSFetchRequest<Book>(entityName:"Book")
        do {
            let backgroundMoc = coreDataSafe.temporaryBackgroundMOC(name: "DeleteAll")
            let books =  try backgroundMoc.fetch(fetchRequest)
            for book in books {
                backgroundMoc.delete(book)
            }
            try backgroundMoc.save()
            print("Deleted [\(books.count)] books.")
            
            let fetchRequest2 = NSFetchRequest<Author>(entityName:"Author")
            let authors =  try backgroundMoc.fetch(fetchRequest2)
            for author in authors {
                backgroundMoc.delete(author)
            }
            try backgroundMoc.save()
            print("Deleted [\(authors.count)] authors.")
            
            completion(true)
        }
        catch {
            print("deleteAll error: \(error)")
            completion(false)
        }
    }
    class BackroundUpdateOperation : Operation {
        
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
    fileprivate func createTestAuthor(_ name:String) -> Author {
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
    fileprivate func createTestBook(_ forAuthor:Author) -> Book {
        let titleWordCount = 2 + Int(arc4random_uniform(UInt32(4)))
        
        let book:Book = coreDataSafe.createEntity()
        book.title = randomWordPhraseOfLength(titleWordCount).capitalized
        book.comment = randomWordPhraseOfLength(6 + titleWordCount)
        book.author = forAuthor
        book.pageCount = NSNumber(value: 100 + arc4random_uniform(UInt32(500)) as UInt32)
        coreDataSafe.saveMainMocAsync()
        
        return book
    }
    fileprivate func randomWordPhraseOfLength(_ length:Int) -> String {
        var words = [String]()
        for _ in 0 ..< length {
            let wordIndex = Int(arc4random_uniform(UInt32(kTestBooksWords.count)))
            words.append(kTestBooksWords[wordIndex])
        }
        let phrase = words.joined(separator: " ")
        return phrase
    }
}
extension ViewController : UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
    }
}






















