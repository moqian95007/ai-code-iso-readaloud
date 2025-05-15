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
    
    /// 私有初始化方法
    private init() {
        loadSubscriptionsFromStorage()
    }
    
    /// 添加订阅
    /// - Parameter subscription: 订阅信息
    func addSubscription(_ subscription: Subscription) {
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
        
        // 同步到远程
        syncSubscriptionsToRemote()
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
        return subscriptions.first { $0.userId == userId && $0.isActive && $0.isValid }
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
        // 从本地存储加载
        loadSubscriptionsFromStorage()
        
        // 更新活跃订阅
        updateActiveSubscription(for: userId)
        
        // 同步远程数据
        syncRemoteSubscriptionsToLocal(userId: userId)
    }
    
    /// 更新活跃订阅
    /// - Parameter userId: 用户ID
    private func updateActiveSubscription(for userId: Int) {
        // 过滤出用户的有效订阅
        let validSubscriptions = subscriptions.filter { 
            $0.userId == userId && $0.isActive && $0.endDate > Date() 
        }
        
        // 如果有多个有效订阅，选择结束日期最远的
        activeSubscription = validSubscriptions.max(by: { $0.endDate < $1.endDate })
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
    private func syncSubscriptionsToRemote() {
        guard let user = UserManager.shared.currentUser,
              user.id > 0,
              let token = user.token,
              !token.isEmpty else {
            print("无法同步订阅数据: 用户未登录或令牌无效")
            return
        }
        
        // 过滤出当前用户的订阅
        let userSubscriptions = subscriptions.filter { $0.userId == user.id }
        
        // 没有订阅数据，跳过同步
        if userSubscriptions.isEmpty {
            print("用户没有订阅数据，跳过同步")
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
                        }
                    },
                    receiveValue: { data in
                        if let response = try? JSONDecoder().decode(APIResponse<String>.self, from: data) {
                            print("同步订阅数据结果: \(response.status), \(response.message ?? "")")
                        }
                    }
                )
                .store(in: &cancellables)
        } catch {
            print("处理订阅数据失败: \(error.localizedDescription)")
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
                                
                                // 合并远程和本地订阅数据
                                self?.mergeSubscriptions(remoteSubscriptions)
                                
                                // 更新活跃订阅
                                self?.updateActiveSubscription(for: userId)
                                
                                print("成功同步\(remoteSubscriptions.count)个订阅从远程到本地")
                                
                                // 通知订阅状态更新
                                NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
                            } else {
                                print("远程订阅数据为空")
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
                                
                                // 合并远程和本地订阅数据
                                self?.mergeSubscriptions(parsedSubscriptions)
                                
                                // 更新活跃订阅
                                self?.updateActiveSubscription(for: userId)
                                
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
        var mergedSubscriptions = [UUID: Subscription]()
        
        // 先保存所有本地订阅
        for subscription in subscriptions {
            mergedSubscriptions[subscription.id] = subscription
        }
        
        // 合并或添加远程订阅
        for remote in remoteSubscriptions {
            // 如果本地有相同ID的订阅，使用更新时间较新的版本
            if let local = mergedSubscriptions[remote.id] {
                if remote.updatedAt > local.updatedAt {
                    mergedSubscriptions[remote.id] = remote
                }
            } else {
                // 本地没有，直接添加
                mergedSubscriptions[remote.id] = remote
            }
        }
        
        // 更新订阅列表
        subscriptions = Array(mergedSubscriptions.values)
        
        // 保存到本地
        saveSubscriptionsToStorage()
    }
} 