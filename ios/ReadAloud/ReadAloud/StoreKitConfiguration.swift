import Foundation
import StoreKit

/// StoreKit配置类
class StoreKitConfiguration {
    
    /// 共享实例
    static let shared = StoreKitConfiguration()
    
    /// 测试环境标识
    let isTestEnvironment: Bool
    
    /// 初始化
    private init() {
        #if DEBUG
        self.isTestEnvironment = true
        #else
        self.isTestEnvironment = false
        #endif
        
        setupStoreKit()
    }
    
    /// 设置StoreKit
    private func setupStoreKit() {
        if isTestEnvironment {
            print("正在使用StoreKit测试环境")
            
            // 在DEBUG模式下，监听StoreKit测试交易完成的通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleStoreKitTestCompletion),
                name: Notification.Name("StoreKitTestTransactionCompleted"),
                object: nil
            )
        } else {
            print("正在使用StoreKit生产环境")
        }
    }
    
    /// 处理StoreKit测试交易完成的通知
    @objc private func handleStoreKitTestCompletion() {
        print("StoreKit测试交易已完成")
    }
    
    /// 启用StoreKit测试交易观察
    func enableStoreKitTestObserver() {
        guard isTestEnvironment else { return }
        
        // 在iOS 15及以上版本，这里可以使用新的StoreKit 2.0 API来测试交易
        if #available(iOS 15.0, *) {
            Task {
                // 请求交易更新，用于在测试环境中模拟购买流程
                for await verificationResult in Transaction.updates {
                    do {
                        let transaction = try verificationResult.payloadValue
                        print("收到StoreKit 2.0测试交易更新: \(String(describing: transaction.productID))")
                        
                        // 处理交易更新，更新用户订阅状态
                        await handleTransaction(transaction)
                        
                        // 完成交易
                        await transaction.finish()
                    } catch {
                        print("处理StoreKit 2.0交易验证失败: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // iOS 14及以下使用旧API (已由SubscriptionManager实现)
            print("iOS 14及以下使用传统StoreKit API")
        }
    }
    
    /// 处理交易并更新用户订阅状态
    @available(iOS 15.0, *)
    private func handleTransaction(_ transaction: Transaction) async {
        // 确认是订阅类型的交易
        guard transaction.productType == .autoRenewable else {
            print("非订阅类型的交易，忽略")
            return
        }
        
        let productId = transaction.productID
        
        // 判断是普通购买还是恢复购买
        let isRestore = transaction.originalID != nil
        print("交易类型: \(isRestore ? "恢复购买" : "新购买")")
        
        // 获取订阅类型
        var subscriptionType: SubscriptionType = .none
        switch productId {
        case "top.ai-toolkit.readaloud.subscription.monthly":
            subscriptionType = .monthly
        case "top.ai-toolkit.readaloud.subscription.quarterly":
            subscriptionType = .quarterly
        case "top.ai-toolkit.readaloud.subscription.halfYearly":
            subscriptionType = .halfYearly
        case "top.ai-toolkit.readaloud.subscription.yearly":
            subscriptionType = .yearly
        default:
            print("未知的产品ID: \(productId)")
            return
        }
        
        // 获取当前用户
        guard let user = UserManager.shared.currentUser, user.id > 0 else {
            print("用户未登录，无法更新订阅状态")
            return
        }
        
        // 计算订阅有效期
        let startDate = Date()
        var endDate: Date
        
        switch subscriptionType {
        case .monthly:
            endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)!
        case .quarterly:
            endDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate)!
        case .halfYearly:
            endDate = Calendar.current.date(byAdding: .month, value: 6, to: startDate)!
        case .yearly:
            endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate)!
        case .none:
            return
        }
        
        // 创建新的订阅记录
        let subscription = Subscription(
            userId: user.id,
            type: subscriptionType,
            startDate: startDate,
            endDate: endDate,
            subscriptionId: "\(productId)_\(UUID().uuidString)"
        )
        
        // 添加订阅记录
        SubscriptionRepository.shared.addSubscription(subscription)
        
        // 发送通知，通知UI更新
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
        }
        
        print("用户订阅状态已更新: \(subscriptionType.displayName), 有效期至: \(endDate)")
    }
} 