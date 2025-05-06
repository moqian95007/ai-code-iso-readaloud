import Foundation

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
} 