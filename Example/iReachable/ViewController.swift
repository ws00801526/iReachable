//
//  ViewController.swift
//  iReachable
//
//  Created by ws00801526 on 11/23/2020.
//  Copyright (c) 2020 ws00801526. All rights reserved.
//

import UIKit
import iReachable
import CoreTelephony
import CoreLocation
import SystemConfiguration

class ViewController: UIViewController {

    var reachability: SCNetworkReachability?
//    var task = URLSession.shared.dataTask(with: .init(url: URL(string: "https://www.baidu.com")!))
    override func viewDidLoad() {
        super.viewDidLoad()
        
        try? IReachable.start { reachable in
            debugPrint("this is new state \(reachable.connection)")
        }
        
        debugPrint("this is initial state \(IReachable.shared.connection)")
        
        var zeroAddress = sockaddr()
        zeroAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zeroAddress.sa_family = sa_family_t(AF_INET)
        reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, &zeroAddress);
        
        NotificationCenter.default.addObserver(self, selector: #selector(viewDidAppear(_:)), name: .UIApplicationDidBecomeActive, object: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 13, *) {
            return .darkContent
        } else {
            return .default
        }
    }
    

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard let reachability = reachability else { return }
        var flags: SCNetworkReachabilityFlags = .init()
        SCNetworkReachabilityGetFlags(reachability, withUnsafeMutablePointer(to: &flags, { $0 }))
        debugPrint("蜂窝开关是否开启 \(flags.contains(.isWWAN) ? "YES" : "NO")")
        
        let info = CTTelephonyNetworkInfo()
        guard let currendRadios = info.currentRadioAccessTechnology else { return }
        debugPrint("蜂窝数据 \(currendRadios)")
    }
}
