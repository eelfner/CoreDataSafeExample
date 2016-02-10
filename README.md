


This project contains a few different things, but the key class is CoreDataSafe. This is a simple CoreData stack (<200 lines of code) that enables effective and (almost) foolproof code to implement CoreData with both foreground and background operations. The rest of the project is just a demonstration of using it. The demo consists of 2 parts:

 1. The CoreDataTest target that demonstrates some usage and validates the operation of the stack.
 2. The iOS App that uses the CoreDataSafe to populate a TableView using an NSFectchResultsController while running background processes to update the data.



Notes:
 * NSFetchedResultsController is not informed of updates from background managed object contexts. This is standard CoreData. 
 * NSOperationQueue to run a bunch of updates
 * See the layout changes under rotation of iPhones. Views are repositioned to make best use of space.
