import Foundation

/// 产品ID管理器
/// 用于统一管理应用内的所有产品ID，确保一致性
struct ProductIdManager {
    // 单例模式
    static let shared = ProductIdManager()
    
    // MARK: - 消耗型产品(导入次数)
    // App内完整产品ID
    // 导入1次
    let importSingle = "top.ai-toolkit.readaloud.import.single"
    
    // 导入3次
    let importThree = "top.ai-toolkit.readaloud.import.three"
    
    // 导入5次
    let importFive = "top.ai-toolkit.readaloud.import.five"
    
    // 导入10次
    let importTen = "top.ai-toolkit.readaloud.import.ten"
    
    // App Store Connect简化产品ID
    let appStoreImportSingle = "import.single"
    let appStoreImportThree = "import.three"
    let appStoreImportFive = "import.five"
    let appStoreImportTen = "import.ten"
    
    // MARK: - 订阅产品
    // 订阅组ID
    let subscriptionGroupId = "21690295"
    
    // 订阅组名称
    let subscriptionGroupName = "top.ai-toolkit.readaloud.subscription"
    
    // App内完整产品ID
    // 月度订阅
    let subscriptionMonthly = "top.ai-toolkit.readaloud.subscription.monthly"
    
    // 季度订阅
    let subscriptionQuarterly = "top.ai-toolkit.readaloud.subscription.quarterly"
    
    // 半年订阅
    let subscriptionHalfYearly = "top.ai-toolkit.readaloud.subscription.halfYearly"
    
    // 年度订阅
    let subscriptionYearly = "top.ai-toolkit.readaloud.subscription.yearly"
    
    // App Store Connect内简化的产品ID
    let appStoreMonthly = "monthly"
    let appStoreQuarterly = "quarterly"
    let appStoreHalfYearly = "halfYearly"
    let appStoreYearly = "Yearly"
    
    // MARK: - 获取所有产品ID集合
    
    /// 获取所有消耗型产品ID（完整ID）
    var allConsumableProductIds: [String] {
        return [importSingle, importThree, importFive, importTen]
    }
    
    /// 获取App Store Connect中配置的简化消耗型产品ID
    var allSimplifiedConsumableIds: [String] {
        return [appStoreImportSingle, appStoreImportThree, appStoreImportFive, appStoreImportTen]
    }
    
    /// 获取所有可能的消耗型产品ID（同时包含完整ID和简化ID）
    var allPossibleConsumableIds: [String] {
        return allConsumableProductIds + allSimplifiedConsumableIds
    }
    
    /// 获取所有订阅产品ID（完整ID）
    var allSubscriptionProductIds: [String] {
        return [subscriptionMonthly, subscriptionQuarterly, subscriptionHalfYearly, subscriptionYearly]
    }
    
    /// 获取App Store Connect中配置的简化订阅产品ID
    var allSimplifiedSubscriptionIds: [String] {
        return [appStoreMonthly, appStoreQuarterly, appStoreHalfYearly, appStoreYearly]
    }
    
    /// 获取所有可能的订阅产品ID（同时包含完整ID和简化ID）
    var allPossibleSubscriptionIds: [String] {
        return allSubscriptionProductIds + allSimplifiedSubscriptionIds
    }
    
    /// 获取App Store Connect中配置的所有简化产品ID
    var allSimplifiedIds: [String] {
        return allSimplifiedConsumableIds + allSimplifiedSubscriptionIds
    }
    
    /// 获取所有产品ID
    var allProductIds: [String] {
        return allPossibleConsumableIds + allPossibleSubscriptionIds
    }
    
    // MARK: - 产品ID映射
    
    /// 导入次数映射表
    let importCountsMap: [String: Int] = [
        // 完整ID
        "top.ai-toolkit.readaloud.import.single": 1,
        "top.ai-toolkit.readaloud.import.three": 3,
        "top.ai-toolkit.readaloud.import.five": 5,
        "top.ai-toolkit.readaloud.import.ten": 10,
        // 简化ID
        "import.single": 1,
        "import.three": 3,
        "import.five": 5,
        "import.ten": 10
    ]
    
    /// 订阅时长映射表(以月为单位)
    let subscriptionDurationMap: [String: Int] = [
        // 完整ID
        "top.ai-toolkit.readaloud.subscription.monthly": 1,
        "top.ai-toolkit.readaloud.subscription.quarterly": 3,
        "top.ai-toolkit.readaloud.subscription.halfYearly": 6,
        "top.ai-toolkit.readaloud.subscription.yearly": 12,
        // 简化ID
        "monthly": 1,
        "quarterly": 3,
        "halfYearly": 6,
        "Yearly": 12
    ]
    
    /// 将简化产品ID转换为完整产品ID
    /// - Parameter simplifiedId: 简化的产品ID
    /// - Returns: 完整的产品ID
    func getFullProductId(from simplifiedId: String) -> String? {
        switch simplifiedId {
        // 订阅产品
        case appStoreMonthly:
            return subscriptionMonthly
        case appStoreQuarterly:
            return subscriptionQuarterly
        case appStoreHalfYearly:
            return subscriptionHalfYearly
        case appStoreYearly:
            return subscriptionYearly
            
        // 消耗型产品
        case appStoreImportSingle:
            return importSingle
        case appStoreImportThree:
            return importThree
        case appStoreImportFive:
            return importFive
        case appStoreImportTen:
            return importTen
            
        default:
            return nil
        }
    }
    
    /// 验证产品ID是否有效
    /// - Parameter productId: 产品ID
    /// - Returns: 是否有效
    func isValidProductId(_ productId: String) -> Bool {
        return allProductIds.contains(productId)
    }
    
    /// 获取产品类型
    /// - Parameter productId: 产品ID
    /// - Returns: 产品类型
    func getProductType(for productId: String) -> ProductType {
        if allPossibleConsumableIds.contains(productId) {
            return .consumable
        } else if allPossibleSubscriptionIds.contains(productId) {
            return .subscription
        } else {
            return .unknown
        }
    }
    
    /// 获取导入次数
    /// - Parameter productId: 产品ID
    /// - Returns: 导入次数，如果不是导入产品则返回0
    func getImportCount(for productId: String) -> Int {
        return importCountsMap[productId] ?? 0
    }
}

/// 产品类型枚举
enum ProductType {
    case consumable    // 消耗型产品
    case subscription  // 订阅产品
    case unknown       // 未知类型
} 