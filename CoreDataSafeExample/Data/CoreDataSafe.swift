//
//  CoreDataMgr.swift
//  Fliptop
//
//  Created by Eric Elfner on 2015-11-25.
//  Copyright © 2015 Eric Elfner. All rights reserved.
//
// This "Core Data Stack" is inspired by Marcus Zarra (http://martiancraft.com/blog/2015/03/core-data-stack/)
// and work done by Big Nerd Ranch https://www.bignerdranch.com/blog/introducing-the-big-nerd-ranch-core-data-stack/.
// The BNR work seems to me to be way over the top and uses more complex Swift idioms than is necessary.
// This class attempts to follow Zarra's words of wisdom, but make the coding as simple as possible.
//
// Overview: PSC 
//              ↖︎privateMOC
//                    ↖︎mainMOC (UI+quick ops)
//                         ↖︎ tempBackgroundMOC1 (No UI)
//                         ↖︎ tempBackgroundMOC2 (No UI)
//                         ↖︎ ...
//
// The main tenets of this code as I see them are:
//   - The privateMOC is just for persisting to disk in the background.
//   - The mainMoc is Source of Truth and should be connected to the UI.
//   - New temporaryBackgroundMOCs should be used for all background code based data manipulation.
//   - Merge by MergeByPropertyObjectTrumpMergePolicyType, so no errors, last update (by field) wins.
//   - The mainMoc and temporaryBackgroundMOCs automatically trigger saves all the way to the PSC.
//   -
//
// Overview:
//  - Only 4 public access points:
//    - init() Creates and Sqlite backed data source with the mainMoc.
//    - mainMoc The main object context that runs on the main thread. Use for UI and quick operations.
//    - temporaryBackgroundMOC() Creates a background moc for use on background threads.
//    - createEntity() Helper method to create new entities. Not required.
//    - saveMainMocAsync() Helper method to allow easy async saves and either global or no error handling.
//
// Simple Usage:
// let coreDataSafe = CoreDataSafe(dbName:"MyModel")
// let book:Book = coreDataSafe.createEntity("Book") as! Book
// book.title = "The World According to Garp"
// coreDataSafe.saveMainMocAsync()
//
//let fetchRequest = NSFetchRequest(entityName:"Book")
//let results = try! coreDataSafe.mainMoc.executeFetchRequest(fetchRequest)
//
//let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
//dispatch_async(backGroundQueue) {
//    let backgroundMoc = coreDataSafe.temporaryBackgroundMOC(name:"T")
//    
//    let fetchRequest = NSFetchRequest(entityName:"Book")
//    do {
//        let results =  try backgroundMoc.executeFetchRequest(fetchRequest)
//        let books = results as! [Book]
//        ...
//        //background updates
//        try backgroundMoc.save()
//    }
//    catch let error as NSError {
//        print("runBookUpdates error: \(error), \(error.userInfo)")
//    }
//}


// Notes:
//  - Needs testing and work on migrations.
//  - Failed migrations can result in: "autolayout engine from a background thread" errors because ???
//
import Foundation
import CoreData

public class CoreDataSafe {
    
    private(set) public var mainMoc: NSManagedObjectContext
    private let privateMoc: NSManagedObjectContext
    private let storeFileURL: NSURL
    private var globalErrorHandler:((error:NSError, msg:String)-> ())? = nil
    
    init(dbName:String, bundle:NSBundle = NSBundle.mainBundle(), errorHandler:((error:NSError, msg:String) -> ())? = nil, completion:(() -> ())? = nil) {
    
        globalErrorHandler = errorHandler // Save global handler if there is one
        
        let modelURL = bundle.URLForResource(dbName, withExtension:"momd")
        assert(modelURL != nil, "CoreDataMgr failed to find CoreData model: [\(dbName).momd].")

        let mom = NSManagedObjectModel(contentsOfURL:modelURL!)
        assert(mom != nil, "CoreDataMgr init failed for: \(modelURL). Check for correct model file name.")
        
        let psc = NSPersistentStoreCoordinator(managedObjectModel:mom!)
        
        privateMoc = NSManagedObjectContext(concurrencyType:.PrivateQueueConcurrencyType)
        privateMoc.persistentStoreCoordinator = psc
        
        let mainMoc = MainManagedObjectContext(concurrencyType:.MainQueueConcurrencyType)
        mainMoc.globalErrorHandler = globalErrorHandler // Share handler for background errors
        
        // Override default (NSErrorMergePolicy) policy. Last in (by field) wins. There may be cases where this is not acceptable and error handling logic is needed to handle merge errors.
        mainMoc.mergePolicy = NSMergePolicy(mergeType:.MergeByPropertyObjectTrumpMergePolicyType)
        mainMoc.parentContext = self.privateMoc // Saves flow up to parent
        self.mainMoc = mainMoc
        
        let docDir = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains:.UserDomainMask).first
        storeFileURL = NSURL(string: "\(dbName).sqlite", relativeToURL: docDir)!
        
        // Create SQLite store in background and call completion
        let backGroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(backGroundQueue) {
            do  {
                let lightweightMigration = [NSMigratePersistentStoresAutomaticallyOption:true, NSInferMappingModelAutomaticallyOption:true]
                try psc.addPersistentStoreWithType(NSSQLiteStoreType, configuration:nil, URL:self.storeFileURL, options:lightweightMigration)
                if completion != nil {
                    dispatch_async(dispatch_get_main_queue()) {
                        completion!()
                    }
                }
            }
            catch let error as NSError {
                let msg = "CoreDataSafe.init:addPersistentStoreWithType() for [\(self.storeFileURL)] failed with error: [\(error)]"
                if let errorHandler = self.globalErrorHandler {
                    errorHandler(error:error, msg:msg)
                }
                else {
                    print(msg)
                    fatalError(msg)
                }
            }
            catch {
                fatalError("CoreDataSafe.init:addPersistentStoreWithType failure unknown type")
            }
        }
    }
    func createEntity<T:NSManagedObject>() -> T {
        
        let typeName = "\(T.self)"
        guard let entityDescription = NSEntityDescription.entityForName(typeName, inManagedObjectContext:mainMoc) else {
            fatalError("NSManagedObject named \typeName) doesn't exist.")
        }
        let any = NSManagedObject(entity:entityDescription, insertIntoManagedObjectContext:mainMoc)
        
        return any as! T
    }
    public func temporaryBackgroundMOC(name name:String) -> NSManagedObjectContext {
        
        let moc = TemporaryBackgroundManagedObjectContext(concurrencyType:.PrivateQueueConcurrencyType)
        moc.mergePolicy = NSMergePolicy(mergeType:.MergeByPropertyObjectTrumpMergePolicyType)
        moc.parentContext = mainMoc
        moc.name = name
        
        return moc
    }
    // Convenience method. Async execution with optional errorHandler callback.
    // Could add completion handler, but maybe user should then just use coreDataSave.mainMoc.save()
    public func saveMainMocAsync(errorHandler:((error:NSError) -> Void)? = nil) {
        dispatch_async(dispatch_get_main_queue()) {
            do {
                try self.mainMoc.save()
            }
            catch let error as NSError {
                let errorMsg = "CoreDataSafe.mainMoc.save() failed with error: [\(error)]"
                if errorHandler != nil {
                    errorHandler!(error: error)
                }
                else if let handler = self.globalErrorHandler {
                    handler(error:error, msg:errorMsg)
                }
                else {
                    print(errorMsg)
                    assertionFailure(errorMsg)
                }
            }
        }
    }
    
    // Propogate save through to the private context. The Private context will be updated on the mainContext save,
    // but the propogation to the persistent store requires a save call on the privateMoc.
    private class MainManagedObjectContext : NSManagedObjectContext {
        
        private var globalErrorHandler:((error:NSError, msg:String)-> ())? = nil
        
        override func save() throws {
            try super.save()
            
            if let privateMoc = parentContext {
                privateMoc.performBlock() { // Note: async
                    do {
                        try privateMoc.save()
                    }
                    catch let error as NSError {
                        let errorMsg = "CoreDataSafe.privateMoc.save() failed with error: [\(error)]"
                        if let handler = self.globalErrorHandler {
                            handler(error:error, msg:errorMsg)
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
            assert(self.concurrencyType == .PrivateQueueConcurrencyType, "Sanity check on TemporaryBackgroundManagedObjectContext")
            assert(self.parentContext is MainManagedObjectContext, "Sanity check on TemporaryBackgroundManagedObjectContext")
            
            try super.save() // Saves to MainMoc
            if let mainMoc = parentContext as? MainManagedObjectContext {
                
                var blockError:NSError? = nil // Must capture error within block and pass out.
                
                mainMoc.performBlockAndWait() {
                    do {
                        try mainMoc.save()
                    }
                    catch let error as NSError {
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















