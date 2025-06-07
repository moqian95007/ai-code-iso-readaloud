import Foundation
import Combine
import StoreKit
import UIKit
import SwiftUI
import ObjectiveC

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
        
        print("开始加载导入产品 - ImportPurchaseService")
        
        // 先检查StoreKitConfiguration中是否已有缓存的产品
        let cachedProducts = StoreKitConfiguration.shared.getAllCachedProducts()
        
        // 使用ProductIdManager获取简化导入产品ID
        let importProductIds = ProductIdManager.shared.allSimplifiedConsumableIds
        
        print("导入产品ID: \(importProductIds.joined(separator: ", "))")
        
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
            
            // 添加关联对象标识，以便StoreKitConfiguration能区分导入请求和订阅请求
            objc_setAssociatedObject(productRequest!, UnsafeRawPointer(bitPattern: 2)!, "import_products", .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            productRequest?.start()
            
            // 添加自定义超时处理，避免StoreKitConfiguration的通用超时处理
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self = self else { return }
                
                // 如果仍在加载中且产品列表为空，则认为超时
                if self.isLoading && self.products.isEmpty {
                    print("⚠️ 导入产品请求超时 (ImportPurchaseService)")
                    
                    // 取消之前的请求
                    self.productRequest?.cancel()
                    self.productRequest = nil
                    
                    // 更新UI状态
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "加载产品超时，请检查网络连接或稍后再试"
                        
                        // 发送通知，通知UI更新
                        NotificationCenter.default.post(name: NSNotification.Name("ImportProductsUpdated"), object: nil)
                    }
                }
            }
        }
    }
    
    /// 购买导入次数
    /// - Parameters:
    ///   - productId: 产品ID
    ///   - completion: 完成回调
    func purchaseImportCount(productId: String, completion: @escaping (Result<Int, Error>) -> Void) {
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
    
    /// 处理完成的购买交易
    private func handlePurchasedTransaction(_ transaction: SKPaymentTransaction) {
        // 获取产品ID
        let productId = transaction.payment.productIdentifier
        print("成功购买产品: \(productId)")
        
        // 首先检查产品ID是否为导入类产品
        let productType = ProductIdManager.shared.getProductType(for: productId)
        if productType != .consumable {
            print("非导入类产品: \(productId)，跳过处理")
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        
        // 根据产品ID确定导入次数
        var importCount = 1
        
        switch productId {
        case ProductIdManager.shared.importSingle, ProductIdManager.shared.appStoreImportSingle:
            importCount = 1
        case ProductIdManager.shared.importThree, ProductIdManager.shared.appStoreImportThree:
            importCount = 3
        case ProductIdManager.shared.importFive, ProductIdManager.shared.appStoreImportFive:
            importCount = 5
        case ProductIdManager.shared.importTen, ProductIdManager.shared.appStoreImportTen:
            importCount = 10
        default:
            print("未知产品ID: \(productId)")
            importCount = 1
        }
        
        print("购买导入次数: \(importCount)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 始终更新本地存储的导入次数，确保登录状态切换时导入次数一致
            self.addGuestImportCount(count: importCount)
            
            // 如果用户已登录，还需要更新用户对象并同步到服务器
            if let user = self.userManager.currentUser {
                // 创建更新后的用户对象，使用本地存储的导入次数
                var updatedUser = user
                let localCount = UserDefaults.standard.integer(forKey: "guestRemainingImportCount")
                updatedUser.remainingImportCount = localCount
                
                // 更新用户信息
                self.userManager.updateUser(updatedUser)
                
                // 如果用户已登录且有token，同步导入次数到服务器
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
            }
            
            // 调用成功回调
            self.purchaseCompletionHandler?(.success(importCount))
            
            // 清除完成回调
            self.purchaseCompletionHandler = nil
        }
        
        // 完成交易
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    /// 为Guest用户添加导入次数
    private func addGuestImportCount(count: Int) {
        // 从UserDefaults获取现有的导入次数
        let currentCount = UserDefaults.standard.integer(forKey: "guestRemainingImportCount")
        let actualCurrentCount = currentCount > 0 ? currentCount : 1
        
        // 累加新购买的次数
        let newCount = actualCurrentCount + count
        
        // 保存到UserDefaults
        UserDefaults.standard.set(newCount, forKey: "guestRemainingImportCount")
        print("已为Guest用户添加导入次数，现有次数: \(newCount)")
        
        // 发送通知刷新UI
        NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
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