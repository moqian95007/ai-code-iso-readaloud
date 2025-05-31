import Foundation
import Combine
import SwiftUI

/// 同步服务，用于处理用户设置和阅读进度的同步
class SyncService: ObservableObject {
    // 单例模式
    static let shared = SyncService()
    
    // 发布状态
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    
    // 用户管理器
    private let userManager = UserManager.shared
    
    // 网络管理器
    private let networkManager = NetworkManager.shared
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 私有初始化方法
    private init() {
        // 监听设置变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: NSNotification.Name("UserSettingsUpdated"),
            object: nil
        )
        
        // 监听阅读进度变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReadingProgressChanged),
            name: NSNotification.Name("ReadingProgressUpdated"),
            object: nil
        )
        
        // 定时同步
        setupPeriodicSync()
    }
    
    // 设置定时同步
    private func setupPeriodicSync() {
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.syncIfNeeded()
        }
    }
    
    // 根据需要进行同步
    private func syncIfNeeded() {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser, user.hasActiveSubscription else {
            return
        }
        
        // 检查上次同步时间，如果在15分钟内已同步，则跳过
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < 15 * 60 {
            return
        }
        
        // 执行同步
        syncUserSettings()
        syncReadingProgress()
    }
    
    // 处理设置变更
    @objc private func handleSettingsChanged() {
        // 用户必须登录且有订阅
        guard userManager.isLoggedIn, let user = userManager.currentUser, user.hasActiveSubscription else {
            return
        }
        
        // 防抖动，延迟5秒后执行同步
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.syncUserSettings()
        }
    }
    
    // 处理阅读进度变更
    @objc private func handleReadingProgressChanged() {
        // 用户必须登录且有订阅
        guard userManager.isLoggedIn, let user = userManager.currentUser, user.hasActiveSubscription else {
            return
        }
        
        // 不再在每次阅读进度变化时同步到服务器
        // 仅记录变化，等到应用退出或用户登出时再统一同步
        print("检测到阅读进度变化，已记录但不立即同步")
    }
    
    // MARK: - 同步用户设置
    
    /// 同步用户设置
    /// - Parameter completion: 完成回调，返回同步是否成功
    func syncUserSettings(completion: ((Bool) -> Void)? = nil) {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，跳过设置同步")
            completion?(false)
            return
        }
        
        // 检查用户是否有订阅
        guard user.hasActiveSubscription else {
            print("用户无活跃订阅，跳过设置同步")
            completion?(false)
            return
        }
        
        print("开始同步用户设置...")
        isSyncing = true
        
        // 从UserDefaults读取设置
        let settings = UserSettings()
        
        do {
            // 将设置编码为JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let settingsData = try encoder.encode(settings)
            let settingsJson = String(data: settingsData, encoding: .utf8) ?? ""
            
            // 发送到服务器
            networkManager.saveUserData(userId: user.id, token: user.token ?? "", dataKey: "user_settings", dataValue: settingsJson)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] result in
                        if case .failure(let error) = result {
                            print("同步设置失败: \(error.localizedDescription)")
                            self?.syncError = "同步设置失败: \(error.localizedDescription)"
                            completion?(false)
                        }
                        self?.isSyncing = false
                    },
                    receiveValue: { [weak self] message in
                        print("同步设置成功: \(message)")
                        self?.lastSyncTime = Date()
                        self?.syncError = nil
                        completion?(true)
                    }
                )
                .store(in: &cancellables)
        } catch {
            print("编码设置数据失败: \(error.localizedDescription)")
            isSyncing = false
            syncError = "编码设置数据失败: \(error.localizedDescription)"
            completion?(false)
        }
    }
    
    /// 从服务器获取设置
    func fetchUserSettings() {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，跳过获取设置")
            return
        }
        
        // 检查用户是否有订阅
        guard user.hasActiveSubscription else {
            print("用户无活跃订阅，跳过获取设置")
            return
        }
        
        print("从服务器获取用户设置...")
        isSyncing = true
        
        networkManager.getUserData(userId: user.id, token: user.token ?? "", dataKey: "user_settings")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] result in
                    if case .failure(let error) = result {
                        print("获取设置失败: \(error.localizedDescription)")
                        self?.syncError = "获取设置失败: \(error.localizedDescription)"
                    }
                    self?.isSyncing = false
                },
                receiveValue: { [weak self] data in
                    if let settingsString = data["user_settings"], let settingsData = settingsString.data(using: .utf8) {
                        do {
                            let decoder = JSONDecoder()
                            let settings = try decoder.decode(UserSettings.self, from: settingsData)
                            
                            // 应用设置
                            settings.applyToUserDefaults()
                            
                            print("成功应用从服务器获取的设置")
                            self?.lastSyncTime = Date()
                            self?.syncError = nil
                            
                            // 发送通知，通知设置已更新
                            NotificationCenter.default.post(name: NSNotification.Name("UserSettingsUpdated"), object: nil)
                        } catch {
                            print("解码设置数据失败: \(error.localizedDescription)")
                            self?.syncError = "解码设置数据失败: \(error.localizedDescription)"
                        }
                    } else {
                        print("设置数据为空或无效")
                        self?.syncError = "设置数据为空或无效"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 同步阅读进度
    
    /// 同步阅读进度
    /// - Parameter completion: 完成回调，返回同步是否成功
    func syncReadingProgress(completion: ((Bool) -> Void)? = nil) {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，跳过阅读进度同步")
            completion?(false)
            return
        }
        
        // 检查用户是否有订阅
        guard user.hasActiveSubscription else {
            print("用户无活跃订阅，跳过阅读进度同步")
            completion?(false)
            return
        }
        
        print("开始同步阅读进度...")
        isSyncing = true
        
        // 从UserDefaults读取阅读进度
        let progresses = ReadingProgress.loadFromUserDefaults()
        
        // 创建阅读进度对象
        let readingProgress = ReadingProgress(
            userId: user.id,
            lastSyncTime: Date(),
            contentProgresses: progresses
        )
        
        do {
            // 将阅读进度编码为JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let progressData = try encoder.encode(readingProgress)
            let progressJson = String(data: progressData, encoding: .utf8) ?? ""
            
            // 发送到服务器
            networkManager.saveUserData(userId: user.id, token: user.token ?? "", dataKey: "reading_progress", dataValue: progressJson)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] result in
                        if case .failure(let error) = result {
                            print("同步阅读进度失败: \(error.localizedDescription)")
                            self?.syncError = "同步阅读进度失败: \(error.localizedDescription)"
                            completion?(false)
                        }
                        self?.isSyncing = false
                    },
                    receiveValue: { [weak self] message in
                        print("同步阅读进度成功: \(message)")
                        self?.lastSyncTime = Date()
                        self?.syncError = nil
                        completion?(true)
                    }
                )
                .store(in: &cancellables)
        } catch {
            print("编码阅读进度数据失败: \(error.localizedDescription)")
            isSyncing = false
            syncError = "编码阅读进度数据失败: \(error.localizedDescription)"
            completion?(false)
        }
    }
    
    /// 从服务器获取阅读进度
    func fetchReadingProgress() {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，跳过获取阅读进度")
            return
        }
        
        // 检查用户是否有订阅
        guard user.hasActiveSubscription else {
            print("用户无活跃订阅，跳过获取阅读进度")
            return
        }
        
        print("从服务器获取阅读进度...")
        isSyncing = true
        
        networkManager.getUserData(userId: user.id, token: user.token ?? "", dataKey: "reading_progress")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] result in
                    if case .failure(let error) = result {
                        print("获取阅读进度失败: \(error.localizedDescription)")
                        self?.syncError = "获取阅读进度失败: \(error.localizedDescription)"
                    }
                    self?.isSyncing = false
                },
                receiveValue: { [weak self] data in
                    if let progressString = data["reading_progress"], let progressData = progressString.data(using: .utf8) {
                        do {
                            let decoder = JSONDecoder()
                            let readingProgress = try decoder.decode(ReadingProgress.self, from: progressData)
                            
                            // 应用阅读进度
                            ReadingProgress.applyProgressesToUserDefaults(progresses: readingProgress.contentProgresses)
                            
                            print("成功应用从服务器获取的阅读进度")
                            self?.lastSyncTime = Date()
                            self?.syncError = nil
                            
                            // 发送通知，通知阅读进度已更新
                            NotificationCenter.default.post(name: NSNotification.Name("ReadingProgressUpdated"), object: nil)
                        } catch {
                            print("解码阅读进度数据失败: \(error.localizedDescription)")
                            self?.syncError = "解码阅读进度数据失败: \(error.localizedDescription)"
                        }
                    } else {
                        print("阅读进度数据为空或无效")
                        self?.syncError = "阅读进度数据为空或无效"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 同步所有数据
    /// - Parameter completion: 完成回调，返回同步是否成功
    func syncAll(completion: ((Bool) -> Void)? = nil) {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，跳过同步所有数据")
            completion?(false)
            return
        }
        
        // 检查用户是否有订阅
        guard user.hasActiveSubscription else {
            print("用户无活跃订阅，跳过同步所有数据")
            completion?(false)
            return
        }
        
        // 创建一个组来跟踪所有同步任务
        let syncGroup = DispatchGroup()
        var syncSuccess = true
        
        // 同步用户设置
        syncGroup.enter()
        syncUserSettings { success in
            if !success {
                syncSuccess = false
            }
            syncGroup.leave()
        }
        
        // 同步阅读进度
        syncGroup.enter()
        syncReadingProgress { success in
            if !success {
                syncSuccess = false
            }
            syncGroup.leave()
        }
        
        // 当所有同步完成后回调
        syncGroup.notify(queue: .main) {
            print("所有同步任务已完成，结果: \(syncSuccess ? "成功" : "有部分失败")")
            completion?(syncSuccess)
        }
    }
    
    /// 从服务器获取所有数据
    func fetchAll() {
        // 用户必须登录
        guard userManager.isLoggedIn, let user = userManager.currentUser else {
            print("用户未登录，跳过获取所有数据")
            return
        }
        
        // 检查用户是否有订阅
        guard user.hasActiveSubscription else {
            print("用户无活跃订阅，跳过获取所有数据")
            return
        }
        
        fetchUserSettings()
        fetchReadingProgress()
    }
    
    // 清理资源
    deinit {
        // 移除通知观察者
        NotificationCenter.default.removeObserver(self)
    }
} 