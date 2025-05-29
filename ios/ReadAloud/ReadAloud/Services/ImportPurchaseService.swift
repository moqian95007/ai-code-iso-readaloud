import Foundation
import Combine
import StoreKit
import UIKit
import SwiftUI

/// 导入次数购买服务
class ImportPurchaseService: NSObject, ObservableObject {
    // 单例模式
    static let shared = ImportPurchaseService()
    
    // 用户管理器
    private let userManager = UserManager.shared
    
    // 产品ID管理器
    private let productIdManager = ProductIdManager.shared
    
    // 导入次数对应字典
    var importCountsMap: [String: Int] {
        return productIdManager.importCountsMap
    }
    
    // 产品结构
    struct ImportProduct {
        let id: String
        let count: Int
        let product: SKProduct
        let localizedPrice: String
        
        init(id: String, count: Int, product: SKProduct) {
            self.id = id
            self.count = count
            self.product = product
            
            // 格式化价格
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            
            // 检查区域是否为中国
            let regionCode = product.priceLocale.regionCode ?? Locale.current.regionCode ?? ""
            
            if regionCode == "CN" {
                // 中国区域使用原始价格区域(人民币)
                formatter.locale = product.priceLocale
            } else {
                // 非中国区域统一使用美元
                formatter.locale = Locale(identifier: "en_US")
                formatter.currencyCode = "USD"
            }
            
            self.localizedPrice = formatter.string(from: product.price) ?? "\(product.price)"
        }
    }
    
    // 发布订阅状态
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var products: [ImportProduct] = []
    @Published var selectedProductId: String? = nil
    
    // StoreKit相关
    private var productRequest: SKProductsRequest?
    private var purchaseCompletionHandler: ((Result<Int, Error>) -> Void)? = nil
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 私有初始化方法
    private override init() {
        super.init()
        // 设置SKPaymentTransactionObserver
        SKPaymentQueue.default().add(self)
        
        // 观察产品加载完成的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProductsLoaded(_:)),
            name: NSNotification.Name("StoreKitProductsLoaded"),
            object: nil
        )
        
        // 初次尝试从缓存中获取产品
        checkCachedProducts()
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
        // 移除观察者
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 从缓存中获取产品信息
    private func checkCachedProducts() {
        let cachedProducts = StoreKitConfiguration.shared.getAllCachedProducts()
        
        // 如果缓存中有产品，则直接使用
        if !cachedProducts.isEmpty {
            processProducts(Array(cachedProducts.values))
        }
    }
    
    /// 处理StoreKitProductsLoaded通知
    @objc private func handleProductsLoaded(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let products = userInfo["products"] as? [String: SKProduct] else {
            return
        }
        
        // 处理加载的产品
        processProducts(Array(products.values))
    }
    
    /// 处理产品列表
    private func processProducts(_ skProducts: [SKProduct]) {
        // 处理产品信息
        var importProducts: [ImportProduct] = []
        
        // 详细记录处理的产品
        print("⏱️ 开始处理获取到的导入类产品，共\(skProducts.count)个")
        
        for product in skProducts {
            // 简化导入次数判断逻辑
            var count: Int = 0
            
            // 直接根据产品ID判断
            switch product.productIdentifier {
            case "import.single":
                count = 1
                print("找到单次导入产品: \(product.localizedTitle)")
            case "import.three":
                count = 3
                print("找到三次导入产品: \(product.localizedTitle)")
            case "import.five":
                count = 5
                print("找到五次导入产品: \(product.localizedTitle)")
            case "import.ten":
                count = 10
                print("找到十次导入产品: \(product.localizedTitle)")
            default:
                print("忽略未知产品: \(product.productIdentifier)")
                continue
            }
            
            importProducts.append(ImportProduct(
                id: product.productIdentifier,
                count: count,
                product: product
            ))
            
            print("成功添加产品: \(product.productIdentifier), 导入次数: \(count)")
        }
        
        // 更新产品列表
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 记录更新前后的产品数量
            let oldCount = self.products.count
            self.products = importProducts.sorted(by: { $0.count < $1.count })
            let newCount = self.products.count
            print("🔄 更新导入产品列表: 之前\(oldCount)个产品，现在\(newCount)个产品")
            
            // 记录所有找到的产品
            if !self.products.isEmpty {
                print("✅ 可用导入产品列表:")
                for (index, product) in self.products.enumerated() {
                    print("  \(index+1). 导入\(product.count)次 - \(product.localizedPrice)")
                }
            }
            
            self.isLoading = false
            
            if self.products.isEmpty {
                self.errorMessage = "未找到可用的导入次数产品"
                print("❌ 未找到任何可用的导入次数产品")
            } else {
                self.errorMessage = nil
            }
            
            // 发送通知，通知UI更新
            NotificationCenter.default.post(name: NSNotification.Name("ImportProductsUpdated"), object: nil)
        }
    }
    
    /// 加载导入次数购买产品
    func loadProducts() {
        isLoading = true
        errorMessage = nil
        
        // 先检查StoreKitConfiguration中是否已有缓存的产品
        let cachedProducts = StoreKitConfiguration.shared.getAllCachedProducts()
        
        // 直接使用四种简化导入产品ID
        let importProductIds = ["import.single", "import.three", "import.five", "import.ten"]
        
        // 检查是否所有产品都已在缓存中
        let allProductsCached = importProductIds.allSatisfy { cachedProducts[$0] != nil }
        
        if allProductsCached && !cachedProducts.isEmpty {
            // 如果所有产品都已缓存，直接使用缓存的产品
            print("使用缓存的导入产品信息")
            let relevantProducts = importProductIds.compactMap { cachedProducts[$0] }
            processProducts(relevantProducts)
        } else {
            // 否则发起请求，使用简化版产品ID
            print("请求新的导入产品信息(简化ID)")
            let productIds = Set(importProductIds)
            productRequest = SKProductsRequest(productIdentifiers: productIds)
            productRequest?.delegate = self
            productRequest?.start()
        }
    }
    
    /// 购买导入次数
    /// - Parameters:
    ///   - productId: 产品ID
    ///   - completion: 完成回调
    func purchaseImportCount(productId: String, completion: @escaping (Result<Int, Error>) -> Void) {
        // 验证用户是否已登录
        guard userManager.isLoggedIn, let _ = userManager.currentUser else {
            completion(.failure(NSError(domain: "ImportPurchaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先登录再购买导入次数"])))
            return
        }
        
        // 首先检查缓存中是否有此产品
        if let cachedProduct = StoreKitConfiguration.shared.getCachedProduct(productId: productId) {
            // 使用缓存的产品进行购买
            purchaseCompletionHandler = completion
            let payment = SKPayment(product: cachedProduct)
            SKPaymentQueue.default().add(payment)
            return
        }
        
        // 如果缓存中没有，则查找当前加载的产品列表
        guard let product = products.first(where: { $0.id == productId })?.product else {
            completion(.failure(NSError(domain: "ImportPurchaseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到对应的产品"])))
            return
        }
        
        // 存储完成回调
        purchaseCompletionHandler = completion
        
        // 创建支付请求
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
}

// MARK: - SKProductsRequestDelegate
extension ImportPurchaseService: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        // 检查是否有无效的产品ID
        if !response.invalidProductIdentifiers.isEmpty {
            print("⚠️ 导入产品 - 无效的产品ID: \(response.invalidProductIdentifiers.joined(separator: ", "))")
        }
        
        // 详细记录每个获取到的产品
        print("✅ 从App Store获取到\(response.products.count)个导入类产品:")
        for (index, product) in response.products.enumerated() {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product.priceLocale
            let price = formatter.string(from: product.price) ?? "\(product.price)"
            
            print("  \(index+1). 产品ID: \(product.productIdentifier)")
            print("     标题: \(product.localizedTitle)")
            print("     价格: \(price)")
            print("     本地化描述: \(product.localizedDescription)")
        }
        
        if response.products.isEmpty {
            print("❌ 没有从App Store获取到任何导入产品，请检查产品ID配置和App Store Connect设置")
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.isLoading = false
                self.errorMessage = "未找到可用的导入次数产品"
            }
            return
        }
        
        // 处理获取到的产品
        processProducts(response.products)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("❌ 加载导入产品信息失败: \(error.localizedDescription)")
        
        // 获取更详细的错误信息
        if let skError = error as? SKError {
            print("  StoreKit错误代码: \(skError.code.rawValue)")
            print("  StoreKit错误域: \(SKErrorDomain)")
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isLoading = false
            self.errorMessage = "加载产品失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - SKPaymentTransactionObserver
extension ImportPurchaseService: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                // 购买成功
                handlePurchasedTransaction(transaction)
                
            case .failed:
                // 购买失败
                handleFailedTransaction(transaction)
                
            case .restored:
                // 恢复购买 (对于消费型产品通常不需要)
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .deferred, .purchasing:
                // 处理中，不需要操作
                break
                
            @unknown default:
                break
            }
        }
    }
    
    /// 处理购买成功的交易
    private func handlePurchasedTransaction(_ transaction: SKPaymentTransaction) {
        let productId = transaction.payment.productIdentifier
        
        // 简化获取导入次数逻辑
        var importCount: Int
        
        // 直接根据产品ID判断次数
        switch productId {
        case "import.single":
            importCount = 1
        case "import.three":
            importCount = 3
        case "import.five":
            importCount = 5
        case "import.ten":
            importCount = 10
        default:
            // 未找到对应的导入次数，完成交易并报错
            SKPaymentQueue.default().finishTransaction(transaction)
            
            DispatchQueue.main.async { [weak self] in
                self?.purchaseCompletionHandler?(.failure(NSError(domain: "ImportPurchaseService", code: 3, userInfo: [NSLocalizedDescriptionKey: "无效的产品ID"])))
                self?.purchaseCompletionHandler = nil
            }
            
            return
        }
        
        // 增加用户的导入次数
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 更新用户的导入次数
            if let user = self.userManager.currentUser {
                // 创建更新后的用户对象
                var updatedUser = user
                updatedUser.remainingImportCount += importCount
                
                // 更新用户信息
                self.userManager.updateUser(updatedUser)
                
                // 直接调用完成回调，不再调用refreshUserStatus
                // 这样避免触发订阅处理逻辑
                self.purchaseCompletionHandler?(.success(importCount))
                
                // 只同步导入次数，不更新订阅状态
                // 使用单独的API同步导入次数
                if let token = updatedUser.token, !token.isEmpty {
                    DispatchQueue.global().async {
                        // 将数据转换为JSON
                        let dataValue = String(updatedUser.remainingImportCount)
                        
                        // 使用NetworkManager保存数据
                        NetworkManager.shared.saveUserData(
                            userId: updatedUser.id, 
                            token: token, 
                            dataKey: "remaining_import_count", 
                            dataValue: dataValue
                        )
                        .sink(
                            receiveCompletion: { result in
                                if case .failure(let error) = result {
                                    print("同步导入次数失败: \(error)")
                                }
                            },
                            receiveValue: { message in
                                print("同步导入次数成功: \(message)")
                            }
                        )
                        .store(in: &self.cancellables)
                    }
                }
            } else {
                // 如果无法获取用户，报错
                self.purchaseCompletionHandler?(.failure(NSError(domain: "ImportPurchaseService", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法更新用户信息"])))
            }
            
            // 清除完成回调
            self.purchaseCompletionHandler = nil
        }
        
        // 完成交易
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    /// 处理购买失败的交易
    private func handleFailedTransaction(_ transaction: SKPaymentTransaction) {
        // 完成交易
        SKPaymentQueue.default().finishTransaction(transaction)
        
        // 获取错误信息
        let error = transaction.error ?? NSError(domain: "ImportPurchaseService", code: 5, userInfo: [NSLocalizedDescriptionKey: "购买失败，请稍后再试"])
        
        DispatchQueue.main.async { [weak self] in
            // 调用失败回调
            self?.purchaseCompletionHandler?(.failure(error))
            
            // 清除完成回调
            self?.purchaseCompletionHandler = nil
        }
    }
} 