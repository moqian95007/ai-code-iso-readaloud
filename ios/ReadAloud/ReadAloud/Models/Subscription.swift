import Foundation

/// 订阅模型，用于存储订阅信息
struct Subscription: Codable, Identifiable {
    /// 订阅唯一标识
    var id: UUID
    /// 关联的用户ID
    var userId: Int
    /// 订阅类型
    var type: SubscriptionType
    /// 订阅开始日期
    var startDate: Date
    /// 订阅结束日期
    var endDate: Date
    /// 订阅标识符（来自App Store）
    var subscriptionId: String
    /// 是否为当前活跃订阅
    var isActive: Bool
    /// 创建时间
    var createdAt: Date
    /// 最后更新时间
    var updatedAt: Date
    
    /// 订阅是否有效
    var isValid: Bool {
        // 必须同时满足：是活跃的(isActive为true)且未过期
        return isActive && endDate > Date()
    }
    
    /// 创建新的订阅
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - type: 订阅类型
    ///   - startDate: 开始日期
    ///   - endDate: 结束日期
    ///   - subscriptionId: 订阅标识符
    init(userId: Int, type: SubscriptionType, startDate: Date, endDate: Date, subscriptionId: String) {
        self.id = UUID()
        self.userId = userId
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.subscriptionId = subscriptionId
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Codable实现
    
    /// 解码器键
    private enum CodingKeys: String, CodingKey {
        case id, userId, type, startDate, endDate, subscriptionId, isActive, createdAt, updatedAt
    }
    
    /// 从解码器初始化
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let idString = try container.decode(String.self, forKey: .id)
        if let uuid = UUID(uuidString: idString) {
            id = uuid
        } else {
            id = UUID()
        }
        
        userId = try container.decode(Int.self, forKey: .userId)
        type = try container.decode(SubscriptionType.self, forKey: .type)
        
        // 处理日期
        let startDateString = try container.decode(String.self, forKey: .startDate)
        let endDateString = try container.decode(String.self, forKey: .endDate)
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        
        let dateFormatter = ISO8601DateFormatter()
        
        if let date = dateFormatter.date(from: startDateString) {
            startDate = date
        } else {
            startDate = Date()
        }
        
        if let date = dateFormatter.date(from: endDateString) {
            endDate = date
        } else {
            endDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 默认30天
        }
        
        if let date = dateFormatter.date(from: createdAtString) {
            createdAt = date
        } else {
            createdAt = Date()
        }
        
        if let date = dateFormatter.date(from: updatedAtString) {
            updatedAt = date
        } else {
            updatedAt = Date()
        }
        
        subscriptionId = try container.decode(String.self, forKey: .subscriptionId)
        isActive = try container.decode(Bool.self, forKey: .isActive)
    }
    
    /// 编码到编码器
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(type, forKey: .type)
        
        // 格式化日期
        let dateFormatter = ISO8601DateFormatter()
        try container.encode(dateFormatter.string(from: startDate), forKey: .startDate)
        try container.encode(dateFormatter.string(from: endDate), forKey: .endDate)
        try container.encode(dateFormatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(dateFormatter.string(from: updatedAt), forKey: .updatedAt)
        
        try container.encode(subscriptionId, forKey: .subscriptionId)
        try container.encode(isActive, forKey: .isActive)
    }
} 