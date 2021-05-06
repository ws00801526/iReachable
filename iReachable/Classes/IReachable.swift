//
//  iReachable.swift
//  iReachable
//
//  Created by XMFraker on 2020/11/23.
//

import Foundation
import CoreTelephony
import SystemConfiguration

public enum IReachableError: Error {
    case failedToCreateWithAddress(sockaddr, Int32)
    case unableToSetCallback(Int32)
    case unableToScheduleSCNetwork(Int32)
}

public class iReachable {

    public typealias Action = (iReachable) -> Void
    
    public static let shared = iReachable()
    public var notifyAction: Action? = nil
    public private(set) var isAutoAlertable: Bool = true
    public private(set) var connection: Connection = .offline
    public var isMonitoring: Bool {
        guard let _ = cellularData?.cellularDataRestrictionDidUpdateNotifier else { return false }
        guard let _ = reachability else { return false }
        return true
    }
    
    private lazy var alert: UIAlertController = {
        let alert = UIAlertController(title: "网络连接失败", message: nil, preferredStyle: .alert)
        alert.addAction(.init(title: "取消", style: .cancel, handler: dismissAlert(_:)))
        alert.addAction(.init(title: "设置", style: .default, handler: confirmAction(_:)))
        alert.preferredAction = alert.actions.last
        return alert
    }()
    private var cellularData: CTCellularData?
    private var reachability: SCNetworkReachability?
        
    deinit {
        stopNotifier()        
    }
}

public extension Notification.Name {
    static let IReachableStateDidChanged: Notification.Name = .init("iReachable.State.DidChanged")
}

extension iReachable.Connection : CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .offline: return "offline"
        case .online(let cellular): return "online with \(cellular.rawValue)"
        case .restricted: return "offline because restricted"
        }
    }
}

extension iReachable : CustomStringConvertible {
    
    public enum Connection {
        /// Network is available
        case online(Cellular)
        /// User should access WLAN or CellularData
        case restricted
        /// User disabled WiFi & Cellular
        case offline
    }
    
    public enum Cellular: String {
        case unknown
        case iWiFi  = "WiFi"
        case i2G    = "2G"
        case i3G    = "3G"
        case i4G    = "4G"
        case i5G    = "5G"
        
        static let i2GValues = [CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyCDMA1x]
        static let i3GValues = [CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSUPA,
                                CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB,
                                CTRadioAccessTechnologyeHRPD]
        static let i4GValues = [CTRadioAccessTechnologyLTE]
                
        @available(iOS 14.1, *)
        static let i5GValues = [CTRadioAccessTechnologyNRNSA, CTRadioAccessTechnologyNR]
        static let i5GValuesPre = ["CTRadioAccessTechnologyNRNSA", "CTRadioAccessTechnologyNR"]
    }
    
    public class func start(_ action: Action? = nil) throws {
        shared.notifyAction = action
        try shared.setup().startNotifier()
    }
    
    public class func stop() {
        shared.stopNotifier()
    }
    
    public class func setAutoAlert(enabled: Bool) {
        shared.isAutoAlertable = enabled
    }
    
    public var description: String { return connection.description }
}

fileprivate extension iReachable {
    
    var currentCellular: Cellular {
        
        func transWWAN(of radio: String) -> Cellular {
            
            if #available(iOS 14.1, *), Cellular.i5GValues.contains(radio) { return .i5G }
            else if Cellular.i5GValuesPre.contains(radio) { return .i5G }
            
            switch radio {
            case let item where Cellular.i2GValues.contains(item): return .i2G
            case let item where Cellular.i3GValues.contains(item): return .i3G
            case let item where Cellular.i4GValues.contains(item): return .i4G
            default: return .unknown
            }
        }
        
        guard isCellularLinked else { return .unknown }
        
        let info = CTTelephonyNetworkInfo()
        if #available(iOS 12, *) {
            if let currendRadios = info.serviceCurrentRadioAccessTechnology?.values {
                for currentRadio in currendRadios {
                    let theWWAN = transWWAN(of: currentRadio)
                    if theWWAN == .unknown { continue }
                    else { return theWWAN }
                }
            }
        } else {
            if let currendRadio = info.currentRadioAccessTechnology { return transWWAN(of: currendRadio) }
        }
        
        return .unknown
    }

    var isNetworkReachable: Bool {
        guard let reachability = reachability else { return false }
        var flags: SCNetworkReachabilityFlags = .init()
        SCNetworkReachabilityGetFlags(reachability, withUnsafeMutablePointer(to: &flags, { $0 }))
        return flags.contains(.reachable)
    }
    
    var isWLANLinked: Bool {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return false }
        defer { freeifaddrs(interfaces) }
        
        var tempInterface = interfaces
        while let interface = tempInterface {
            let name = String(cString: interface.pointee.ifa_name)
            if name == "en0" {
                var addr = interface.pointee.ifa_addr.pointee
                switch Int32(addr.sa_family) {
                case AF_INET, AF_INET6:
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&addr, socklen_t(addr.sa_len), &host, socklen_t(host.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        if let address = String(validatingUTF8: host), !address.isEmpty { return true }
                    }
                default: break
                }
            }
            tempInterface = interface.pointee.ifa_next
        }
        return false
    }
    
    var isCellularLinked: Bool {
        guard let reachability = reachability else { return false }
        var flags: SCNetworkReachabilityFlags = .init()
        SCNetworkReachabilityGetFlags(reachability, withUnsafeMutablePointer(to: &flags, { $0 }))
        return flags.contains(.isWWAN)
    }
    
    /// Check is this app first launch
    var isFirstRun: Bool {
        let hasFirshRunFlag = UserDefaults.standard.bool(forKey: "iReachable.first.run.flag")
        if !hasFirshRunFlag { UserDefaults.standard.set(true, forKey: "iReachable.first.run.flag"); UserDefaults.standard.synchronize() }
        return !hasFirshRunFlag
    }
    
}

extension iReachable {
    
    func setup() throws -> Self {
             
        // 1. Create Reachability to check network is available
        var zeroAddress = sockaddr()
        zeroAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zeroAddress.sa_family = sa_family_t(AF_INET)
        reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, &zeroAddress);
        guard let _ = reachability else { throw IReachableError.failedToCreateWithAddress(zeroAddress, SCError()) }

        // 2. Create CellularData to check restrictedState of Cellular
        cellularData = .init()
        
        // 3. Get current state
        if isNetworkReachable {
            if isWLANLinked { connection = .online(.iWiFi) }
            else { connection = .online(currentCellular) }
        } else {
            if (isWLANLinked || isCellularLinked) { connection = .restricted }
            else { connection = .offline }
        }
        
        return self
    }
}

// MARK: - Notifier

extension iReachable {
    
    func startNotifier() throws {
        try startReachabilityNotifier()
        try startCellularDataNotifier()
    }
    
    func stopNotifier() {
        
        cellularData?.cellularDataRestrictionDidUpdateNotifier = nil
        
        if let reachability = reachability {
            SCNetworkReachabilitySetCallback(reachability, nil, nil)
            SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
    }
    
    func startReachabilityNotifier() throws {
        
        guard let reachability = reachability else { return }

        let callBack: SCNetworkReachabilityCallBack = { _, flags, info in
            guard let info = info else { return }
            let wReachable = Unmanaged<IReachableWeakify>.fromOpaque(info).takeUnretainedValue()
            guard let reachable = wReachable.associateObj else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: reachable.notifyIfNeeded)
        }
        
        let wReachable: IReachableWeakify = .init(weakObj: self)
        let opaqueWeakReachable = Unmanaged<IReachableWeakify>.passUnretained(wReachable).toOpaque()
        
        var context = SCNetworkReachabilityContext(version: 0, info: UnsafeMutableRawPointer(opaqueWeakReachable)) {
            let unmanagedWeakifiedReachability = Unmanaged<IReachableWeakify>.fromOpaque($0)
            _ = unmanagedWeakifiedReachability.retain()
            return UnsafeRawPointer(unmanagedWeakifiedReachability.toOpaque())
        } release: {
            let unmanagedWeakifiedReachability = Unmanaged<IReachableWeakify>.fromOpaque($0)
            unmanagedWeakifiedReachability.release()
        } copyDescription: {
            let unmanagedWeakifiedReachability = Unmanaged<IReachableWeakify>.fromOpaque($0)
            let weakifiedReachability = unmanagedWeakifiedReachability.takeUnretainedValue()
            let description = weakifiedReachability.associateObj?.description ?? "nil"
            return Unmanaged.passRetained(description as CFString)
        }
                
        if !SCNetworkReachabilitySetCallback(reachability, callBack, &context) {
            stopNotifier()
            throw IReachableError.unableToSetCallback(SCError())
        }

        if !SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) {
            stopNotifier()
            throw IReachableError.unableToScheduleSCNetwork(SCError())
        }
    }
    
    func startCellularDataNotifier() throws {
        guard let cellularData = cellularData else { return }
        cellularData.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            guard let `self` = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: self.notifyIfNeeded)
        }
    }
}

// MARK: -

extension iReachable {
        
    func notifyIfNeeded() {
        
        func notify(_ state: Connection) {
                    
            guard self.connection != state else { return }
            self.connection = state

            if isAutoAlertable {
                if case .online = state { dismissAlert(.init()) }
                else { showAlert() }
            }
            
            if let action = notifyAction { action(self) }
            NotificationCenter.default.post(name: .IReachableStateDidChanged, object: self)
        }

        // 1. check is network available,  if network is available the state should be reached
        if isNetworkReachable { return notify(.online(isWLANLinked ? .iWiFi : currentCellular)) }
        // 2. check cellularData.restrictedState
        guard let cellularData = cellularData else { return }
        switch cellularData.restrictedState {
        case .notRestricted:
            // The WLAN & CellularData is accessed
            notify(.offline)
        case .restricted:
            // check again if the state is restricted
            // * WiFi (✅)                    --> None    -->   .restricted
            // * WiFi (❎) Cellular(✅)       --> WLAN    -->   .restricted
            // * WiFi (❎) Cellular(✅)       --> None    -->   .restricted
            // * WiFi Cellular (❎)           --> WLAN    -->   .offline
            // * WiFi Cellular (❎)           --> None    -->   .offline
            notify((isWLANLinked || isCellularLinked) ? .restricted : .offline)
        case .restrictedStateUnknown:
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: notifyIfNeeded)
        @unknown default: break
        }
    }
}

// MARK: - Alert
extension iReachable {
    
    /// Get the controller to present the alert controller.
    var visibleController: UIViewController? {
        guard let root = UIApplication.shared.keyWindow?.rootViewController else { return nil }
        guard let _ = root.presentedViewController else { return root }
        var presented: UIViewController? = root.presentedViewController
        while presented != nil {
            if let otherPresented = presented?.presentedViewController { presented = otherPresented }
            else { break }
        }
        return presented
    }
    
    func showAlert() -> Void {
        guard alert.presentingViewController == nil, !alert.isBeingPresented else { return }
        alert.message = connection == .restricted ? "检测到网络权限可能未开启，您可以在“设置”中检查蜂窝移动网络" : "检测到网络可能未开启，您可以在“设置”中查看网络是否连接"
        visibleController?.present(alert, animated: true, completion: nil)
    }
    
    func dismissAlert(_ action: UIAlertAction) -> Void {
        if let presenting = alert.presentingViewController { presenting.dismiss(animated: true, completion: nil) }
        else { alert.dismiss(animated: true, completion: nil) }
    }
    
    func confirmAction(_ action: UIAlertAction) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

extension iReachable.Connection : Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.online(let lmode), .online(let rmode)): return lmode == rmode
        case (.offline, .offline):       return true
        case (.restricted, .restricted): return true
        default: return false
        }
    }
}

extension iReachable.Cellular {
    public var isWWAN: Bool {
        if case .iWiFi = self { return false }
        if case .unknown = self { return false }
        return true
    }
}

private class IReachableWeakify {
    weak var associateObj: iReachable?
    init(weakObj: iReachable) {
        self.associateObj = weakObj
    }
}
