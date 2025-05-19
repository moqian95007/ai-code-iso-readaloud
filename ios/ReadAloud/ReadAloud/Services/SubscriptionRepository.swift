import Foundation
import Combine

// 定义通知名称扩展
extension NSNotification.Name {
    static let subscriptionStatusDidChange = NSNotification.Name("subscriptionStatusDidChange")
}

/// 订阅数据仓库
class SubscriptionRepository: ObservableObject {
    /// 共享实例
    static let shared = SubscriptionRepository()
    
    /// 用户的订阅列表
    @Published private(set) var subscriptions: [Subscription] = []
    
    /// 当前活跃订阅
    @Published private(set) var activeSubscription: Subscription?
    
    /// 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 添加防抖计时器
    private var syncDebounceTimer: Timer?
    private var lastAddedSubscriptionId: String?
    private var lastSyncTime: Date = Date(timeIntervalSince1970: 0)
    
    // 添加同步锁定标志，防止短时间内重复请求
    private var isSyncLocked: Bool = false
    private var syncLockTimeout: Timer?
    
    /// 私有初始化方法
    private init() {
        loadSubscriptionsFromStorage()
    }
    
    /// 添加订阅
    /// - Parameter subscription: 订阅信息
    func addSubscription(_ subscription: Subscription) {
        // 防止短时间内重复添加相同订阅
        let now = Date()
        if let lastId = lastAddedSubscriptionId, 
           lastId.contains(subscription.type.rawValue) && // 类型相同
           now.timeIntervalSince(lastSyncTime) < 5 {  // 5秒内的重复添加
            print("忽略短时间内(\(now.timeIntervalSince(lastSyncTime))秒)重复添加的订阅: \(subscription.subscriptionId)")
            return
        }
        
        // 记录本次添加
        lastAddedSubscriptionId = subscription.subscriptionId
        lastSyncTime = now
        
        // 如果是新的活跃订阅，取消之前的活跃订阅
        if subscription.isActive {
            deactivateAllSubscriptions()
        }
        
        // 添加新订阅
        subscriptions.append(subscription)
        
        // 更新活跃订阅
        if subscription.isActive {
            activeSubscription = subscription
        }
        
        // 保存到本地
        saveSubscriptionsToStorage()
        
        // 取消之前的同步计时器
        syncDebounceTimer?.invalidate()
        
        // 延迟3秒执行同步，允许在此期间合并多个更改
        syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.syncSubscriptionsToRemote()
        }
    }
    
    /// 获取用户所有订阅
    /// - Parameter userId: 用户ID
    /// - Returns: 订阅列表
    func getSubscriptions(for userId: Int) -> [Subscription] {
        return subscriptions.filter { $0.userId == userId }
    }
    
    /// 获取用户当前活跃订阅
    /// - Parameter userId: 用户ID
    /// - Returns: 活跃订阅
    func getActiveSubscription(for userId: Int) -> Subscription? {
        // 必须同时满足三个条件：属于该用户、isActive为true、未过期
        let validSubscriptions = subscriptions.filter { 
            $0.userId == userId && $0.isActive && $0.endDate > Date() 
        }
        
        // 如果有多个有效订阅，选择结束日期最远的
        let result = validSubscriptions.max(by: { $0.endDate < $1.endDate })
        
        if result == nil {
            print("getActiveSubscription: 用户ID \(userId) 没有有效的活跃订阅")
        } else {
            print("getActiveSubscription: 用户ID \(userId) 有效的活跃订阅类型: \(result!.type.rawValue)")
        }
        
        return result
    }
    
    /// 取消所有活跃订阅
    private func deactivateAllSubscriptions() {
        for i in 0..<subscriptions.count {
            if subscriptions[i].isActive {
                subscriptions[i].isActive = false
                subscriptions[i].updatedAt = Date()
            }
        }
        
        activeSubscription = nil
    }
    
    /// 加载订阅信息
    /// - Parameter userId: 用户ID
    func loadSubscriptionsForUser(_ userId: Int) {
        // 不再从本地存储加载，直接从远程获取
        print("开始为用户ID \(userId) 加载订阅数据，直接从远程获取")
        
        // 清空当前订阅列表，确保只使用远程数据
        subscriptions.removeAll()
        activeSubscription = nil
        
        // 同步远程数据
        syncRemoteSubscriptionsToLocal(userId: userId)
    }
    
    /// 更新活跃订阅
    /// - Parameter userId: 用户ID
    private func updateActiveSubscription(for userId: Int) {
        // 过滤出用户的有效订阅，必须是活跃的且未过期
        let validSubscriptions = subscriptions.filter { 
            $0.userId == userId && $0.isActive && $0.endDate > Date() 
        }
        
        // 打印订阅状态信息用于调试
        let allUserSubscriptions = subscriptions.filter { $0.userId == userId }
        print("用户ID: \(userId) 的所有订阅数量: \(allUserSubscriptions.count)")
        
        for sub in allUserSubscriptions {
            print("订阅ID: \(sub.id), 类型: \(sub.type.rawValue), 活跃状态: \(sub.isActive), 结束日期: \(sub.endDate), 是否有效: \(sub.endDate > Date())")
        }
        
        print("符合有效条件的订阅数量: \(validSubscriptions.count)")
        
        // 重置活跃订阅
        activeSubscription = nil
        
        // 如果有多个有效订阅，选择结束日期最远的
        activeSubscription = validSubscriptions.max(by: { $0.endDate < $1.endDate })
        
        if let active = activeSubscription {
            print("更新活跃订阅 - 用户ID: \(userId), 订阅类型: \(active.type.rawValue), 结束日期: \(active.endDate), 来源: 远程数据")
        } else {
            print("用户ID: \(userId) 没有有效订阅 (基于远程数据判断)")
        }
    }
    
    /// 清除用户订阅数据
    /// - Parameter userId: 用户ID
    func clearSubscriptions(for userId: Int) {
        subscriptions.removeAll { $0.userId == userId }
        
        if activeSubscription?.userId == userId {
            activeSubscription = nil
        }
        
        saveSubscriptionsToStorage()
    }
    
    // MARK: - 数据持久化
    
    /// 保存订阅数据到本地存储
    private func saveSubscriptionsToStorage() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(subscriptions)
            UserDefaults.standard.set(data, forKey: "userSubscriptions")
        } catch {
            print("保存订阅数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 从本地存储加载订阅数据
    private func loadSubscriptionsFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: "userSubscriptions") else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let loadedSubscriptions = try decoder.decode([Subscription].self, from: data)
            subscriptions = loadedSubscriptions
        } catch {
            print("加载订阅数据失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 远程同步
    
    /// 同步订阅数据到远程
    func syncSubscriptionsToRemote() {
        // 检查同步锁，如果已锁定，跳过此次同步
        if isSyncLocked {
            print("同步已锁定，跳过重复请求")
            return
        }
        
        // 锁定同步，防止短时间内重复请求
        isSyncLocked = true
        
        // 设置5秒后自动解锁
        syncLockTimeout?.invalidate()
        syncLockTimeout = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.isSyncLocked = false
            print("同步锁定已释放，可以进行下一次同步")
        }
        
        guard let user = UserManager.shared.currentUser,
              user.id > 0,
              let token = user.token,
              !token.isEmpty else {
            print("无法同步订阅数据: 用户未登录或令牌无效")
            isSyncLocked = false // 失败时解锁
            return
        }
        
        // 过滤出当前用户的订阅
        let userSubscriptions = subscriptions.filter { $0.userId == user.id }
        
        // 没有订阅数据，跳过同步
        if userSubscriptions.isEmpty {
            print("用户没有订阅数据，跳过同步")
            isSyncLocked = false // 失败时解锁
            return
        }
        
        do {
            // 转换为JSON数据
            let encoder = JSONEncoder()
            let data = try encoder.encode(userSubscriptions)
            
            // 构建请求参数
            let parameters: [String: Any] = [
                "user_id": user.id,
                "token": token,
                "subscriptions": try JSONSerialization.jsonObject(with: data, options: [])
            ]
            
            // 使用NetworkManager发送请求
            NetworkManager.shared.performRequest(endpoint: "/save_subscription.php", method: "POST", parameters: parameters)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { result in
                        if case .failure(let error) = result {
                            print("同步订阅数据失败: \(error)")
                            // 解锁同步
                            self.isSyncLocked = false
                        }
                    },
                    receiveValue: { data in
                        if let response = try? JSONDecoder().decode(APIResponse<String>.self, from: data) {
                            print("同步订阅数据结果: \(response.status), \(response.message ?? "")")
                        }
                        // 解锁同步
                        self.isSyncLocked = false
                    }
                )
                .store(in: &cancellables)
        } catch {
            print("处理订阅数据失败: \(error.localizedDescription)")
            // 解锁同步
            isSyncLocked = false
        }
    }
    
    /// 从远程同步订阅数据到本地
    /// - Parameter userId: 用户ID
    private func syncRemoteSubscriptionsToLocal(userId: Int) {
        guard let user = UserManager.shared.currentUser,
              user.id > 0,
              let token = user.token,
              !token.isEmpty else {
            print("无法同步远程订阅数据: 用户未登录或令牌无效")
            return
        }
        
        print("开始从远程同步订阅数据 - 用户ID: \(userId)")
        
        // 构建请求参数
        let parameters: [String: Any] = [
            "user_id": user.id,
            "token": token,
            "active_only": false
        ]
        
        // 使用NetworkManager发送请求
        NetworkManager.shared.performRequest(endpoint: "/get_subscriptions.php", method: "POST", parameters: parameters)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("获取远程订阅数据失败: \(error)")
                    }
                },
                receiveValue: { [weak self] data in
                    // 打印原始数据以便调试
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("获取到的原始JSON数据: \(jsonString)")
                    }
                    
                    do {
                        // 使用自定义解码器，明确对日期的处理
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        
                        // 创建自定义结构体用于解码
                        struct SubscriptionsResponse: Decodable {
                            let status: String
                            let data: [Subscription]?
                        }
                        
                        // 直接解码为预期的响应结构
                        let response = try decoder.decode(SubscriptionsResponse.self, from: data)
                        
                        // 检查响应状态
                        if response.status == "success" {
                            if let remoteSubscriptions = response.data, !remoteSubscriptions.isEmpty {
                                print("成功解码: 获取到\(remoteSubscriptions.count)条订阅记录")
                                
                                // 检查是否有活跃的有效订阅
                                let hasActiveValidSubscription = remoteSubscriptions.contains { 
                                    $0.isActive && $0.endDate > Date() 
                                }
                                
                                if !hasActiveValidSubscription {
                                    print("警告: 服务器返回的订阅中没有活跃有效的订阅，用户将被视为非会员")
                                    
                                    // 直接使用远程数据，不做本地激活
                                    self?.subscriptions = remoteSubscriptions
                                    self?.activeSubscription = nil
                                    
                                    // 保存到本地
                                    self?.saveSubscriptionsToStorage()
                                    
                                    // 发送订阅状态更新通知
                                    NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
                                    NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                                } else {
                                    // 有有效的活跃订阅，使用远程数据
                                    self?.subscriptions = remoteSubscriptions
                                    
                                    // 更新活跃订阅
                                    self?.updateActiveSubscription(for: userId)
                                    
                                    // 保存到本地
                                    self?.saveSubscriptionsToStorage()
                                    
                                    print("成功同步\(remoteSubscriptions.count)个订阅从远程到本地")
                                    
                                    // 通知订阅状态更新
                                    NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
                                }
                            } else {
                                print("远程订阅数据为空")
                                
                                // 如果远程没有订阅数据，清除该用户的本地订阅
                                if let self = self {
                                    print("清除用户ID \(userId) 的本地订阅数据...")
                                    
                                    // 保存当前的订阅状态以检测是否需要发送通知
                                    let hadActiveSubscription = self.getActiveSubscription(for: userId) != nil
                                    
                                    // 清除该用户的所有订阅
                                    self.clearSubscriptions(for: userId)
                                    
                                    print("用户的本地订阅数据已清除")
                                    
                                    // 如果之前有活跃订阅，发送状态更新通知
                                    if hadActiveSubscription {
                                        NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
                                        NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                                    }
                                }
                            }
                        } else {
                            print("远程数据获取失败: 状态码不为success")
                        }
                    } catch {
                        print("订阅数据解码错误: \(error)")
                        print("详细错误: \(String(describing: error))")
                        
                        // 尝试降级处理 - 手动解析JSON
                        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let status = json["status"] as? String,
                           status == "success",
                           let dataArray = json["data"] as? [[String: Any]] {
                            
                            print("降级处理: 手动解析JSON数据")
                            var parsedSubscriptions: [Subscription] = []
                            
                            for item in dataArray {
                                // 提取各字段，并使用安全转换
                                if let id = item["id"] as? String,
                                   let userIdValue = item["userId"] as? Int,
                                   let typeString = item["type"] as? String,
                                   let startDateString = item["startDate"] as? String,
                                   let endDateString = item["endDate"] as? String,
                                   let subId = item["subscriptionId"] as? String,
                                   let isActiveValue = item["isActive"] as? Bool,
                                   let createdAtString = item["createdAt"] as? String,
                                   let updatedAtString = item["updatedAt"] as? String {
                                    
                                    // 手动转换日期
                                    let dateFormatter = DateFormatter()
                                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                    
                                    guard let startDate = dateFormatter.date(from: startDateString),
                                          let endDate = dateFormatter.date(from: endDateString),
                                          let createdAt = dateFormatter.date(from: createdAtString),
                                          let updatedAt = dateFormatter.date(from: updatedAtString),
                                          let uuid = UUID(uuidString: id) else {
                                        print("日期或UUID转换失败，跳过该条目")
                                        continue
                                    }
                                    
                                    // 创建订阅对象
                                    var subscription = Subscription(
                                        userId: userIdValue,
                                        type: SubscriptionType(rawValue: typeString) ?? .monthly,
                                        startDate: startDate,
                                        endDate: endDate, 
                                        subscriptionId: subId
                                    )
                                    // 手动设置其他属性
                                    subscription.id = uuid
                                    subscription.isActive = isActiveValue
                                    subscription.createdAt = createdAt
                                    subscription.updatedAt = updatedAt
                                    
                                    parsedSubscriptions.append(subscription)
                                    print("手动解析订阅: ID=\(id), 类型=\(typeString)")
                                }
                            }
                            
                            if !parsedSubscriptions.isEmpty {
                                print("手动解析成功: 获取到\(parsedSubscriptions.count)条订阅记录")
                                
                                // 直接使用解析出的远程数据
                                self?.subscriptions = parsedSubscriptions
                                
                                // 更新活跃订阅
                                self?.updateActiveSubscription(for: userId)
                                
                                // 保存到本地
                                self?.saveSubscriptionsToStorage()
                                
                                // 通知订阅状态更新
                                NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
                            }
                        } else {
                            print("降级处理失败: 无法手动解析JSON数据")
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 合并本地和远程订阅数据
    /// - Parameter remoteSubscriptions: 远程订阅数据
    private func mergeSubscriptions(_ remoteSubscriptions: [Subscription]) {
        // 不再进行合并，直接使用远程数据
        subscriptions = remoteSubscriptions
        
        // 确保在处理后更新活跃订阅
        if let user = UserManager.shared.currentUser {
            updateActiveSubscription(for: user.id)
        }
        
        // 保存到本地
        saveSubscriptionsToStorage()
    }
} 