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
    
    // 产品ID
    let singleImportProductId = "top.ai-toolkit.readaloud.import.single"
    let threeImportsProductId = "top.ai-toolkit.readaloud.import.three"
    let fiveImportsProductId = "top.ai-toolkit.readaloud.import.five"
    let tenImportsProductId = "top.ai-toolkit.readaloud.import.ten"
    
    // 导入次数对应字典
    let importCountsMap: [String: Int] = [
        "top.ai-toolkit.readaloud.import.single": 1,
        "top.ai-toolkit.readaloud.import.three": 3,
        "top.ai-toolkit.readaloud.import.five": 5,
        "top.ai-toolkit.readaloud.import.ten": 10
    ]
    
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
            formatter.locale = product.priceLocale
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
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    /// 加载导入次数购买产品
    func loadProducts() {
        isLoading = true
        errorMessage = nil
        
        let productIds = Set([singleImportProductId, threeImportsProductId, fiveImportsProductId, tenImportsProductId])
        productRequest = SKProductsRequest(productIdentifiers: productIds)
        productRequest?.delegate = self
        productRequest?.start()
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
        
        // 查找对应的产品
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isLoading = false
            
            // 检查是否有有效产品
            if response.products.isEmpty {
                self.errorMessage = "未找到可用的导入次数产品"
                return
            }
            
            // 处理产品信息
            var products: [ImportProduct] = []
            
            for product in response.products {
                if let count = self.importCountsMap[product.productIdentifier] {
                    products.append(ImportProduct(
                        id: product.productIdentifier,
                        count: count,
                        product: product
                    ))
                }
            }
            
            self.products = products.sorted(by: { $0.count < $1.count })
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
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
        
        // 获取对应的导入次数
        guard let importCount = importCountsMap[productId] else {
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