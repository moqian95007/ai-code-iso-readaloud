// 注意：该文件需要在项目中添加SystemConfiguration.framework框架
// 请在Xcode中: Target -> Build Phases -> Link Binary With Libraries中添加

import Foundation
import StoreKit

/// StoreKit配置类
class StoreKitConfiguration: NSObject {
    
    /// 共享实例
    static let shared = StoreKitConfiguration()
    
    /// 测试环境标识
    let isTestEnvironment: Bool
    
    // 用于存储预加载的产品
    private var cachedProducts: [String: SKProduct] = [:]
    
    // 产品ID管理器
    private let productIdManager = ProductIdManager.shared
    
    // 请求超时计时器
    private var requestTimeoutTimer: Timer?
    
    // 当前正在处理的请求
    private var currentRequest: SKProductsRequest?
    
    /// 初始化
    private override init() {
        // 使用收据URL判断环境，确保Xcode和TestFlight环境一致
        let isSandbox = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        
        #if DEBUG
        // DEBUG模式下不再强制使用沙盒环境，而是直接使用App Store产品
        print("🔄 [StoreKit] DEBUG模式编译，收据检测结果: \(isSandbox ? "沙盒环境" : "生产环境")")
        print("🔄 [StoreKit] 收据URL路径: \(Bundle.main.appStoreReceiptURL?.path ?? "nil")")
        self.isTestEnvironment = isSandbox  // 直接使用收据判断结果，不强制设置为测试环境
        LogManager.shared.log("DEBUG模式编译，使用收据判断环境: \(isSandbox ? "沙盒环境" : "生产环境")", level: .info, category: "StoreKit")
        #else
        // RELEASE模式(包括TestFlight)使用收据判断
        self.isTestEnvironment = isSandbox
        print("🔄 [StoreKit] RELEASE模式编译，收据检测结果: \(isSandbox ? "沙盒环境" : "生产环境")")
        print("🔄 [StoreKit] 收据URL路径: \(Bundle.main.appStoreReceiptURL?.path ?? "nil")")
        print("🔄 [StoreKit] 实际使用环境: \(self.isTestEnvironment ? "沙盒环境" : "生产环境")")
        LogManager.shared.log("RELEASE模式编译，收据检测结果: \(isSandbox ? "沙盒环境" : "生产环境")", level: .info, category: "StoreKit")
        LogManager.shared.log("实际使用环境: \(self.isTestEnvironment ? "沙盒环境" : "生产环境")", level: .info, category: "StoreKit")
        #endif
        
        super.init()
        
        setupStoreKit()
    }
    
    deinit {
        invalidateTimeoutTimer()
    }
    
    /// 设置StoreKit
    private func setupStoreKit() {
        if isTestEnvironment {
            print("🔄 [StoreKit] 正在使用StoreKit测试环境")
            LogManager.shared.log("使用StoreKit测试环境", level: .info, category: "StoreKit")
            
            // 在测试环境下，监听StoreKit测试交易完成的通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleStoreKitTestCompletion),
                name: Notification.Name("StoreKitTestTransactionCompleted"),
                object: nil
            )
        } else {
            print("🔄 [StoreKit] 正在使用StoreKit生产环境")
            LogManager.shared.log("使用StoreKit生产环境", level: .info, category: "StoreKit")
        }
    }
    
    /// 设置请求超时计时器
    private func setupTimeoutTimer() {
        // 取消现有计时器
        invalidateTimeoutTimer()
        
        // 创建新计时器，10秒后触发超时
        requestTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            print("⚠️ [StoreKit] 产品请求超时")
            LogManager.shared.logIAP("产品请求超时", level: .warning)
            
            // 如果有当前请求，取消它
            if let request = self.currentRequest {
                request.cancel()
                self.currentRequest = nil
                
                // 获取请求类型
                let requestType = objc_getAssociatedObject(request, UnsafeRawPointer(bitPattern: 1)!) as? String ?? "unknown"
                let isSimplifiedRequest = requestType == "simplified"
                
                // 如果是简化ID请求超时，尝试完整ID
                if isSimplifiedRequest {
                    print("🔄 [StoreKit] 简化ID请求超时，尝试使用完整ID")
                    LogManager.shared.logIAP("简化ID请求超时，尝试使用完整ID")
                    
                    let fullIds = Set(self.productIdManager.allSubscriptionProductIds)
                    self.requestProducts(identifiers: fullIds, isSimplified: false)
                }
            }
        }
    }
    
    /// 取消超时计时器
    private func invalidateTimeoutTimer() {
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
    }
    
    /// 请求产品信息
    /// - Parameters:
    ///   - identifiers: 产品ID集合
    ///   - isSimplified: 是否为简化ID
    private func requestProducts(identifiers: Set<String>, isSimplified: Bool) {
        if identifiers.isEmpty {
            print("🔄 [StoreKit] 没有要请求的产品ID")
            return
        }
        
        // 取消之前的请求（如果有）
        currentRequest?.cancel()
        currentRequest = nil
        
        print("🔄 [StoreKit] 开始请求\(isSimplified ? "简化" : "完整")产品ID: \(identifiers)")
        LogManager.shared.logIAP("请求\(isSimplified ? "简化" : "完整")产品", details: "产品ID: \(identifiers.joined(separator: ", "))")
        
        // 创建请求
        let request = SKProductsRequest(productIdentifiers: identifiers)
        print("🔄 [StoreKit] SKProductsRequest已创建，请求产品数量: \(identifiers.count)")
        request.delegate = self
        
        // 保存当前请求引用
        currentRequest = request
        
        // 设置请求标识
        if isSimplified {
            objc_setAssociatedObject(request, UnsafeRawPointer(bitPattern: 1)!, "simplified", .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        } else {
            objc_setAssociatedObject(request, UnsafeRawPointer(bitPattern: 1)!, "full", .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        // 设置超时计时器
        setupTimeoutTimer()
        
        // 启动请求
        request.start()
        
        print("🔄 [StoreKit] SKProductsRequest.start()已调用，请求开始时间: \(Date())")
        
        // 输出日志
        print("🔄 [StoreKit] 正在请求 \(identifiers.count) 个\(isSimplified ? "简化" : "完整")产品信息...")
        LogManager.shared.log("开始请求\(identifiers.count)个\(isSimplified ? "简化" : "完整")产品", level: .info, category: "StoreKit")
        
        // 如果15秒后仍然没有收到响应，强制尝试完整ID
        if isSimplified {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                guard let self = self, self.currentRequest != nil else { return }
                
                print("⚠️ [StoreKit] 简化ID请求长时间无响应，强制尝试完整ID")
                LogManager.shared.logIAP("简化ID请求长时间无响应，强制尝试完整ID", level: .warning)
                
                // 取消当前请求
                self.currentRequest?.cancel()
                self.currentRequest = nil
                
                // 取消超时计时器
                self.invalidateTimeoutTimer()
                
                // 尝试完整ID
                let fullIds = Set(self.productIdManager.allSubscriptionProductIds)
                self.requestProducts(identifiers: fullIds, isSimplified: false)
            }
        }
    }
    
    /// 获取缓存的产品信息
    func getCachedProduct(productId: String) -> SKProduct? {
        // 先检查是否直接有缓存
        if let product = cachedProducts[productId] {
            return product
        }
        
        // 如果是简化ID，尝试获取对应的完整ID产品
        if let fullId = productIdManager.getFullProductId(from: productId) {
            return cachedProducts[fullId]
        }
        
        return nil
    }
    
    /// 获取所有缓存的产品信息
    func getAllCachedProducts() -> [String: SKProduct] {
        return cachedProducts
    }
    
    /// 强制刷新产品信息
    func forceRefreshProducts() {
        print("🔄 [StoreKit] 强制刷新产品信息")
        LogManager.shared.logIAP("强制刷新产品信息")
        
        // 取消当前请求和计时器
        currentRequest?.cancel()
        currentRequest = nil
        invalidateTimeoutTimer()
        
        // 重新加载产品
        preloadProducts()
    }
    
    /// 预加载所有产品信息 - 仅供强制刷新时使用
    private func preloadProducts() {
        print("🔄 [StoreKit] 开始预加载产品信息")
        LogManager.shared.log("开始预加载产品信息", level: .info, category: "StoreKit")
        
        // 获取所有产品ID (包括完整ID和简化ID)
        let allProductIds = Set(productIdManager.allProductIds)
        
        // 获取所有简化ID
        let allSimplifiedIds = Set(productIdManager.allSimplifiedIds)
        
        // 获取消耗型产品简化ID
        let simplifiedConsumableIds = Set(productIdManager.allSimplifiedConsumableIds)
        
        // 获取订阅产品简化ID
        let simplifiedSubscriptionIds = Set(productIdManager.allSimplifiedSubscriptionIds)
        
        // 获取完整ID
        let fullIds = Set(productIdManager.allConsumableProductIds + productIdManager.allSubscriptionProductIds)
        
        print("🔄 [StoreKit] 产品ID请求前检查 - 总数: \(allProductIds.count)")
        print("🔄 [StoreKit] 将请求以下产品ID: \(allProductIds)")
        
        // 特别记录简化ID和完整ID
        LogManager.shared.logIAP("产品ID信息", details: """
        订阅组ID: \(productIdManager.subscriptionGroupId)
        订阅组名称: \(productIdManager.subscriptionGroupName)
        
        简化消耗型产品ID (\(simplifiedConsumableIds.count)个):
        \(simplifiedConsumableIds.joined(separator: "\n"))
        
        简化订阅产品ID (\(simplifiedSubscriptionIds.count)个):
        \(simplifiedSubscriptionIds.joined(separator: "\n"))
        
        所有简化产品ID (\(allSimplifiedIds.count)个):
        \(allSimplifiedIds.joined(separator: "\n"))
        
        完整产品ID (\(fullIds.count)个):
        \(fullIds.joined(separator: "\n"))
        
        所有产品ID (\(allProductIds.count)个):
        \(allProductIds.joined(separator: "\n"))
        """)
        
        // 记录当前网络状态
        let reachability = try? Reachability()
        if let reachability = reachability {
            print("🔄 [StoreKit] 当前网络状态: \(reachability.connection)")
            LogManager.shared.log("当前网络状态: \(reachability.connection)", level: .info, category: "StoreKit")
        }
        
        // 首先尝试使用所有简化ID请求
        requestProducts(identifiers: allSimplifiedIds, isSimplified: true)
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
        case productIdManager.subscriptionMonthly:
            subscriptionType = .monthly
        case productIdManager.subscriptionQuarterly:
            subscriptionType = .quarterly
        case productIdManager.subscriptionHalfYearly:
            subscriptionType = .halfYearly
        case productIdManager.subscriptionYearly:
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

// MARK: - SKProductsRequestDelegate
extension StoreKitConfiguration: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        // 取消超时计时器
        invalidateTimeoutTimer()
        
        // 清除当前请求引用
        if currentRequest === request {
            currentRequest = nil
        }
        
        // 获取请求类型
        let requestType = objc_getAssociatedObject(request, UnsafeRawPointer(bitPattern: 1)!) as? String ?? "unknown"
        let isSimplifiedRequest = requestType == "simplified"
        
        print("🔄 [StoreKit] 收到\(isSimplifiedRequest ? "简化" : "完整")产品ID响应，时间: \(Date())")
        print("🔄 [StoreKit] 收到的产品数量: \(response.products.count)")
        print("🔄 [StoreKit] 无效的产品ID数量: \(response.invalidProductIdentifiers.count)")
        
        // 记录详细日志
        LogManager.shared.logIAP("收到产品响应", 
                               level: response.products.isEmpty ? .warning : .info,
                               details: """
        请求类型: \(isSimplifiedRequest ? "简化ID" : "完整ID")
        收到产品数: \(response.products.count)
        无效产品数: \(response.invalidProductIdentifiers.count)
        无效的产品ID: \(response.invalidProductIdentifiers)
        """)
        
        // 检查是否有无效的产品ID
        if !response.invalidProductIdentifiers.isEmpty {
            print("⚠️ [StoreKit] 无效的产品ID数量: \(response.invalidProductIdentifiers.count)")
            print("⚠️ [StoreKit] 无效的产品ID列表: \(response.invalidProductIdentifiers.joined(separator: ", "))")
            
            // 对每个无效ID进行详细分析
            for invalidId in response.invalidProductIdentifiers {
                print("⚠️ [StoreKit] 无效ID分析: \(invalidId)")
                print("⚠️ [StoreKit] - 是否在本地ProductIdManager中定义: \(productIdManager.allProductIds.contains(invalidId))")
                
                // 检查ID格式
                if !invalidId.contains(".") {
                    print("⚠️ [StoreKit] - 可能的问题: 产品ID格式不符合要求，缺少Bundle ID前缀")
                }
                
                // 检查是否包含特殊字符
                let specialCharacters = CharacterSet(charactersIn: "~`!@#$%^&*()+=[]{}\\|:;\"'<>,?/")
                if invalidId.rangeOfCharacter(from: specialCharacters) != nil {
                    print("⚠️ [StoreKit] - 可能的问题: 产品ID包含特殊字符")
                }
            }
            
            LogManager.shared.log("无效产品ID: \(response.invalidProductIdentifiers.joined(separator: ", "))", level: .warning, category: "StoreKit")
        }
        
        // 详细记录每个获取到的产品
        print("✅ [StoreKit] 从App Store获取到\(response.products.count)个产品:")
        LogManager.shared.log("从App Store获取到\(response.products.count)个产品", level: .info, category: "StoreKit")
        
        for (index, product) in response.products.enumerated() {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product.priceLocale
            let price = formatter.string(from: product.price) ?? "\(product.price)"
            
            print("  \(index+1). 产品ID: \(product.productIdentifier)")
            print("     标题: \(product.localizedTitle)")
            print("     价格: \(price)")
            print("     本地化描述: \(product.localizedDescription)")
            
            // 添加更多产品详情日志
            print("     价格区域设置: \(product.priceLocale.identifier)")
            if #available(iOS 11.2, *), product.subscriptionPeriod != nil {
                let period = product.subscriptionPeriod!
                let unitStr: String
                switch period.unit {
                case .day: unitStr = "天"
                case .week: unitStr = "周"
                case .month: unitStr = "月"
                case .year: unitStr = "年"
                @unknown default: unitStr = "未知"
                }
                print("     订阅周期: \(period.numberOfUnits) \(unitStr)")
            }
            
            LogManager.shared.log("产品\(index+1): \(product.productIdentifier) - \(product.localizedTitle) - \(price)", level: .debug, category: "StoreKit")
            
            // 详细产品信息记录 - 简化记录以减少UserDefaults存储量
            var productDetails = """
            产品ID: \(product.productIdentifier)
            标题: \(product.localizedTitle)
            价格: \(price)
            """
            
            if #available(iOS 11.2, *), product.subscriptionPeriod != nil {
                let period = product.subscriptionPeriod!
                let unitStr: String
                switch period.unit {
                case .day: unitStr = "天"
                case .week: unitStr = "周"
                case .month: unitStr = "月"
                case .year: unitStr = "年"
                @unknown default: unitStr = "未知"
                }
                productDetails += "\n订阅周期: \(period.numberOfUnits) \(unitStr)"
            }
            
            LogManager.shared.logIAP("有效产品详情", details: productDetails)
        }
        
        if response.products.isEmpty {
            print("❌ [StoreKit] 没有从App Store获取到任何产品，请检查以下可能的原因:")
            print("❌ [StoreKit] 1. App Store Connect中的产品配置是否正确")
            print("❌ [StoreKit] 2. 产品是否已通过Apple审核")
            print("❌ [StoreKit] 3. 沙盒测试账户设置是否正确")
            print("❌ [StoreKit] 4. 应用Bundle ID与产品ID前缀是否匹配")
            print("❌ [StoreKit] 5. 网络连接是否正常")
            LogManager.shared.log("没有获取到任何产品，请检查产品ID配置", level: .error, category: "StoreKit")
            
            // 如果是简化ID请求，尝试使用完整ID
            if isSimplifiedRequest {
                print("🔄 [StoreKit] 简化ID请求未返回产品，尝试使用完整ID")
                LogManager.shared.logIAP("简化ID请求未返回产品，尝试使用完整ID")
                
                let fullIds = Set(productIdManager.allSubscriptionProductIds)
                self.requestProducts(identifiers: fullIds, isSimplified: false)
            }
        }
        
        // 缓存所有有效产品
        for product in response.products {
            cachedProducts[product.productIdentifier] = product
            
            // 如果是简化ID，同时缓存对应的完整ID产品
            if isSimplifiedRequest, let fullId = productIdManager.getFullProductId(from: product.productIdentifier) {
                print("🔄 [StoreKit] 将简化ID产品同时缓存为完整ID: \(product.productIdentifier) -> \(fullId)")
                cachedProducts[fullId] = product
            }
        }
        
        print("✅ [StoreKit] 成功预加载并缓存 \(response.products.count) 个产品信息")
        
        // 发送通知，告知产品已加载完成
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("StoreKitProductsLoaded"), 
                object: nil, 
                userInfo: ["products": self.cachedProducts]
            )
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        // 取消超时计时器
        invalidateTimeoutTimer()
        
        // 清除当前请求引用
        if currentRequest === request {
            currentRequest = nil
        }
        
        // 获取请求类型
        let requestType = objc_getAssociatedObject(request, UnsafeRawPointer(bitPattern: 1)!) as? String ?? "unknown"
        let isSimplifiedRequest = requestType == "simplified"
        
        print("❌ [StoreKit] 加载\(isSimplifiedRequest ? "简化" : "完整")产品信息失败，时间: \(Date())")
        print("❌ [StoreKit] 错误描述: \(error.localizedDescription)")
        print("❌ [StoreKit] 错误详情: \(error)")
        
        // 记录错误详情到日志
        LogManager.shared.logIAP("产品请求失败", 
                               level: .error,
                               details: """
        请求类型: \(isSimplifiedRequest ? "简化ID" : "完整ID")
        错误描述: \(error.localizedDescription)
        错误详情: \(error)
        """)
        
        // 检查网络状态
        let reachability = try? Reachability()
        if let reachability = reachability {
            print("❌ [StoreKit] 网络状态检查: \(reachability.connection)")
        }
        
        // 获取更详细的错误信息
        if let skError = error as? SKError {
            print("  StoreKit错误代码: \(skError.code.rawValue)")
            print("  StoreKit错误域: \(SKErrorDomain)")
            LogManager.shared.log("StoreKit错误代码: \(skError.code.rawValue)", level: .error, category: "StoreKit")
            
            // 输出一些常见错误的解释
            switch skError.code {
            case .unknown:
                print("  错误类型: 未知错误")
                LogManager.shared.log("错误类型: 未知错误", level: .error, category: "StoreKit")
            case .clientInvalid:
                print("  错误类型: 客户端无效，可能需要用户登录iTunes Store")
                LogManager.shared.log("错误类型: 客户端无效，可能需要用户登录iTunes Store", level: .error, category: "StoreKit")
            case .paymentCancelled:
                print("  错误类型: 用户取消了支付")
                LogManager.shared.log("错误类型: 用户取消了支付", level: .error, category: "StoreKit")
            case .paymentInvalid:
                print("  错误类型: 购买标识符无效")
                LogManager.shared.log("错误类型: 购买标识符无效", level: .error, category: "StoreKit")
            case .paymentNotAllowed:
                print("  错误类型: 设备不允许付款")
                LogManager.shared.log("错误类型: 设备不允许付款", level: .error, category: "StoreKit")
            case .storeProductNotAvailable:
                print("  错误类型: 产品不可用于当前店面")
                LogManager.shared.log("错误类型: 产品不可用于当前店面", level: .error, category: "StoreKit")
            case .cloudServicePermissionDenied:
                print("  错误类型: 用户不允许访问云服务信息")
                LogManager.shared.log("错误类型: 用户不允许访问云服务信息", level: .error, category: "StoreKit")
            case .cloudServiceNetworkConnectionFailed:
                print("  错误类型: 设备无法连接到网络")
                LogManager.shared.log("错误类型: 设备无法连接到网络", level: .error, category: "StoreKit")
            case .cloudServiceRevoked:
                print("  错误类型: 用户已撤销对此云服务的使用权限")
                LogManager.shared.log("错误类型: 用户已撤销对此云服务的使用权限", level: .error, category: "StoreKit")
            default:
                print("  错误类型: 其他StoreKit错误")
                LogManager.shared.log("错误类型: 其他StoreKit错误", level: .error, category: "StoreKit")
            }
        }
        
        // 尝试解决方案提示
        print("💡 可能的解决方案:")
        print("  1. 检查网络连接")
        print("  2. 确认产品ID是否正确配置在App Store Connect")
        print("  3. 确认沙盒测试账号设置正确")
        print("  4. 确认应用Bundle ID与App Store Connect匹配")
        
        // 如果是简化ID请求失败，尝试使用完整ID
        if isSimplifiedRequest {
            print("🔄 [StoreKit] 简化ID请求失败，尝试使用完整ID")
            LogManager.shared.logIAP("简化ID请求失败，尝试使用完整ID")
            
            let fullIds = Set(productIdManager.allSubscriptionProductIds)
            self.requestProducts(identifiers: fullIds, isSimplified: false)
        }
    }
} 