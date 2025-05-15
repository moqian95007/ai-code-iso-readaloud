import Foundation

/// 订阅类型枚举
public enum SubscriptionType: String, Codable {
    case none = "none"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case halfYearly = "halfYearly"
    case yearly = "yearly"
    
    var displayName: String {
        switch self {
        case .none:
            return "无订阅"
        case .monthly:
            return "月度会员"
        case .quarterly:
            return "季度会员"
        case .halfYearly:
            return "半年会员"
        case .yearly:
            return "年度会员"
        }
    }
    
    var simplifiedDisplayName: String {
        switch self {
        case .none:
            return "无订阅"
        case .monthly, .quarterly, .halfYearly, .yearly:
            return "PRO会员"
        }
    }
}

/// 用户模型，用于存储用户信息
struct User: Codable, Identifiable {
    /// 用户唯一标识
    var id: Int
    /// 用户名
    var username: String
    /// 邮箱地址
    var email: String
    /// 手机号码，可选
    var phone: String?
    /// 用户认证令牌
    var token: String?
    /// 注册日期
    var registerDate: Date?
    /// 最后登录时间
    var lastLogin: Date?
    /// 用户状态
    var status: String
    
    /// 用户令牌是否有效
    var isTokenValid: Bool {
        return token != nil && !token!.isEmpty
    }
    
    /// 用户是否有有效的订阅
    var hasActiveSubscription: Bool {
        return SubscriptionRepository.shared.getActiveSubscription(for: id) != nil
    }
    
    /// 获取用户当前的订阅类型
    var subscriptionType: SubscriptionType {
        return SubscriptionRepository.shared.getActiveSubscription(for: id)?.type ?? .none
    }
    
    /// 获取订阅结束日期
    var subscriptionEndDate: Date? {
        return SubscriptionRepository.shared.getActiveSubscription(for: id)?.endDate
    }
} 