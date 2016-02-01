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
private let kTestBooksWords = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur Excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum".characters.split(" ").map(String.init)

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate {

    private let cdSafe = CoreDataSafe(dbName: "Books")
    //private var authors : [Author]!

    @IBOutlet weak var tableView:UITableView!
    
    lazy private var fetchedResultsController: NSFetchedResultsController = self.currentFetchResultsController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        //authors = createTestAuthors()
        try! fetchedResultsController.performFetch()
    }

    // MARK: - UITableViewDelegate and DataSource
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        if let sections = fetchedResultsController.sections {
            return sections.count
        }
        return 0
    }
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = fetchedResultsController.sections {
            let sectionInfo = sections[section]
            return sectionInfo.numberOfObjects
        }
        return 0
    }
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if let sections = fetchedResultsController.sections {
            let currentSection = sections[section]
            return currentSection.name
            //return (author.name ?? "") + " - \(author.books!.count)"
        }
        
        return nil
    }
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("cell")!
        configureCell(cell, indexPath:indexPath)
        return cell
    }
    func configureCell(cell:UITableViewCell, indexPath: NSIndexPath) {
        let book = fetchedResultsController.objectAtIndexPath(indexPath) as! Book
        
        cell.textLabel?.text = book.title
        cell.detailTextLabel?.text = "\(book.pageCount!)pp: " + (book.comment ?? "")
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
            case .Delete: tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
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
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest:fetchRequest, managedObjectContext:self.cdSafe.mainMoc, sectionNameKeyPath:"author.name", cacheName:nil)
        
        fetchedResultsController.delegate = self
        
        return fetchedResultsController
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
        let author = cdSafe.createEntity("Author") as! Author
        author.name = name
        cdSafe.saveMainMocAsync()
        
        var books = [Book]()
        let authorBookCount = 1 + Int(arc4random_uniform(UInt32(6)))
        for iBook in 0 ..< authorBookCount {
            books.append(createTestBook(iBook, forAuthor:author))
        }
        author.books = NSOrderedSet(array:books)
        cdSafe.saveMainMocAsync()
        return author
    }
    private func createTestBook(iBook:Int, forAuthor:Author) -> Book {
        let titleWordCount = 2 + Int(arc4random_uniform(UInt32(4)))
        
        let book = cdSafe.createEntity("Book") as! Book
        book.title = randomWordPhraseOfLength(titleWordCount).capitalizedString
        book.comment = randomWordPhraseOfLength(6 + titleWordCount)
        book.author = forAuthor
        book.pageCount = NSNumber(unsignedInt: 100 + arc4random_uniform(UInt32(500)))
        cdSafe.saveMainMocAsync()
        
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























