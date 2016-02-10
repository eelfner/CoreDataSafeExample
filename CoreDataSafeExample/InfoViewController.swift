//
//  InfoViewController.swift
//  CoreDataSafeExample
//
//  Created by Eric Elfner on 2016-02-10.
//  Copyright © 2016 Eric Elfner. All rights reserved.
//
// Popover on iPhone
//
// 1. preferredContentSize = CGSizeMake(300, 300)                        (here)
// 2. override func prepareForSegue                                      (see ViewController)
// 3. extension ViewController : UIPopoverPresentationControllerDelegate (see ViewController)

import UIKit

class InfoViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        preferredContentSize = CGSizeMake(300, 300)
    }
    @IBAction func exitAction(sender: AnyObject) {
        presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
    }
}
