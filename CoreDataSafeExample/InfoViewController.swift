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
        preferredContentSize = CGSize(width: 300, height: 300)
    }
    @IBAction func exitAction(_ sender: AnyObject) {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
