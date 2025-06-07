import Foundation

#if DEBUG
/// 用于调试订阅功能的工具类
class SubscriptionDebugger {
    static let shared = SubscriptionDebugger()
    
    private init() {}
    
    /// 强制设置临时订阅信息到UserDefaults
    func forceSetSubscription() {
        // 创建临时订阅信息
        let testSubscriptionInfo: [String: Any] = [
            "type": "monthly",
            "startDate": Date().timeIntervalSince1970,
            "endDate": Date().addingTimeInterval(30 * 24 * 60 * 60).timeIntervalSince1970 // 30天后
        ]
        
        // 保存到UserDefaults
        UserDefaults.standard.set(testSubscriptionInfo, forKey: "tempSubscriptionInfo")
        UserDefaults.standard.set(true, forKey: "guestHasPremiumAccess")
        UserDefaults.standard.synchronize()
        
        // 发送订阅状态更新通知
        NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
    }
    
    /// 清除所有订阅信息
    func clearSubscription() {
        UserDefaults.standard.removeObject(forKey: "tempSubscriptionInfo")
        UserDefaults.standard.set(false, forKey: "guestHasPremiumAccess")
        UserDefaults.standard.synchronize()
        
        // 发送订阅状态更新通知
        NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
    }
    
    /// 打印当前订阅状态
    func printSubscriptionStatus() {
        if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo") {
            print("临时订阅信息: \(subscriptionInfo)")
        } else {
            print("未找到临时订阅信息")
        }
    }
}
#endif 