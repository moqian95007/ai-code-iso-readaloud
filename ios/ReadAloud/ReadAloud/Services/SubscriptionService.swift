import Foundation
import Combine
import StoreKit
import UIKit
import SwiftUI

/// 订阅服务，作为业务逻辑与StoreKit之间的中间层
class SubscriptionService: ObservableObject {
    // 单例模式
    static let shared = SubscriptionService()
    
    // 订阅管理器
    private let subscriptionManager = SubscriptionManager.shared
    
    // 用户管理器
    private let userManager = UserManager.shared
    
    // 订阅仓库
    private let subscriptionRepository = SubscriptionRepository.shared
    
    // 订阅检查器
    private let subscriptionChecker = SubscriptionChecker.shared
    
    // 发布订阅状态
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var products: [SubscriptionProduct] = []
    @Published var selectedProductId: String? = nil
    
    // 添加恢复购买标记，用于避免重复处理
    private var isProcessingRestore: Bool = false
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 私有初始化方法
    private init() {
        // 订阅订阅管理器状态变化
        subscriptionManager.$isLoading
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)
        
        subscriptionManager.$errorMessage
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
        
        subscriptionManager.$availableProducts
            .assign(to: \.products, on: self)
            .store(in: &cancellables)
    }
    
    /// 加载订阅产品
    func loadProducts() {
        print("========== SubscriptionService.loadProducts 开始 ==========")
        
        // 清除旧的错误信息
        errorMessage = nil
        
        // 检查环境
        let isTestEnvironment = StoreKitConfiguration.shared.isTestEnvironment
        print("当前StoreKit环境: \(isTestEnvironment ? "沙盒测试环境" : "生产环境")")
        
        // 检查是否有缓存的产品
        let cachedProducts = StoreKitConfiguration.shared.getAllCachedProducts()
        let subscriptionProductIds = ProductIdManager.shared.allSubscriptionProductIds
        print("缓存的产品总数: \(cachedProducts.count)")
        print("订阅产品ID列表: \(subscriptionProductIds.joined(separator: ", "))")
        
        // 检查缓存中有多少订阅产品
        let cachedSubscriptionProducts = subscriptionProductIds.compactMap { cachedProducts[$0] }
        print("缓存中的订阅产品数: \(cachedSubscriptionProducts.count)")
        
        // 调用订阅管理器加载产品
        print("正在请求最新的订阅产品...")
        subscriptionManager.loadProducts()
        
        // 添加日志监控追踪App Store API请求结果
        print("设置App Store产品获取超时监控...")
        
        // 在所有环境中，如果3秒后仍然没有产品，发送通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            
            if self.products.isEmpty && !self.isLoading {
                print("⚠️ 3秒后仍未获取到产品，可能存在网络问题或产品配置问题")
                print("缓存产品数量: \(StoreKitConfiguration.shared.getAllCachedProducts().count)")
                print("订阅管理器产品数量: \(self.subscriptionManager.availableProducts.count)")
                
                // 检查收据状态
                if let receiptURL = Bundle.main.appStoreReceiptURL,
                   let receiptData = try? Data(contentsOf: receiptURL) {
                    print("收据数据存在，长度: \(receiptData.count)")
                } else {
                    print("❌ 无法获取App Store收据")
                }
                
                // 构建详细的错误信息
                var errorInfo = "无法从App Store获取产品信息"
                if isTestEnvironment {
                    errorInfo += "，请检查沙盒环境配置"
                } else {
                    errorInfo += "，请检查网络连接或产品配置"
                }
                self.errorMessage = errorInfo
                
                // 发送通知，通知UI更新
                NotificationCenter.default.post(
                    name: NSNotification.Name("SubscriptionProductsUpdated"),
                    object: nil,
                    userInfo: ["error": errorInfo]
                )
            }
        }
        
        print("========== SubscriptionService.loadProducts 结束 ==========")
    }
    
    /// 购买订阅
    /// - Parameters:
    ///   - productId: 产品ID
    ///   - completion: 完成回调
    func purchaseSubscription(productId: String, completion: @escaping (Result<SubscriptionType, Error>) -> Void) {
        // 确保用户已登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            completion(.failure(NSError(domain: "SubscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先登录再订阅会员"])))
            return
        }
        
        // 使用订阅管理器购买 - 直接传递完成回调，不需要额外操作
        // 因为SubscriptionManager已经会在处理交易时创建订阅记录
        subscriptionManager.purchaseSubscription(productId: productId, completion: completion)
        
        // 不再需要以下代码，避免重复创建订阅记录
        /*
        subscriptionManager.purchaseSubscription(productId: productId) { [weak self] result in
            switch result {
            case .success(let subscriptionType):
                // 创建新的订阅记录
                self?.createSubscriptionRecord(for: user.id, type: subscriptionType, productId: productId)
                completion(.success(subscriptionType))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        */
    }
    
    /// 恢复购买
    /// - Parameter completion: 完成回调
    func restorePurchases(completion: @escaping (Result<SubscriptionType?, Error>) -> Void) {
        print("========== SubscriptionService.restorePurchases 开始 ==========")
        
        // 确保用户已登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，无法恢复购买")
            completion(.failure(NSError(domain: "SubscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先登录再恢复购买"])))
            return
        }
        
        print("用户已登录，用户ID: \(user.id), 用户名: \(user.username)")
        
        // 检查是否已经在处理恢复购买，避免重复处理
        if isProcessingRestore {
            print("警告: 已经在处理恢复购买，忽略重复请求")
            return
        }
        
        // 标记开始处理恢复购买
        isProcessingRestore = true
        
        // 使用订阅管理器恢复购买
        subscriptionManager.restorePurchases { [weak self] result in
            guard let self = self else { return }
            
            // 处理完成后重置状态
            defer {
                self.isProcessingRestore = false
                print("========== SubscriptionService.restorePurchases 结束 ==========")
            }
            
            switch result {
            case .success(let subscriptionType):
                print("恢复购买成功，订阅类型: \(String(describing: subscriptionType))")
                
                if let type = subscriptionType, type != .none {
                    print("有效的订阅类型: \(type.rawValue)")
                    
                    // 获取用户现有的订阅
                    let existingSubscriptions = SubscriptionRepository.shared.getSubscriptions(for: user.id)
                    
                    // 检查是否已有相同类型的活跃订阅
                    let hasActiveSubscription = existingSubscriptions.contains { 
                        $0.type == type && $0.isActive && $0.isValid 
                    }
                    
                    if !hasActiveSubscription {
                        print("未发现相同类型的活跃订阅，创建新的订阅记录")
                        // 创建恢复的订阅记录
                        self.createSubscriptionRecord(for: user.id, type: type, productId: "restored_\(type.rawValue)")
                        print("已创建恢复的订阅记录，用户ID: \(user.id), 类型: \(type.rawValue)")
                        // 注意：createSubscriptionRecord会调用addSubscription，会自动触发同步
                    } else {
                        print("已存在相同类型的活跃订阅，跳过创建")
                        // 已存在相同类型的活跃订阅，需要手动触发同步
                        // 因为没有调用addSubscription，所以需要手动同步
                        SubscriptionRepository.shared.syncSubscriptionsToRemote()
                    }
                    
                    // 发送订阅状态更新通知，确保UI更新
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                        print("已发送订阅状态更新通知")
                    }
                } else {
                    print("没有找到有效的订阅")
                }
                
                completion(.success(subscriptionType))
            case .failure(let error):
                print("恢复购买失败: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// 创建订阅记录
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - type: 订阅类型
    ///   - productId: 产品ID
    private func createSubscriptionRecord(for userId: Int, type: SubscriptionType, productId: String) {
        let startDate = Date()
        var endDate: Date
        
        // 计算订阅结束日期
        switch type {
        case .monthly:
            endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)!
        case .quarterly:
            endDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate)!
        case .halfYearly:
            endDate = Calendar.current.date(byAdding: .month, value: 6, to: startDate)!
        case .yearly:
            endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate)!
        default:
            // 对于无效的订阅类型，不创建记录
            return
        }
        
        // 创建订阅记录
        let subscription = Subscription(
            userId: userId,
            type: type,
            startDate: startDate,
            endDate: endDate,
            subscriptionId: "\(productId)_\(UUID().uuidString)"
        )
        
        // 添加到订阅仓库
        subscriptionRepository.addSubscription(subscription)
    }
    
    /// 检查功能是否可用，并在需要时显示升级提示
    /// - Parameters:
    ///   - feature: 功能类型
    ///   - viewController: 视图控制器
    ///   - completion: 完成回调，传入是否有权限
    func checkFeatureAvailability(feature: FeatureType, viewController: UIViewController? = nil, completion: ((Bool) -> Void)? = nil) {
        let hasAccess = subscriptionChecker.canAccess(feature)
        
        if !hasAccess && viewController != nil {
            subscriptionChecker.showPremiumFeatureAlert(for: feature, presentingViewController: viewController!) {
                completion?(false)
            }
        } else {
            completion?(hasAccess)
        }
        
        return
    }
    
    /// 检查文章数量限制
    /// - Parameters:
    ///   - currentCount: 当前文章数量
    ///   - viewController: 视图控制器
    ///   - completion: 完成回调，传入是否超出限制
    func checkArticleLimit(currentCount: Int, viewController: UIViewController? = nil, completion: ((Bool) -> Void)? = nil) {
        let withinLimit = subscriptionChecker.checkArticleLimit(currentCount: currentCount)
        
        if !withinLimit && viewController != nil {
            // 显示文章数量限制提示
            let alert = UIAlertController(
                title: "文章数量已达上限",
                message: "免费用户最多可添加20篇文章，升级到会员可无限添加文章。",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "订阅会员", style: .default) { _ in
                // 跳转到订阅页面
                let subscriptionVC = UIHostingController(rootView: SubscriptionView(isPresented: .constant(true)))
                viewController!.present(subscriptionVC, animated: true, completion: nil)
            })
            
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                completion?(false)
            })
            
            viewController!.present(alert, animated: true, completion: nil)
        } else {
            completion?(withinLimit)
        }
    }
} 