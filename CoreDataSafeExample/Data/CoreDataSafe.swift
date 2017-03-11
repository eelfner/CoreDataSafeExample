//
//  CoreDataMgr.swift
//  Fliptop
//
//  Created by Eric Elfner on 2015-11-25.
//  Copyright © 2015 Eric Elfner. All rights reserved.
//
/**
 This "Core Data Stack" is inspired by Marcus Zarra (http://martiancraft.com/blog/2015/03/core-data-stack/)
 and work done by Big Nerd Ranch https://www.bignerdranch.com/blog/introducing-the-big-nerd-ranch-core-data-stack/.
 The BNR work seems to me to be way over the top and uses more complex Swift idioms than is necessary.
 This class attempts to follow Zarra's words of wisdom, but make the coding as simple as possible.
 
 My belief is that 98% of iOS Apps only need this level of complexity.

 Overview: PSC 
              ↖︎privateMOC
                    ↖︎mainMOC (UI+quick ops)
                         ↖︎ tempBackgroundMOC1 (No UI)
                         ↖︎ tempBackgroundMOC2 (No UI)
                         ↖︎ ...

 The main tenets of this code as I see them are:
   - The privateMOC is just for persisting to disk in the background.
   - The mainMoc is Source of Truth and should be connected to the UI.
   - New temporaryBackgroundMOCs should be used for all background code based data manipulation.
   - Merge by MergeByPropertyObjectTrumpMergePolicyType, so no errors, last update (by field) wins.
   - The mainMoc and temporaryBackgroundMOCs automatically trigger saves all the way to the PSC.
   - No CoreData errors... well you still need to handle objects on the right threads.
   - Ability to add single global error handler to allow notify user in cases of rare unexpected errors.

 Overview:
  - Only 4 public access points:
    - init() Creates and Sqlite backed data source with the mainMoc.
    - mainMoc The main object context that runs on the main thread. Use for UI and quick operations.
    - temporaryBackgroundMOC() Creates a background moc for use on background threads.
    - createEntity() Helper method to create new entities. Not required.
    - saveMainMocAsync() Helper method to allow easy async saves and either global or no error handling.

 Simple Usage:
 let coreDataSafe = CoreDataSafe(dbName:"MyModel")
 let book:Book = coreDataSafe.createEntity()
 book.title = "The World According to Garp"
 coreDataSafe.saveMainMocAsync()

let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName:"Book")
let results = try! coreDataSafe.mainMoc.fetch(fetchRequest)

DispatchQueue.global(qos: .background).async {
    let backgroundMoc = coreDataSafe.temporaryBackgroundMOC(name:"T")
    
    let fetchRequest = NSFetchRequest<Book>(entityName:"Book")
    do {
        let books = try backgroundMoc.executeFetchRequest(fetchRequest)
        ...
        //background updates
        try backgroundMoc.save()
    }
    catch {
        print("runBookUpdates error: \(error)")
    }
}
*/

// Notes:
//  - Needs testing and work on migrations.
//  - Failed migrations can result in: "autolayout engine from a background thread" errors because ???
//  - MZ suggests error handling is over the top. The globalErrorHandler was added to be able allow the trapping of unforeseen untested errors rather than just swallowing them or crashing.
//  - MZ also points out that the dispatch_async(dispatch_get_main_queue()) is unnecessary in saveMainMocAsync as the save operation will be carried out in the thread that created the context which is the main thread. I would remove, but since the error handlers are still there, I want to be ensured that they will be called on the main thread, so I have left it for now.

import Foundation
import CoreData

public class CoreDataSafe {
    
    private(set) public var mainMoc: NSManagedObjectContext
    private let privateMoc: NSManagedObjectContext
    private let storeFileURL: NSURL
    private var globalErrorHandler:((Error, String)-> ())? = nil
    
    init(dbName:String, bundle:Bundle = Bundle.main, errorHandler:((Error, String) -> Void)? = nil, completion:(() -> Void)? = nil) {
    
        globalErrorHandler = errorHandler // Save global handler if there is one
        
        let modelURL = bundle.url(forResource: dbName, withExtension:"momd")
        assert(modelURL != nil, "CoreDataMgr failed to find CoreData model: [\(dbName).momd].")

        let mom = NSManagedObjectModel(contentsOf: modelURL!)
        assert(mom != nil, "CoreDataMgr init failed for: \(modelURL). Check for correct model file name.")
        
        let psc = NSPersistentStoreCoordinator(managedObjectModel:mom!)
        
        privateMoc = NSManagedObjectContext(concurrencyType:.privateQueueConcurrencyType)
        privateMoc.persistentStoreCoordinator = psc
        
        let mainMoc = MainManagedObjectContext(concurrencyType:.mainQueueConcurrencyType)
        mainMoc.globalErrorHandler = globalErrorHandler // Share handler for background errors
        
        // Override default (NSErrorMergePolicy) policy. Last in (by field) wins. There may be cases where this is not acceptable and error handling logic is needed to handle merge errors.
        mainMoc.mergePolicy = NSMergePolicy(merge:.mergeByPropertyObjectTrumpMergePolicyType)
        mainMoc.parent = self.privateMoc // Saves flow up to parent
        self.mainMoc = mainMoc
        
        let docDir = FileManager.default.urls(for: .documentDirectory, in:.userDomainMask).first
        storeFileURL = NSURL(string: "\(dbName).sqlite", relativeTo: docDir)!
        
        // Create SQLite store in background and call completion
        DispatchQueue.global(qos: .background).async {
            do  {
                let lightweightMigration = [NSMigratePersistentStoresAutomaticallyOption:true, NSInferMappingModelAutomaticallyOption:true]
                try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName:nil, at:self.storeFileURL as URL, options:lightweightMigration)
                if completion != nil {
                    DispatchQueue.main.async {
                        completion!()
                    }
                }
            }
            catch {
                let msg = "CoreDataSafe.init:addPersistentStoreWithType() for [\(self.storeFileURL)] failed with error: [\(error)]"
                if let errorHandler = self.globalErrorHandler {
                    errorHandler(error, msg)
                }
                else {
                    print(msg)
                    fatalError(msg)
                }
            }
        }
    }
    func createEntity<T:NSManagedObject>(inContext:NSManagedObjectContext? = nil) -> T {
        
        let typeName = "\(T.self)"
        guard let entityDescription = NSEntityDescription.entity(forEntityName: typeName, in:mainMoc) else {
            fatalError("NSManagedObject named \(typeName) doesn't exist.")
        }
        let moc = inContext ?? mainMoc
        let any = NSManagedObject(entity:entityDescription, insertInto:moc)
        
        return any as! T
    }
    public func temporaryBackgroundMOC(name:String) -> NSManagedObjectContext {
        let moc = TemporaryBackgroundManagedObjectContext(concurrencyType:.privateQueueConcurrencyType)
        moc.mergePolicy = NSMergePolicy(merge:.mergeByPropertyObjectTrumpMergePolicyType)
        moc.parent = mainMoc
        moc.name = name
        
        return moc
    }
    // Convenience method. Async execution with optional errorHandler callback.
    // Could add completion handler, but maybe user should then just use coreDataSave.mainMoc.save()
    public func saveMainMocAsync(errorHandler:((Error) -> Void)? = nil) {
        DispatchQueue.main.async {
            do {
                try self.mainMoc.save()
            }
            catch {
                if let errorHandler = errorHandler {
                    errorHandler(error)
                }
                else {
                    let errorMsg = "CoreDataSafe.mainMoc.save() failed with error: [\(error)]"
                    
                    if let globalHandler = self.globalErrorHandler {
                        globalHandler(error, errorMsg)
                    }
                    else {
                        print(errorMsg)
                        assertionFailure(errorMsg)
                    }
                }
            }
        }
    }
    
    // Propogate save through to the private context. The Private context will be updated on the mainContext save,
    // but the propogation to the persistent store requires a save call on the privateMoc.
    private class MainManagedObjectContext : NSManagedObjectContext {
        
        fileprivate var globalErrorHandler:((Error, String) -> Void)? = nil
        
        override func save() throws {
            try super.save()
            
            if let privateMoc = parent {
                privateMoc.perform() { // Note: async
                    do {
                        try privateMoc.save()
                    }
                    catch {
                        let errorMsg = "CoreDataSafe.privateMoc.save() failed with error: [\(error)]"
                        if let handler = self.globalErrorHandler {
                            handler(error, errorMsg)
                        }
                        else {
                            print(errorMsg)
                            assertionFailure(errorMsg)
                        }
                    }
                }
            }
        }
    }
    // Propogate save through to the main context.
    private class TemporaryBackgroundManagedObjectContext : NSManagedObjectContext {
        override func save() throws {
            assert(self.concurrencyType == .privateQueueConcurrencyType, "Sanity check on TemporaryBackgroundManagedObjectContext")
            assert(self.parent is MainManagedObjectContext, "Sanity check on TemporaryBackgroundManagedObjectContext")
            
            try super.save() // Saves to MainMoc
            if let mainMoc = parent as? MainManagedObjectContext {
                
                var blockError:Error? = nil // Must capture error within block and pass out.
                
                mainMoc.performAndWait() {
                    do {
                        try mainMoc.save()
                    }
                    catch {
                        blockError = error
                    }
                }
                if let blockError = blockError {
                    throw blockError
                }
            }
        }
    }
}















