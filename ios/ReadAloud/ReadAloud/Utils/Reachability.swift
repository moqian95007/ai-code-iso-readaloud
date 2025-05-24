// 注意：该文件需要在项目中添加SystemConfiguration.framework框架
// 请在Xcode中: Target -> Build Phases -> Link Binary With Libraries中添加

import Foundation
import SystemConfiguration

public enum ReachabilityError: Error {
    case FailedToCreateWithAddress(sockaddr_in)
    case FailedToCreateWithHostname(String)
    case UnableToSetCallback
    case UnableToSetDispatchQueue
    case UnableToGetInitialFlags
}

public enum ReachabilityConnection: CustomStringConvertible {
    case none, wifi, cellular
    
    public var description: String {
        switch self {
        case .cellular: return "蜂窝数据"
        case .wifi: return "WiFi"
        case .none: return "无网络连接"
        }
    }
}

public class Reachability {
    public typealias NetworkReachable = (Reachability) -> Void
    public typealias NetworkUnreachable = (Reachability) -> Void
    
    public enum NetworkStatus: CustomStringConvertible {
        case notReachable, reachableViaWiFi, reachableViaWWAN
        
        public var description: String {
            switch self {
            case .reachableViaWWAN: return "Cellular"
            case .reachableViaWiFi: return "WiFi"
            case .notReachable: return "No Connection"
            }
        }
    }
    
    public var whenReachable: NetworkReachable?
    public var whenUnreachable: NetworkUnreachable?
    
    public var allowsCellularConnection: Bool
    
    public var notificationCenter: NotificationCenter = NotificationCenter.default
    
    public var connection: ReachabilityConnection {
        if flags == nil {
            try? setReachabilityFlags()
        }
        
        switch flags?.connection {
        case .none?, nil: return .none
        case .cellular?: return allowsCellularConnection ? .cellular : .none
        case .wifi?: return .wifi
        }
    }
    
    fileprivate var isRunningOnDevice: Bool = {
        #if targetEnvironment(simulator)
            return false
        #else
            return true
        #endif
    }()
    
    fileprivate var notifierRunning = false
    fileprivate let reachabilityRef: SCNetworkReachability
    fileprivate let reachabilitySerialQueue: DispatchQueue
    fileprivate(set) var flags: SCNetworkReachabilityFlags? {
        didSet {
            guard flags != oldValue else { return }
            notifyReachabilityChanged()
        }
    }
    
    required public init(reachabilityRef: SCNetworkReachability, queueQoS: DispatchQoS = .default, targetQueue: DispatchQueue? = nil) {
        self.allowsCellularConnection = true
        self.reachabilityRef = reachabilityRef
        self.reachabilitySerialQueue = DispatchQueue(label: "com.readaloud.reachability", qos: queueQoS, target: targetQueue)
    }
    
    public convenience init() throws {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let ref = SCNetworkReachabilityCreateWithAddress(nil, withUnsafePointer(to: &zeroAddress, {
            UnsafePointer($0).withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        })) else {
            throw ReachabilityError.FailedToCreateWithAddress(zeroAddress)
        }
        
        self.init(reachabilityRef: ref)
    }
    
    // MARK: - Notifier methods
    
    public func startNotifier() throws {
        guard !notifierRunning else { return }
        
        let callback: SCNetworkReachabilityCallBack = { (reachability, flags, info) in
            guard let info = info else { return }
            
            let reachability = Unmanaged<Reachability>.fromOpaque(info).takeUnretainedValue()
            reachability.flags = flags
        }
        
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutableRawPointer(Unmanaged<Reachability>.passUnretained(self).toOpaque())
        
        if !SCNetworkReachabilitySetCallback(reachabilityRef, callback, &context) {
            stopNotifier()
            throw ReachabilityError.UnableToSetCallback
        }
        
        if !SCNetworkReachabilitySetDispatchQueue(reachabilityRef, reachabilitySerialQueue) {
            stopNotifier()
            throw ReachabilityError.UnableToSetDispatchQueue
        }
        
        try setReachabilityFlags()
        
        notifierRunning = true
    }
    
    public func stopNotifier() {
        defer { notifierRunning = false }
        
        SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachabilityRef, nil)
    }
    
    // MARK: - Network Flag Handling
    
    fileprivate func setReachabilityFlags() throws {
        try reachabilitySerialQueue.sync { [unowned self] in
            var flags = SCNetworkReachabilityFlags()
            if !SCNetworkReachabilityGetFlags(self.reachabilityRef, &flags) {
                throw ReachabilityError.UnableToGetInitialFlags
            }
            
            self.flags = flags
        }
    }
    
    fileprivate func notifyReachabilityChanged() {
        let notify = { [weak self] in
            guard let self = self else { return }
            if self.connection != .none {
                self.whenReachable?(self)
            } else {
                self.whenUnreachable?(self)
            }
            self.notificationCenter.post(name: .reachabilityChanged, object: self)
        }
        
        DispatchQueue.main.async { notify() }
    }
}

extension SCNetworkReachabilityFlags {
    var connection: ReachabilityConnection {
        guard isReachableFlagSet else { return .none }
        
        #if targetEnvironment(simulator)
        return .wifi
        #else
        var connection = ReachabilityConnection.none
        
        if !isConnectionRequiredFlagSet {
            connection = .wifi
        }
        
        if isConnectionOnTrafficOrDemandFlagSet {
            if !isInterventionRequiredFlagSet {
                connection = .wifi
            }
        }
        
        if isOnWWANFlagSet {
            connection = .cellular
        }
        
        return connection
        #endif
    }
    
    var isOnWWANFlagSet: Bool {
        #if os(iOS)
        return contains(.isWWAN)
        #else
        return false
        #endif
    }
    
    var isReachableFlagSet: Bool {
        return contains(.reachable)
    }
    
    var isConnectionRequiredFlagSet: Bool {
        return contains(.connectionRequired)
    }
    
    var isInterventionRequiredFlagSet: Bool {
        return contains(.interventionRequired)
    }
    
    var isConnectionOnTrafficFlagSet: Bool {
        return contains(.connectionOnTraffic)
    }
    
    var isConnectionOnDemandFlagSet: Bool {
        return contains(.connectionOnDemand)
    }
    
    var isConnectionOnTrafficOrDemandFlagSet: Bool {
        return !intersection([.connectionOnTraffic, .connectionOnDemand]).isEmpty
    }
    
    var isTransientConnectionFlagSet: Bool {
        return contains(.transientConnection)
    }
    
    var isLocalAddressFlagSet: Bool {
        return contains(.isLocalAddress)
    }
    
    var isDirectFlagSet: Bool {
        return contains(.isDirect)
    }
    
    var isConnectionRequiredAndTransientFlagSet: Bool {
        return intersection([.connectionRequired, .transientConnection]) == [.connectionRequired, .transientConnection]
    }
}

extension Notification.Name {
    static let reachabilityChanged = Notification.Name("ReachabilityChanged")
} 