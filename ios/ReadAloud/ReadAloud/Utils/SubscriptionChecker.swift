import Foundation
import Combine
import UIKit
import SwiftUI

/// 不同功能的会员权限等级
enum FeatureTier {
    case free        // 免费用户可用
    case premium     // 需要会员订阅
}

/// 具体功能类型
enum FeatureType: String {
    // 基础功能
    case basicVoiceSynthesis = "基本语音合成"   // 基础语音合成
    case standardReadingSpeed = "标准朗读速度"  // 标准朗读速度
    case basicFilters = "基本筛选功能"         // 基本筛选功能
    case basicExport = "基本导出功能"          // 基本导出功能
    
    // 高级功能
    case premiumVoices = "高级语音"            // 高级语音
    case customReadingSpeed = "自定义朗读速度"  // 自定义朗读速度范围扩大
    case batchExport = "批量导出"              // 批量导出
    case translation = "实时翻译"              // 实时翻译
    case unlimitedArticles = "无限文章"        // 无限文章导入
    case advancedFilters = "高级筛选"          // 高级筛选
    case customerSupport = "专属客服"          // 专属客服支持
    
    /// 获取功能所需的权限等级
    var requiredTier: FeatureTier {
        switch self {
        case .basicVoiceSynthesis, .standardReadingSpeed, .basicFilters, .basicExport:
            return .free
        case .premiumVoices, .customReadingSpeed, .batchExport, .translation, 
             .unlimitedArticles, .advancedFilters, .customerSupport:
            return .premium
        }
    }
    
    /// 功能描述
    var description: String {
        return self.rawValue
    }
}

/// 订阅检查工具类
class SubscriptionChecker {
    // 单例模式
    static let shared = SubscriptionChecker()
    
    // 用户管理器
    private let userManager = UserManager.shared
    
    // 发布用户会员状态变化
    @Published var hasPremiumAccess: Bool = false
    
    // 私有初始化方法
    private init() {
        // 监听用户状态变化
        userManager.$currentUser
            .sink { [weak self] user in
                if let user = user {
                    // 用户已登录，从用户信息获取订阅状态
                    self?.hasPremiumAccess = user.hasActiveSubscription
                } else {
                    // 用户未登录，从UserDefaults获取订阅状态
                    let status = UserDefaults.standard.bool(forKey: "guestHasPremiumAccess")
                    self?.hasPremiumAccess = status
                    
                    // 检查tempSubscriptionInfo是否存在
                    if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo") {
                        if let endDateValue = subscriptionInfo["endDate"] as? TimeInterval {
                            let endDate = Date(timeIntervalSince1970: endDateValue)
                        }
                    }
                }
            }
            .store(in: &cancellables)
            
        // 检查是否有已保存的Guest订阅状态
        if userManager.currentUser == nil {
            let status = UserDefaults.standard.bool(forKey: "guestHasPremiumAccess")
            hasPremiumAccess = status
        }
            
        // 监听订阅状态更新通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SubscriptionStatusUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let user = self?.userManager.currentUser {
                // 用户已登录，从用户信息更新订阅状态
                self?.hasPremiumAccess = user.hasActiveSubscription
            } else {
                // 用户未登录，从UserDefaults更新订阅状态
                let status = UserDefaults.standard.bool(forKey: "guestHasPremiumAccess")
                self?.hasPremiumAccess = status
                
                // 检查tempSubscriptionInfo是否存在
                if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo") {
                    if let endDateValue = subscriptionInfo["endDate"] as? TimeInterval {
                        let endDate = Date(timeIntervalSince1970: endDateValue)
                    }
                }
            }
        }
    }
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    /// 检查用户是否有权限使用特定功能
    /// - Parameter feature: 功能类型
    /// - Returns: 是否有访问权限
    func canAccess(_ feature: FeatureType) -> Bool {
        // 免费功能直接返回true
        if feature.requiredTier == .free {
            return true
        }
        
        // 检查用户是否有高级权限
        return hasPremiumAccess
    }
    
    /// 检查文章数量限制
    /// - Parameter currentCount: 当前文章数量
    /// - Returns: 是否超出限制
    func checkArticleLimit(currentCount: Int) -> Bool {
        // 付费会员无限制
        if hasPremiumAccess {
            return true
        }
        
        // 免费用户限制20篇文章
        let freeLimit = 20
        return currentCount < freeLimit
    }
    
    /// 获取文章限制数量
    /// - Returns: 文章限制数量，-1表示无限制
    func getArticleLimit() -> Int {
        return hasPremiumAccess ? -1 : 20
    }
    
    /// 显示功能受限提示
    /// - Parameters:
    ///   - feature: 功能类型
    ///   - presentingViewController: 弹出提示的控制器
    ///   - completion: 完成回调
    func showPremiumFeatureAlert(for feature: FeatureType, presentingViewController: UIViewController, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(
            title: "升级到会员",
            message: "「\(feature.description)」是会员专属功能，订阅会员即可解锁全部高级功能。",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "订阅会员", style: .default) { _ in
            // 跳转到订阅页面
            let subscriptionVC = UIHostingController(rootView: SubscriptionView(isPresented: .constant(true)))
            presentingViewController.present(subscriptionVC, animated: true, completion: nil)
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completion?()
        })
        
        presentingViewController.present(alert, animated: true, completion: nil)
    }
} 