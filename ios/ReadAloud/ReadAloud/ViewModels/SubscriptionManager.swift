import Foundation
import Combine
import StoreKit
// 导入SwiftUI，因为Transaction API需要用到Combine和Swift Concurrency
import SwiftUI

// 针对iOS 15+导入StoreKit 2.0 Transaction相关API
#if canImport(StoreKit) && compiler(>=5.5)
@available(iOS 15.0, *)
typealias TransactionAPI = StoreKit.Transaction
#endif

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
    
    // 检查是否支持StoreKit 2.0
    private var isStoreKit2Available: Bool {
        if #available(iOS 15.0, *) {
            return true
        }
        return false
    }
    
    // 添加最近处理的交易记录跟踪
    private var recentlyProcessedTransactions = Set<String>()
    private let maxRecentTransactions = 10
    
    // 添加交易ID跟踪集合
    private var processedTransactionIds = Set<String>()
    
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
        // 存储完成回调
        purchaseCompletionHandler = { result in
            switch result {
            case .success(let type):
                completion(.success(type))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
        // 检查是否支持StoreKit 2.0 API
        print("========== 恢复购买路径选择 ==========")
        print("iOS版本: \(UIDevice.current.systemVersion)")
        print("判断是否支持StoreKit 2.0: \(isStoreKit2Available)")
        
        if isStoreKit2Available {
            print("准备使用StoreKit 2.0 API恢复购买")
            if #available(iOS 15.0, *) {
                print("已确认iOS 15+，调用StoreKit 2.0方法")
                restorePurchasesWithStoreKit2(completion: completion)
            } else {
                // 这个分支不应该执行，但为了安全起见
                print("逻辑错误：isStoreKit2Available返回true但条件判断为iOS 15以下")
                print("回退到StoreKit 1.0 API恢复购买")
                SKPaymentQueue.default().restoreCompletedTransactions()
            }
        } else {
            print("设备不支持StoreKit 2.0，使用StoreKit 1.0 API恢复购买")
            SKPaymentQueue.default().restoreCompletedTransactions()
        }
    }
    
    /// 使用StoreKit 2.0 API恢复购买
    /// - Parameter completion: 完成回调
    @available(iOS 15.0, *)
    private func restorePurchasesWithStoreKit2(completion: @escaping (Result<SubscriptionType?, Error>) -> Void) {
        print("========== StoreKit 2.0 恢复购买开始 ==========")
        
        // 标记是否已经处理了活跃订阅
        var hasProcessedActiveSubscription = false
        
        // 创建异步任务获取交易
        Task {
            do {
                // 获取所有交易历史
                print("正在获取所有交易历史...")
                print("注意：在沙盒环境中，可能无法获取完整的交易信息")
                
                var hasActiveSubscription = false
                var latestSubscriptionType: SubscriptionType = .none
                var transactionFound = false
                
                // 遍历所有已验证的交易
                for await verificationResult in TransactionAPI.all {
                    // 标记已经查找到了交易记录
                    transactionFound = true
                    print("已获取到交易记录")
                    
                    // 使用正确的方式处理验证结果
                    switch verificationResult {
                    case .verified(let transaction):
                        // 仅处理订阅类型的交易
                        guard transaction.productType == .autoRenewable else {
                            print("跳过非订阅类型交易")
                            continue
                        }
                        
                        print("========== 交易详情 ==========")
                        print("交易ID: \(transaction.id)")
                        print("产品ID: \(transaction.productID)")
                        print("购买日期: \(transaction.purchaseDate)")
                        print("原始购买日期: \(transaction.originalPurchaseDate)")
                        if let expirationDate = transaction.expirationDate {
                            print("过期日期: \(expirationDate)")
                        } else {
                            print("过期日期: 未指定")
                        }
                        print("是否当前活跃: \(transaction.revocationDate == nil)")
                        print("==============================")
                        
                        // 检查最新的订阅状态
                        let isActive = transaction.revocationDate == nil 
                                      && (transaction.expirationDate == nil || transaction.expirationDate! > Date())
                        
                        // 根据产品ID确定订阅类型
                        let subscriptionType = subscriptionTypeForProductId(transaction.productID)
                        
                        if isActive {
                            print("发现活跃的订阅: \(subscriptionType.rawValue)")
                            hasActiveSubscription = true
                            latestSubscriptionType = subscriptionType
                            
                            // 创建订阅记录
                            if let user = UserManager.shared.currentUser, user.id > 0 {
                                print("为用户 \(user.id) 创建订阅记录")
                                
                                // 使用原始购买日期
                                let startDate = transaction.originalPurchaseDate
                                var endDate = transaction.expirationDate ?? Date().addingTimeInterval(86400 * 30) // 默认30天
                                
                                print("订阅起始日期: \(startDate)")
                                print("订阅结束日期: \(endDate)")
                                
                                // 检查是否有退款
                                if let revocationDate = transaction.revocationDate {
                                    print("订阅已撤销，撤销日期: \(revocationDate)")
                                    endDate = revocationDate
                                }
                                
                                // 创建新的订阅记录
                                let subscription = Subscription(
                                    userId: user.id,
                                    type: subscriptionType,
                                    startDate: startDate,
                                    endDate: endDate,
                                    subscriptionId: "sk2_restored_\(transaction.id)_\(transaction.productID)"
                                )
                                
                                // 添加到订阅仓库 - 这里有同步机制，会自动触发同步到服务器
                                SubscriptionRepository.shared.addSubscription(subscription)
                                print("已添加恢复的订阅记录到仓库")
                                
                                // 标记已处理
                                hasProcessedActiveSubscription = true
                                
                                // 找到有效订阅后立即完成流程
                                print("找到有效订阅，准备返回结果")
                                DispatchQueue.main.async {
                                    print("返回恢复购买结果: 类型=\(subscriptionType.rawValue)")
                                    // 不在这里发送通知，留给SubscriptionService统一处理
                                    // NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                                    completion(.success(subscriptionType))
                                    self.purchaseCompletionHandler?(.success(subscriptionType))
                                    self.purchaseCompletionHandler = nil
                                    print("========== StoreKit 2.0 恢复购买结束 ==========")
                                }
                                
                                // 找到活跃订阅并处理后不再继续检查其他交易
                                break
                            } else {
                                print("用户未登录，无法创建订阅记录")
                            }
                        } else {
                            print("发现已过期的订阅: \(subscriptionType.rawValue)")
                        }
                    case .unverified(let transaction, let error):
                        print("发现未验证的交易: \(transaction.id), 错误: \(error.localizedDescription)")
                    }
                }
                
                print("交易历史查询完成")
                
                // 如果已经处理了活跃订阅，不再执行后续逻辑
                if hasProcessedActiveSubscription {
                    print("已在处理过程中完成了恢复购买流程")
                    return
                }
                
                if !transactionFound {
                    print("⚠️ 警告：没有找到任何交易记录")
                    print("这在沙盒测试环境中很常见，特别是在首次测试时")
                    
                    // 尝试使用StoreKit 1.0的恢复方式作为备选
                    print("尝试使用StoreKit 1.0 API作为备选")
                    DispatchQueue.main.async {
                        SKPaymentQueue.default().restoreCompletedTransactions()
                    }
                    return
                }
                
                if hasActiveSubscription {
                    print("找到活跃的订阅，类型: \(latestSubscriptionType.rawValue)")
                    
                    // 发送订阅状态更新通知
                    DispatchQueue.main.async {
                        // 不在这里发送通知，留给SubscriptionService统一处理
                        // NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                        completion(.success(latestSubscriptionType))
                        self.purchaseCompletionHandler?(.success(latestSubscriptionType))
                        self.purchaseCompletionHandler = nil
                    }
                } else {
                    print("未找到活跃的订阅")
                    DispatchQueue.main.async {
                        completion(.success(.none))
                        self.purchaseCompletionHandler?(.success(.none))
                        self.purchaseCompletionHandler = nil
                    }
                }
            } catch {
                print("使用StoreKit 2.0恢复购买时出错: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                    self.purchaseCompletionHandler?(.failure(error))
                    self.purchaseCompletionHandler = nil
                }
            }
            
            print("========== StoreKit 2.0 恢复购买结束 ==========")
        }
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
    ///   - originalPurchaseDate: 原始购买日期（用于恢复购买）
    private func verifyReceiptAndUpdateSubscription(receiptData: Data, productId: String, originalPurchaseDate: Date? = nil) {
        print("========== 验证收据并更新订阅 ==========")
        print("产品ID: \(productId)")
        print("原始购买日期: \(originalPurchaseDate?.description ?? "未提供，使用当前日期")")
        print("收据数据大小: \(receiptData.count) 字节")
        
        // 生成交易唯一标识符（使用产品ID和当前时间）
        let transactionKey = "\(productId)_\(Date().timeIntervalSince1970)"
        
        // 检查是否是重复处理的交易
        if recentlyProcessedTransactions.contains(transactionKey) {
            print("跳过重复处理的交易: \(transactionKey)")
            return
        }
        
        // 添加到最近处理的交易
        recentlyProcessedTransactions.insert(transactionKey)
        
        // 如果超过最大记录数，移除最早的记录
        if recentlyProcessedTransactions.count > maxRecentTransactions {
            recentlyProcessedTransactions.removeFirst()
        }
        
        // 将收据转换为Base64字符串前50个字符
        let base64Receipt = receiptData.base64EncodedString()
        print("收据Base64前缀: \(String(base64Receipt.prefix(50)))...")
        
        // 在实际应用中，这里应该将收据发送到服务器进行验证
        // 简化版本中，我们仅根据产品ID直接更新用户订阅状态
        
        var subscriptionType = subscriptionTypeForProductId(productId)
        print("订阅类型: \(subscriptionType)")
        
        // 检查订阅类型，如果是none，需要根据productId转换为正确的类型
        if subscriptionType == .none && productId.contains(".subscription.") {
            // 从产品ID中提取订阅类型
            if productId.contains(".monthly") {
                subscriptionType = .monthly
            } else if productId.contains(".quarterly") {
                subscriptionType = .quarterly
            } else if productId.contains(".halfYearly") {
                subscriptionType = .halfYearly
            } else if productId.contains(".yearly") {
                subscriptionType = .yearly
            }
            print("订阅类型更正为: \(subscriptionType)")
        }
        
        // 使用原始购买日期（如果提供）或当前日期
        let startDate = originalPurchaseDate ?? Date()
        print("订阅开始日期: \(startDate)")
        
        // 计算订阅有效期（基于开始日期）
        var endDate: Date?
        
        switch subscriptionType {
        case .monthly:
            endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)
            print("订阅周期: 1个月")
        case .quarterly:
            endDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate)
            print("订阅周期: 3个月")
        case .halfYearly:
            endDate = Calendar.current.date(byAdding: .month, value: 6, to: startDate)
            print("订阅周期: 6个月")
        case .yearly:
            endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate)
            print("订阅周期: 1年")
        case .none:
            endDate = nil
            print("订阅周期: 无")
        }
        
        if let endDate = endDate {
            print("订阅结束日期: \(endDate)")
        }
        
        // 更新用户订阅状态
        if let user = UserManager.shared.currentUser, user.id > 0 {
            print("更新用户ID \(user.id) 的订阅状态")
            
            // 创建新的订阅记录
            let subscription = Subscription(
                userId: user.id,
                type: subscriptionType,
                startDate: startDate,
                endDate: endDate ?? Date(),
                subscriptionId: "\(productId)_\(UUID().uuidString)"
            )
            
            // 添加到订阅仓库 - 注意：SubscriptionRepository.addSubscription会自动同步到服务器
            // 因此不需要在这里发送通知或进行其他操作
            SubscriptionRepository.shared.addSubscription(subscription)
            print("成功添加订阅记录: \(subscription.subscriptionId)")
            
            // 发送通知更新UI
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
            }
            
            // 完成回调
            purchaseCompletionHandler?(.success(subscriptionType))
            purchaseCompletionHandler = nil
        } else {
            // 用户未登录
            print("错误: 用户未登录，无法更新订阅状态")
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "用户未登录"])))
            purchaseCompletionHandler = nil
        }
        print("========================================")
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
        // 检查交易ID是否已处理过，避免重复处理
        if transaction.transactionIdentifier == nil {
            // 没有交易ID，仍然处理该交易
            print("警告：交易没有ID，仍将处理")
        }
        
        if let id = transaction.transactionIdentifier, processedTransactionIds.contains(id) {
            print("交易 \(id) 已处理过，跳过")
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 记录交易ID
        if let id = transaction.transactionIdentifier {
            processedTransactionIds.insert(id)
            print("记录交易ID: \(id)，目前已处理 \(processedTransactionIds.count) 个交易")
        }
        
        // 忽略消费型产品的交易 - 由ImportPurchaseService处理
        let productId = transaction.payment.productIdentifier
        if productId.contains("import.") {
            print("检测到消费型产品交易: \(productId)，由ImportPurchaseService处理")
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
        
        // 验证收据并更新订阅（对于新购买，不传递原始日期，使用当前日期）
        verifyReceiptAndUpdateSubscription(receiptData: receiptData, productId: transaction.payment.productIdentifier)
        
        // 完成交易
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    private func handleRestoredTransaction(_ transaction: SKPaymentTransaction) {
        // 详细打印恢复购买的交易信息
        print("========== 恢复购买详细信息 ==========")
        
        // 忽略消费型产品的交易 - 由ImportPurchaseService处理
        let productId = transaction.payment.productIdentifier
        if productId.contains("import.") {
            print("检测到消费型产品恢复交易: \(productId)，由ImportPurchaseService处理")
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        print("交易ID: \(transaction.transactionIdentifier ?? "未知")")
        print("交易日期: \(transaction.transactionDate?.description ?? "未知")")
        print("产品ID: \(transaction.payment.productIdentifier)")
        print("购买数量: \(transaction.payment.quantity)")
        
        // 打印原始交易信息
        print("原始交易信息：")
        if let originalTransaction = transaction.original {
            print("原始交易ID: \(originalTransaction.transactionIdentifier ?? "未知")")
            print("原始交易日期(原始格式): \(originalTransaction.transactionDate ?? Date())")
            
            if let date = originalTransaction.transactionDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("原始交易日期(格式化): \(formatter.string(from: date))")
                print("原始交易日期距今: \(Date().timeIntervalSince(date) / 86400) 天")
            } else {
                print("⚠️ 原始交易日期为空")
            }
            
            print("原始产品ID: \(originalTransaction.payment.productIdentifier)")
            print("原始交易状态: \(originalTransaction.transactionState.rawValue)")
        } else {
            print("⚠️ 没有原始交易信息")
        }
        
        // 打印收据信息
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            print("收据URL: \(receiptURL.path)")
            if let receiptData = try? Data(contentsOf: receiptURL) {
                print("收据数据大小: \(receiptData.count) 字节")
                // 将收据转换为Base64字符串，取前50个字符打印
                let base64Receipt = receiptData.base64EncodedString()
                print("收据前缀: \(String(base64Receipt.prefix(50)))...")
            }
        }
        
        // 获取原始交易的产品ID
        guard let productId = transaction.original?.payment.productIdentifier else {
            print("错误: 恢复购买失败，无法获取原始交易的产品ID")
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "恢复购买失败，无法获取原始交易"])))
            purchaseCompletionHandler = nil
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 获取收据数据
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            print("错误: 恢复购买失败，无法获取收据数据")
            purchaseCompletionHandler?(.failure(NSError(domain: "SubscriptionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法获取收据"])))
            purchaseCompletionHandler = nil
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 尝试获取原始购买日期
        var originalPurchaseDate: Date? = nil
        if let originalTransaction = transaction.original {
            // 获取交易日期作为原始购买日期
            originalPurchaseDate = originalTransaction.transactionDate
            if let date = originalPurchaseDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("恢复购买成功，原始购买日期: \(formatter.string(from: date))")
            } else {
                print("⚠️ 警告：恢复购买成功，但原始购买日期为空")
            }
        } else {
            print("⚠️ 警告：恢复购买成功，但无法获取原始交易信息")
        }
        
        // 记录对应的订阅类型
        let subscriptionType = subscriptionTypeForProductId(productId)
        print("恢复的订阅类型: \(subscriptionType)")
        print("========================================")
        
        // 验证收据并更新订阅，传递原始购买日期
        verifyReceiptAndUpdateSubscription(receiptData: receiptData, productId: productId, originalPurchaseDate: originalPurchaseDate)
        
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
        print("========== 恢复购买完成 ==========")
        print("恢复的交易数量: \(queue.transactions.count)")
        
        // 打印所有恢复的交易
        for (index, transaction) in queue.transactions.enumerated() {
            if transaction.transactionState == .restored {
                print("恢复的交易 #\(index+1):")
                print("  交易ID: \(transaction.transactionIdentifier ?? "未知")")
                print("  产品ID: \(transaction.payment.productIdentifier)")
                print("  状态: 已恢复")
                
                if let originalTransaction = transaction.original {
                    print("  原始交易ID: \(originalTransaction.transactionIdentifier ?? "未知")")
                    print("  原始交易日期: \(originalTransaction.transactionDate?.description ?? "未知")")
                }
            }
        }
        
        // 如果没有恢复任何交易，且回调仍然存在，则通知用户没有找到可恢复的购买
        if queue.transactions.isEmpty && purchaseCompletionHandler != nil {
            print("没有找到可恢复的购买")
            purchaseCompletionHandler?(.success(.none))
            purchaseCompletionHandler = nil
            
            // 发送通知
            NotificationCenter.default.post(name: NSNotification.Name("SubscriptionRestorationFailed"), object: nil, userInfo: ["error": "未找到可恢复的购买"])
        }
        print("=====================================")
        // 如果purchaseCompletionHandler为nil，说明已经在handleRestoredTransaction中处理了恢复逻辑
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("========== 恢复购买失败 ==========")
        print("错误描述: \(error.localizedDescription)")
        
        if let skError = error as? SKError {
            print("错误代码: \(skError.code.rawValue)")
            print("错误域: \(SKErrorDomain)")
            
            // 打印常见错误类型
            switch skError.code {
            case .paymentCancelled:
                print("错误类型: 用户取消了恢复购买")
            case .paymentInvalid:
                print("错误类型: 支付无效")
            case .paymentNotAllowed:
                print("错误类型: 用户不允许支付")
            case .storeProductNotAvailable:
                print("错误类型: 产品不可用")
            case .cloudServicePermissionDenied:
                print("错误类型: 云服务权限被拒绝")
            case .cloudServiceNetworkConnectionFailed:
                print("错误类型: 云服务网络连接失败")
            default:
                print("错误类型: 其他StoreKit错误")
            }
        }
        
        print("详细错误信息: \(error)")
        print("=====================================")
        
        purchaseCompletionHandler?(.failure(error))
        purchaseCompletionHandler = nil
    }
} 