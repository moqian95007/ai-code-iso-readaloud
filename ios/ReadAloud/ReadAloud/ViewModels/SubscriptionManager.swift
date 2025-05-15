import Foundation
import Combine
import StoreKit

/// 订阅产品信息
struct SubscriptionProduct {
    let id: String
    let type: SubscriptionType
    let product: SKProduct
    let localizedPrice: String
    let localizedPeriod: String
    
    // 计算每月平均价格（仅用于显示）
    var pricePerMonth: String? {
        guard let locale = product.priceLocale.currencySymbol else {
            return nil
        }
        
        var monthlyPrice: Double = 0
        
        switch type {
        case .quarterly:
            monthlyPrice = product.price.doubleValue / 3
            return String(format: "%@%.2f/月", locale, monthlyPrice)
        case .halfYearly:
            monthlyPrice = product.price.doubleValue / 6
            return String(format: "%@%.2f/月", locale, monthlyPrice)
        case .yearly:
            monthlyPrice = product.price.doubleValue / 12
            return String(format: "%@%.2f/月", locale, monthlyPrice)
        default:
            return nil
        }
    }
}

/// 订阅管理器
class SubscriptionManager: NSObject, ObservableObject {
    // 单例模式
    static let shared = SubscriptionManager()
    
    // 产品ID
    private let monthlyProductId = "top.ai-toolkit.readaloud.subscription.monthly"
    private let quarterlyProductId = "top.ai-toolkit.readaloud.subscription.quarterly"
    private let halfYearlyProductId = "top.ai-toolkit.readaloud.subscription.halfYearly"
    private let yearlyProductId = "top.ai-toolkit.readaloud.subscription.yearly"
    
    // 可用产品列表
    @Published var availableProducts: [SubscriptionProduct] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // StoreKit相关
    private var productRequest: SKProductsRequest?
    private var purchaseCompletionHandler: ((Result<SubscriptionType, Error>) -> Void)? = nil
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 初始化
    private override init() {
        super.init()
        // 设置SKPaymentTransactionObserver
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - 公共方法
    
    /// 加载可用的订阅产品
    func loadProducts() {
        isLoading = true
        errorMessage = nil
        
        let productIds = Set([monthlyProductId, quarterlyProductId, halfYearlyProductId, yearlyProductId])
        productRequest = SKProductsRequest(productIdentifiers: productIds)
        productRequest?.delegate = self
        productRequest?.start()
    }
    
    /// 购买订阅
    /// - Parameters:
    ///   - productId: 产品ID
    ///   - completion: 完成回调
    func purchaseSubscription(productId: String, completion: @escaping (Result<SubscriptionType, Error>) -> Void) {
        // 查找对应的产品
        guard let product = availableProducts.first(where: { $0.id == productId })?.product else {
            completion(.failure(NSError(domain: "SubscriptionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到对应的产品"])))
            return
        }
        
        // 存储完成回调
        purchaseCompletionHandler = completion
        
        // 创建支付请求
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    /// 恢复购买
    /// - Parameter completion: 完成回调
    func restorePurchases(completion: @escaping (Result<SubscriptionType?, Error>) -> Void) {
        purchaseCompletionHandler = { result in
            switch result {
            case .success(let type):
                completion(.success(type))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    /// 根据产品ID获取订阅类型
    /// - Parameter productId: 产品ID
    /// - Returns: 订阅类型
    private func subscriptionTypeForProductId(_ productId: String) -> SubscriptionType {
        switch productId {
        case monthlyProductId:
            return .monthly
        case quarterlyProductId:
            return .quarterly
        case halfYearlyProductId:
            return .halfYearly
        case yearlyProductId:
            return .yearly
        default:
            return .none
        }
    }
    
    /// 验证收据并更新订阅状态
    /// - Parameters:
    ///   - receiptData: 收据数据
    ///   - productId: 产品ID
    private func verifyReceiptAndUpdateSubscription(receiptData: Data, productId: String) {
        // 在实际应用中，这里应该将收据发送到服务器进行验证
        // 简化版本中，我们仅根据产品ID直接更新用户订阅状态
        
        let subscriptionType = subscriptionTypeForProductId(productId)
        
        // 计算订阅有效期
        var endDate: Date?
        let startDate = Date()
        
        switch subscriptionType {
        case .monthly:
            endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)
        case .quarterly:
            endDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate)
        case .halfYearly:
            endDate = Calendar.current.date(byAdding: .month, value: 6, to: startDate)
        case .yearly:
            endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate)
        case .none:
            endDate = nil
        }
        
        // 更新用户订阅状态
        if let user = UserManager.shared.currentUser, user.id > 0 {
            // 创建新的订阅记录
            let subscription = Subscription(
                userId: user.id,
                type: subscriptionType,
                startDate: startDate,
                endDate: endDate ?? Date(),
                subscriptionId: "\(productId)_\(UUID().uuidString)"
            )
            
            // 添加到订阅仓库
            SubscriptionRepository.shared.addSubscription(subscription)
            
            // 完成回调
            purchaseCompletionHandler?(.success(subscriptionType))
            purchaseCompletionHandler = nil
        } else {
            // 用户未登录
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])))
            purchaseCompletionHandler = nil
        }
    }
}

// MARK: - SKProductsRequestDelegate
extension SubscriptionManager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isLoading = false
            
            // 检查是否有有效产品
            if response.products.isEmpty {
                self.errorMessage = "未找到可用的订阅产品"
                return
            }
            
            // 处理产品信息
            var products: [SubscriptionProduct] = []
            
            for product in response.products {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = product.priceLocale
                
                guard let price = formatter.string(from: product.price) else { continue }
                
                var periodText = ""
                switch product.productIdentifier {
                case self.monthlyProductId:
                    periodText = "按月"
                    products.append(SubscriptionProduct(
                        id: product.productIdentifier,
                        type: .monthly,
                        product: product,
                        localizedPrice: price,
                        localizedPeriod: periodText
                    ))
                case self.quarterlyProductId:
                    periodText = "按季度"
                    products.append(SubscriptionProduct(
                        id: product.productIdentifier,
                        type: .quarterly,
                        product: product,
                        localizedPrice: price,
                        localizedPeriod: periodText
                    ))
                case self.halfYearlyProductId:
                    periodText = "半年"
                    products.append(SubscriptionProduct(
                        id: product.productIdentifier,
                        type: .halfYearly,
                        product: product,
                        localizedPrice: price,
                        localizedPeriod: periodText
                    ))
                case self.yearlyProductId:
                    periodText = "按年"
                    products.append(SubscriptionProduct(
                        id: product.productIdentifier,
                        type: .yearly,
                        product: product,
                        localizedPrice: price,
                        localizedPeriod: periodText
                    ))
                default:
                    continue
                }
            }
            
            self.availableProducts = products
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
            self?.errorMessage = "加载产品信息失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - SKPaymentTransactionObserver
extension SubscriptionManager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                handlePurchasedTransaction(transaction)
            case .restored:
                handleRestoredTransaction(transaction)
            case .failed:
                handleFailedTransaction(transaction)
            case .deferred, .purchasing:
                // 这些状态不需要特殊处理
                break
            @unknown default:
                break
            }
        }
    }
    
    private func handlePurchasedTransaction(_ transaction: SKPaymentTransaction) {
        // 获取收据数据
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法获取收据"])))
            purchaseCompletionHandler = nil
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 验证收据并更新订阅
        verifyReceiptAndUpdateSubscription(receiptData: receiptData, productId: transaction.payment.productIdentifier)
        
        // 完成交易
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func handleRestoredTransaction(_ transaction: SKPaymentTransaction) {
        // 获取原始交易的产品ID
        guard let productId = transaction.original?.payment.productIdentifier else {
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "恢复购买失败，无法获取原始交易"])))
            purchaseCompletionHandler = nil
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 获取收据数据
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法获取收据"])))
            purchaseCompletionHandler = nil
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 验证收据并更新订阅
        verifyReceiptAndUpdateSubscription(receiptData: receiptData, productId: productId)
        
        // 发送订阅状态更新通知
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
        }
        
        // 完成交易
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func handleFailedTransaction(_ transaction: SKPaymentTransaction) {
        if let error = transaction.error as? SKError {
            if error.code != .paymentCancelled {
                // 真正的错误
                purchaseCompletionHandler?(.failure(error))
            } else {
                // 用户取消
                purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "用户取消了购买"])))
            }
        } else {
            // 其他错误
            purchaseCompletionHandler?(.failure(transaction.error ?? NSError(domain: "SubscriptionManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "购买失败"])))
        }
        
        purchaseCompletionHandler = nil
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        // 如果没有恢复任何交易，且回调仍然存在，则通知用户没有找到可恢复的购买
        if queue.transactions.isEmpty && purchaseCompletionHandler != nil {
            print("没有找到可恢复的购买")
            purchaseCompletionHandler?(.success(.none))
            purchaseCompletionHandler = nil
            
            // 发送通知
            NotificationCenter.default.post(name: NSNotification.Name("SubscriptionRestorationFailed"), object: nil, userInfo: ["error": "未找到可恢复的购买"])
        }
        // 如果purchaseCompletionHandler为nil，说明已经在handleRestoredTransaction中处理了恢复逻辑
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        purchaseCompletionHandler?(.failure(error))
        purchaseCompletionHandler = nil
    }
} 