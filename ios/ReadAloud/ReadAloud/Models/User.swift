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
            return "subscription_none".localized
        case .monthly:
            return "subscription_monthly".localized
        case .quarterly:
            return "subscription_quarterly".localized
        case .halfYearly:
            return "subscription_half_yearly".localized
        case .yearly:
            return "subscription_yearly".localized
        }
    }
    
    var simplifiedDisplayName: String {
        switch self {
        case .none:
            return "subscription_none".localized
        case .monthly, .quarterly, .halfYearly, .yearly:
            return "pro_member".localized
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
    /// 剩余可导入本地文档的数量
    var remainingImportCount: Int = 1
    
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
    
    // CodingKeys枚举，处理字段命名差异
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case phone
        case token
        case registerDate = "register_date"
        case lastLogin = "last_login"
        case status
        case remainingImportCount = "remaining_import_count"
    }
} 