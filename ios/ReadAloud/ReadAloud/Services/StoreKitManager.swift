import Foundation
import StoreKit
import Combine

/// StoreKit管理器，负责在应用启动时恢复和验证交易
class StoreKitManager {
    // 单例模式
    static let shared = StoreKitManager()
    
    // 订阅管理器
    private let subscriptionManager = SubscriptionManager.shared
    
    // 导入购买服务
    private let importPurchaseService = ImportPurchaseService.shared
    
    // 用户管理器
    private let userManager = UserManager.shared
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 是否正在恢复交易
    private(set) var isRestoringTransactions = false
    
    // 是否完成了启动时恢复
    private(set) var hasPerformedLaunchRestore = false
    
    // 私有初始化方法
    private init() {}
    
    /// 在应用启动时调用，自动恢复和验证所有交易
    /// - Parameter completion: 完成回调，返回恢复是否成功
    func restoreTransactionsAtLaunch(completion: ((Bool) -> Void)? = nil) {
        // 防止重复调用
        guard !hasPerformedLaunchRestore && !isRestoringTransactions else {
            print("跳过启动时恢复：已经执行过或正在执行")
            completion?(false)
            return
        }
        
        print("========== 应用启动时恢复交易 ==========")
        LogManager.shared.log("开始应用启动时恢复交易", level: .info, category: "StoreKit")
        
        isRestoringTransactions = true
        
        // 首先加载产品
        loadAllProducts()
        
        // 恢复交易
        SKPaymentQueue.default().restoreCompletedTransactions()
        
        // 设置超时处理
        let timeout = 15.0 // 15秒超时
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, self.isRestoringTransactions else { return }
            
            print("恢复交易超时，强制完成")
            LogManager.shared.log("恢复交易超时，强制完成", level: .warning, category: "StoreKit")
            self.isRestoringTransactions = false
            self.hasPerformedLaunchRestore = true
            
            // 触发订阅状态更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
            }
            
            completion?(false)
        }
        
        // 添加一次性恢复完成的观察者
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SKRestoreTransactionsFinished"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            
            let success = notification.userInfo?["success"] as? Bool ?? false
            print("收到恢复交易完成通知，结果：\(success ? "成功" : "失败")")
            LogManager.shared.log("恢复交易完成，结果：\(success ? "成功" : "失败")", level: .info, category: "StoreKit")
            
            self.isRestoringTransactions = false
            self.hasPerformedLaunchRestore = true
            
            // 触发订阅状态更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
            }
            
            completion?(success)
            
            // 移除观察者
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SKRestoreTransactionsFinished"), object: nil)
        }
        
        print("启动恢复交易过程已启动")
    }
    
    /// 手动恢复交易（供用户主动触发）
    /// - Parameter completion: 完成回调，返回恢复是否成功
    func restoreTransactionsManually(completion: ((Bool) -> Void)? = nil) {
        // 防止重复调用
        guard !isRestoringTransactions else {
            print("恢复交易已在进行中，请稍后再试")
            completion?(false)
            return
        }
        
        print("========== 手动恢复交易 ==========")
        LogManager.shared.log("开始手动恢复交易", level: .info, category: "StoreKit")
        
        isRestoringTransactions = true
        
        // 首先加载产品
        loadAllProducts()
        
        // 恢复交易
        SKPaymentQueue.default().restoreCompletedTransactions()
        
        // 设置超时处理
        let timeout = 20.0 // 20秒超时
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, self.isRestoringTransactions else { return }
            
            print("手动恢复交易超时，强制完成")
            LogManager.shared.log("手动恢复交易超时，强制完成", level: .warning, category: "StoreKit")
            self.isRestoringTransactions = false
            
            // 触发订阅状态更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
            }
            
            completion?(false)
        }
        
        // 添加一次性恢复完成的观察者
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SKRestoreTransactionsFinished"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            
            let success = notification.userInfo?["success"] as? Bool ?? false
            print("收到手动恢复交易完成通知，结果：\(success ? "成功" : "失败")")
            LogManager.shared.log("手动恢复交易完成，结果：\(success ? "成功" : "失败")", level: .info, category: "StoreKit")
            
            self.isRestoringTransactions = false
            
            // 触发订阅状态更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
            }
            
            completion?(success)
            
            // 移除观察者
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SKRestoreTransactionsFinished"), object: nil)
        }
        
        print("手动恢复交易过程已启动")
    }
    
    /// 加载所有产品（订阅和导入次数）
    private func loadAllProducts() {
        // 加载订阅产品
        subscriptionManager.loadProducts()
        
        // 加载导入次数产品
        importPurchaseService.loadProducts()
    }
} 