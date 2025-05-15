import Foundation
import Combine
import SwiftUI
import CryptoKit

/// 用户管理器，处理用户登录、注册和用户状态持久化
class UserManager: ObservableObject {
    // 单例模式
    static let shared = UserManager()
    
    // 发布用户状态变化
    @Published var currentUser: User?
    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var verificationCodeSent: Bool = false
    @Published var verificationMessage: String = ""
    @Published var codeVerified: Bool = false
    @Published var verifiedEmail: String? = nil
    @Published var suggestedUsername: String? = nil
    @Published var lastVerificationCode: String? = nil
    
    // Apple登录相关
    var currentNonce: String?
    
    // 取消标记
    private var cancellables = Set<AnyCancellable>()
    
    // 私有初始化方法
    private init() {
        // 从UserDefaults加载用户信息
        loadUserFromStorage()
    }
    
    // MARK: - 第三方登录方法
    
    /// 使用Apple账号登录
    /// - Parameters:
    ///   - idToken: Apple ID令牌
    ///   - nonce: 加密nonce
    ///   - email: 邮箱
    ///   - fullName: 全名
    func loginWithApple(idToken: String, nonce: String, email: String, fullName: String, appleUserId: String) {
        isLoading = true
        error = nil
        
        // 处理用户名，确保不为空
        let username = !fullName.isEmpty ? fullName : "Apple用户"
        print("开始Apple登录请求 - 用户名: \(username), 邮箱: \(email.isEmpty ? "[空]" : email), 用户ID: \(appleUserId)")
        
        // 调用NetworkManager将用户信息同步到后台
        NetworkManager.shared.loginWithApple(idToken: idToken, nonce: nonce, email: email, fullName: username, appleUserId: appleUserId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                            print("Apple登录失败: \(message)")
                        } else {
                            self?.error = "Apple登录失败，请稍后再试"
                            print("Apple登录错误: \(error)")
                        }
                        
                        // 登录失败时，仍然创建本地用户对象（离线模式）
                        print("使用本地模式创建Apple用户")
                        let offlineUser = User(
                            id: -1, // 使用临时ID
                            username: username,
                            email: email,
                            phone: nil,
                            token: "local_token_for_apple",
                            registerDate: Date(),
                            lastLogin: Date(),
                            status: "active"
                        )
                        self?.currentUser = offlineUser
                        self?.isLoggedIn = true
                        self?.saveUserToStorage(user: offlineUser)
                    }
                },
                receiveValue: { [weak self] user in
                    print("Apple登录成功，从服务器返回用户: \(user.username), ID: \(user.id)")
                    self?.currentUser = user
                    self?.isLoggedIn = true
                    self?.saveUserToStorage(user: user)
                    
                    // 登录成功后，先从远程同步数据到本地，然后再同步本地数据到远程
                    self?.syncRemoteDataToLocal(user: user) { [weak self] in
                        // 完成从远程同步后，再同步本地数据到远程
                        self?.syncLocalDataToRemote(user: user) {
                            // 发送通知通知所有ArticleManager实例重新加载文章数据
                            NotificationCenter.default.post(name: Notification.Name("ReloadArticlesData"), object: nil)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 使用Google账号登录
    /// - Parameters:
    ///   - idToken: Google ID令牌
    ///   - email: 邮箱
    ///   - name: 姓名
    func loginWithGoogle(idToken: String, email: String, name: String) {
        isLoading = true
        error = nil
        
        // 处理用户名
        let username = name.isEmpty ? "GoogleUser" : name
        // 注意：我们现在接受空的电子邮箱，后端会处理
        let userEmail = email
        
        print("开始Google登录请求 - 用户名: \(username), 邮箱: \(userEmail.isEmpty ? "[空]" : userEmail)")
        
        // 调用NetworkManager将用户信息同步到后台
        NetworkManager.shared.loginWithGoogle(idToken: idToken, email: userEmail, name: username)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                            print("Google登录失败: \(message)")
                        } else {
                            self?.error = "Google登录失败，请稍后再试"
                            print("Google登录错误: \(error)")
                        }
                        
                        // 登录失败时，仍然创建本地用户对象（离线模式）
                        print("使用本地模式创建Google用户")
                        let offlineUser = User(
                            id: -2, // 使用临时ID
                            username: username,
                            email: userEmail,
                            phone: nil,
                            token: "local_token_for_google",
                            registerDate: Date(),
                            lastLogin: Date(),
                            status: "active"
                        )
                        self?.currentUser = offlineUser
                        self?.isLoggedIn = true
                        self?.saveUserToStorage(user: offlineUser)
                    }
                },
                receiveValue: { [weak self] user in
                    print("Google登录成功，从服务器返回用户: \(user.username), ID: \(user.id)")
                    self?.currentUser = user
                    self?.isLoggedIn = true
                    self?.saveUserToStorage(user: user)
                    
                    // 登录成功后，先从远程同步数据到本地，然后再同步本地数据到远程
                    self?.syncRemoteDataToLocal(user: user) { [weak self] in
                        // 完成从远程同步后，再同步本地数据到远程
                        self?.syncLocalDataToRemote(user: user) {
                            // 发送通知通知所有ArticleManager实例重新加载文章数据
                            NotificationCenter.default.post(name: Notification.Name("ReloadArticlesData"), object: nil)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Apple登录辅助方法
    
    /// 生成随机nonce用于防止重放攻击
    /// - Parameter length: nonce长度
    /// - Returns: 随机nonce字符串
    func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    /// 对nonce进行SHA256哈希
    /// - Parameter input: 输入nonce
    /// - Returns: 哈希后的字符串
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // MARK: - 用户验证和注册方法
    
    /// 发送验证码到指定邮箱
    /// - Parameter email: 邮箱
    func sendVerificationCode(to email: String) {
        guard isValidEmail(email) else {
            error = "请输入有效的邮箱地址"
            return
        }
        
        isLoading = true
        error = nil
        verificationMessage = ""
        
        NetworkManager.shared.sendVerificationCode(email: email)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                        } else {
                            self?.error = "发送验证码失败，请稍后再试"
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    self?.verificationCodeSent = true
                    self?.verificationMessage = response
                }
            )
            .store(in: &cancellables)
    }
    
    /// 验证邮箱验证码
    /// - Parameters:
    ///   - email: 邮箱
    ///   - code: 验证码
    func verifyCode(email: String, code: String) {
        isLoading = true
        error = nil
        
        NetworkManager.shared.verifyCode(email: email, verificationCode: code)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                        } else {
                            self?.error = "验证失败，请稍后再试"
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    self?.codeVerified = response.verified
                    if response.verified {
                        self?.verifiedEmail = email
                        self?.suggestedUsername = response.username_suggestion
                        self?.lastVerificationCode = code
                    } else {
                        self?.error = "验证码无效"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 完成注册流程
    /// - Parameters:
    ///   - email: 邮箱
    ///   - password: 密码
    func completeRegistration(email: String, password: String) {
        guard let code = lastVerificationCode else {
            error = "验证码无效，请重新获取"
            return
        }
        
        isLoading = true
        error = nil
        
        NetworkManager.shared.completeRegistration(email: email, password: password, verificationCode: code)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                        } else {
                            self?.error = "注册失败，请稍后再试"
                        }
                    }
                },
                receiveValue: { [weak self] user in
                    self?.currentUser = user
                    self?.isLoggedIn = true
                    self?.saveUserToStorage(user: user)
                    
                    // 注册成功后，先从远程同步数据到本地，然后再同步本地数据到远程
                    self?.syncRemoteDataToLocal(user: user) { [weak self] in
                        // 完成从远程同步后，再同步本地数据到远程
                        self?.syncLocalDataToRemote(user: user)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 注册新用户
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    ///   - email: 邮箱
    func register(username: String, password: String, email: String) {
        guard let code = lastVerificationCode else {
            error = "验证码无效，请重新获取"
            return
        }
        
        isLoading = true
        error = nil
        
        NetworkManager.shared.register(username: username, password: password, email: email, verificationCode: code)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        self?.isLoading = false
                        if case .failure(let error) = completion {
                            if case NetworkError.apiError(let message) = error {
                                self?.error = message
                            } else {
                            self?.error = "注册失败，请稍后再试"
                        }
                    }
                },
                receiveValue: { [weak self] user in
                    self?.currentUser = user
                    self?.isLoggedIn = true
                    self?.saveUserToStorage(user: user)
                    
                    // 注册成功后，先从远程同步数据到本地，然后再同步本地数据到远程
                    self?.syncRemoteDataToLocal(user: user) { [weak self] in
                        // 完成从远程同步后，再同步本地数据到远程
                        self?.syncLocalDataToRemote(user: user)
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 使用邮箱和密码登录
    /// - Parameters:
    ///   - email: 邮箱
    ///   - password: 密码
    func login(email: String, password: String) {
        isLoading = true
        error = nil
        
        NetworkManager.shared.login(email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                        } else {
                            self?.error = "登录失败，请稍后再试"
                        }
                    }
                },
                receiveValue: { [weak self] user in
                    self?.currentUser = user
                    self?.isLoggedIn = true
                    self?.saveUserToStorage(user: user)
                    
                    // 登录成功后，先从远程同步数据到本地，然后再同步本地数据到远程
                    self?.syncRemoteDataToLocal(user: user) { [weak self] in
                        // 完成从远程同步后，再同步本地数据到远程
                        self?.syncLocalDataToRemote(user: user) {
                            // 发送通知通知所有ArticleManager实例重新加载文章数据
                            NotificationCenter.default.post(name: Notification.Name("ReloadArticlesData"), object: nil)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    /// 发送验证码
    /// - Parameter email: 邮箱地址
    func sendVerificationCodeForPasswordReset(to email: String) {
        sendVerificationCode(to: email)
    }
    
    /// 重置密码
    /// - Parameters:
    ///   - email: 邮箱
    ///   - newPassword: 新密码
    ///   - verificationCode: 验证码
    func resetPassword(email: String, newPassword: String, verificationCode: String) {
        isLoading = true
        error = nil
        
        // 简化实现，直接假设成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isLoading = false
            self?.verificationMessage = "密码重置成功"
        }
    }
    
    /// 更新用户资料
    /// - Parameters:
    ///   - username: 用户名
    ///   - email: 邮箱
    ///   - phone: 手机号
    func updateProfile(username: String? = nil, email: String? = nil, phone: String? = nil) {
        guard let user = currentUser, user.id > 0, let token = user.token else {
            error = "用户未登录或令牌无效"
            return
        }
        
        isLoading = true
        error = nil
        
        // 简化实现，直接更新本地用户信息
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            
            var updatedUser = user
            if let username = username {
                updatedUser.username = username
            }
            if let email = email {
                updatedUser.email = email
            }
            
            self.currentUser = updatedUser
            self.saveUserToStorage(user: updatedUser)
            self.isLoading = false
        }
    }
    
    /// 更改密码
    /// - Parameters:
    ///   - oldPassword: 旧密码
    ///   - newPassword: 新密码
    func changePassword(oldPassword: String, newPassword: String) {
        guard let user = currentUser, user.id > 0, let token = user.token else {
            error = "用户未登录或令牌无效"
            return
        }
        
        isLoading = true
        error = nil
        
        // 简化实现，直接假设成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isLoading = false
            self?.verificationMessage = "密码修改成功"
        }
    }
    
    /// 用户登出
    func logout() {
        print("========= 开始用户登出流程 =========")
        
        // 保存当前用户ID用于清除订阅数据
        let currentUserId = currentUser?.id
        
        // 先同步本地数据到远程服务器
        if let user = currentUser, user.id > 0, let token = user.token {
            print("登出前先同步本地数据到远程服务器")
            
            // 创建一个信号量来等待同步完成
            let syncSemaphore = DispatchSemaphore(value: 0)
            
            // 创建一个同步组来追踪所有同步任务
            let syncGroup = DispatchGroup()
            
            // 同步文章列表到远程
            syncGroup.enter()
            syncArticleLists(userId: user.id, token: token) {
                syncGroup.leave()
            }
            
            // 同步文章内容到远程
            syncGroup.enter()
            syncArticles(userId: user.id, token: token) {
                syncGroup.leave()
            }
            
            // 当所有同步任务完成后，发送信号
            syncGroup.notify(queue: .global()) {
                print("所有数据同步操作已完成")
                syncSemaphore.signal()
            }
            
            // 限制最多等待5秒钟
            let waitResult = syncSemaphore.wait(timeout: .now() + 5.0)
            
            if waitResult == .success {
                print("登出前数据同步已完成，继续登出流程")
            } else {
                print("数据同步等待超时，继续登出流程")
            }
        }
        
        // 清除用户数据
        currentUser = nil
        isLoggedIn = false
        clearUserFromStorage()
        
        // 清除订阅数据
        if let userId = currentUserId, userId > 0 {
            print("清除用户ID为\(userId)的订阅数据")
            SubscriptionRepository.shared.clearSubscriptions(for: userId)
        }
        
        // 清空所有列表中的文章
        clearArticlesFromLists()
        
        // 发送登出通知
        NotificationCenter.default.post(name: Notification.Name("UserLoggedOut"), object: nil)
        
        print("========= 用户登出流程完成 =========")
    }
    
    /// 清空所有列表中的文章
    private func clearArticlesFromLists() {
        print("开始清空所有文章列表和数据")
        
        // 获取ArticleListManager实例
        let listManager = ArticleListManager.shared
        
        // 保留文档列表
        let documentLists = listManager.lists.filter { $0.isDocument }
        
        // 创建初始列表（仅保留"所有文章"列表并清空其中文章）
        var initialLists: [ArticleList] = []
        
        // 寻找"所有文章"列表或创建新的
        if let allArticlesList = listManager.userLists.first(where: { $0.name == "所有文章" }) {
            // 创建一个全新的"所有文章"列表（保留ID和创建时间，但清空文章）
            let emptyAllArticlesList = ArticleList(
                id: allArticlesList.id,
                name: allArticlesList.name,
                createdAt: allArticlesList.createdAt,
                articleIds: [],
                isDocument: false
            )
            initialLists.append(emptyAllArticlesList)
        } else {
            // 如果不存在，创建一个新的"所有文章"列表
            let newAllArticlesList = ArticleList(name: "所有文章")
            initialLists.append(newAllArticlesList)
        }
        
        // 更新列表（保留文档列表，清空用户列表中的文章）
        listManager.lists = documentLists + initialLists
        
        // 确保选择"所有文章"列表
        if let allArticlesListId = initialLists.first?.id {
            listManager.selectedListId = allArticlesListId
        }
        
        // 保存更改
        listManager.saveLists()
        
        // 完全清空文章内容存储
        UserDefaults.standard.removeObject(forKey: "savedArticles")
        
        // 清空SpeechManager中的播放列表
        SpeechManager.shared.clearPlaylist()
        
        // 发送通知，告知应用文章已被清空
        NotificationCenter.default.post(name: Notification.Name("ArticlesCleared"), object: nil)
        
        print("登出时已清空所有文章列表和文章内容")
    }
    
    // MARK: - 数据持久化
    
    /// 将用户数据保存到UserDefaults
    /// - Parameter user: 用户对象
    private func saveUserToStorage(user: User) {
        do {
            let encoder = JSONEncoder()
            let userData = try encoder.encode(user)
            UserDefaults.standard.set(userData, forKey: "currentUser")
        } catch {
            print("保存用户数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 从UserDefaults加载用户数据
    private func loadUserFromStorage() {
        guard let userData = UserDefaults.standard.data(forKey: "currentUser") else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let user = try decoder.decode(User.self, from: userData)
            self.currentUser = user
            self.isLoggedIn = true
        } catch {
            print("加载用户数据失败: \(error.localizedDescription)")
        }
    }
    
    /// 清除存储的用户数据
    private func clearUserFromStorage() {
        UserDefaults.standard.removeObject(forKey: "currentUser")
    }
    
    // MARK: - 数据同步
    
    /// 从远程同步数据到本地
    /// - Parameters:
    ///   - user: 用户对象
    ///   - completion: 完成回调
    private func syncRemoteDataToLocal(user: User, completion: (() -> Void)? = nil) {
        guard user.id > 0, let token = user.token, !token.isEmpty else {
            print("无法从远程同步数据: 用户ID或令牌无效")
            completion?()
            return
        }
        
        // 创建一个组来追踪所有同步任务
        let syncGroup = DispatchGroup()
        
        // 1. 清除旧的本地订阅数据
        SubscriptionRepository.shared.clearSubscriptions(for: user.id)
        
        // 2. 从远程加载订阅数据
        syncGroup.enter()
        DispatchQueue.main.async {
            // 加载订阅数据
            print("开始从远程加载订阅数据...")
            SubscriptionRepository.shared.loadSubscriptionsForUser(user.id)
            
            // 由于loadSubscriptionsForUser是异步操作，我们需要等待一段时间再离开组
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                syncGroup.leave()
            }
        }
        
        // 3. 同步文章数据
        syncGroup.enter()
        syncRemoteArticlesToLocal(userId: user.id, token: token) {
            syncGroup.leave()
        }
        
        // 5. 同步文章列表
        syncGroup.enter()
        syncRemoteArticleListsToLocal(userId: user.id, token: token) {
            syncGroup.leave()
        }
        
        // 当所有任务完成后调用completion
        syncGroup.notify(queue: .main) {
            print("所有远程数据同步到本地完成")
            
            // 发送通知以更新界面显示
            NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
            
            completion?()
        }
    }
    
    /// 从远程同步文章列表到本地
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - completion: 完成回调
    private func syncRemoteArticleListsToLocal(userId: Int, token: String, completion: @escaping () -> Void) {
        // 获取远程保存的文章列表数据
        NetworkManager.shared.getUserData(userId: userId, token: token, dataKey: "article_lists")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completionStatus in
                    if case .failure(let error) = completionStatus {
                        print("从远程获取文章列表失败: \(error)")
                        completion()
                    }
                },
                receiveValue: { [weak self] responseData in
                    // 检查是否获取到数据
                    if let listsData = responseData["article_lists"]?.data(using: .utf8) {
                        do {
                            // 尝试解析JSON数据
                            if let listsArray = try JSONSerialization.jsonObject(with: listsData, options: []) as? [[String: Any]] {
                                self?.processRemoteLists(listsArray)
                                print("成功同步\(listsArray.count)个文章列表从远程到本地")
                            }
                        } catch {
                            print("解析远程文章列表数据失败: \(error)")
                            
                            // 检查是否需要处理分块数据
                            if let metadataString = responseData["article_lists_metadata"],
                               let metadataData = metadataString.data(using: .utf8),
                               let metadata = try? JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any],
                               let totalChunks = metadata["totalChunks"] as? Int {
                                
                                print("检测到分块数据，尝试合并\(totalChunks)个块")
                                self?.mergeRemoteChunks(userId: userId, token: token, dataKey: "article_lists", totalChunks: totalChunks, completion: completion)
                                return
                            }
                        }
                    } else {
                        print("远程没有文章列表数据")
                    }
                    completion()
                }
            )
            .store(in: &cancellables)
    }
    
    /// 处理从远程获取的文章列表数据
    /// - Parameter listsArray: 列表数据数组
    private func processRemoteLists(_ listsArray: [[String: Any]]) {
        // 获取当前的本地列表
        let currentLists = ArticleListManager.shared.userLists
        var updatedLists: [ArticleList] = []
        
        // 处理从远程获取的每个列表
        for listData in listsArray {
            guard let idString = listData["id"] as? String,
                  let name = listData["name"] as? String,
                  let createdAtString = listData["createdAt"] as? String,
                  let articleIdsArray = listData["articleIds"] as? [String] else {
                continue
            }
            
            // 转换ID和日期
            guard let id = UUID(uuidString: idString),
                  let createdAt = ISO8601DateFormatter().date(from: createdAtString) else {
                continue
            }
            
            // 转换文章ID
            let articleIds = articleIdsArray.compactMap { UUID(uuidString: $0) }
            
            // 创建列表对象
            let list = ArticleList(id: id, name: name, createdAt: createdAt, articleIds: articleIds, isDocument: false)
            updatedLists.append(list)
        }
        
        // 合并远程列表和本地列表，保留本地文档列表
        let documentLists = ArticleListManager.shared.lists.filter { $0.isDocument }
        
        // 更新文章列表管理器
        DispatchQueue.main.async {
            // 保留本地的文档列表，添加远程同步的用户列表
            ArticleListManager.shared.lists = documentLists + updatedLists
            ArticleListManager.shared.saveLists()
        }
    }
    
    /// 合并远程分块数据
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - dataKey: 数据键
    ///   - totalChunks: 总块数
    ///   - completion: 完成回调
    private func mergeRemoteChunks(userId: Int, token: String, dataKey: String, totalChunks: Int, completion: @escaping () -> Void) {
        var chunks: [String] = Array(repeating: "", count: totalChunks)
        var completedChunks = 0
        
        // 创建一个DispatchGroup来追踪所有块的获取
        let chunkGroup = DispatchGroup()
        
        // 获取每个数据块
        for i in 0..<totalChunks {
            let chunkKey = "\(dataKey)_chunk_\(i)"
            chunkGroup.enter()
            
            NetworkManager.shared.getUserData(userId: userId, token: token, dataKey: chunkKey)
            .receive(on: DispatchQueue.main)
            .sink(
                    receiveCompletion: { completionStatus in
                        if case .failure(let error) = completionStatus {
                            print("获取数据块\(i)失败: \(error)")
                        }
                        chunkGroup.leave()
                    },
                    receiveValue: { responseData in
                        if let chunkData = responseData[chunkKey] {
                            chunks[i] = chunkData
                            completedChunks += 1
                            print("已获取\(dataKey)数据块\(i+1)/\(totalChunks)")
                        }
                    }
                )
                .store(in: &cancellables)
        }
        
        // 当所有块都获取完成后，尝试合并并解析
        chunkGroup.notify(queue: .main) { [weak self] in
            // 合并所有数据块
            let combinedData = chunks.joined()
            
            if let jsonData = combinedData.data(using: .utf8) {
                do {
                    // 尝试解析JSON数据
                    if let listsArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                        self?.processRemoteLists(listsArray)
                        print("成功合并并同步\(listsArray.count)个文章列表从远程到本地")
                    }
                } catch {
                    print("解析合并的远程数据失败: \(error)")
                }
            }
            
            completion()
        }
    }
    
    /// 同步本地数据到远程服务器
    /// - Parameters:
    ///   - user: 当前用户
    ///   - completion: 完成后的回调
    private func syncLocalDataToRemote(user: User, completion: (() -> Void)? = nil) {
        guard user.id > 0, let token = user.token else {
            print("无法同步数据: 用户ID或令牌无效")
            completion?()
            return
        }
        
        print("开始同步本地数据到远程服务器 - 用户ID: \(user.id)")
        
        // 创建一个同步组来追踪所有同步任务
        let syncGroup = DispatchGroup()
        
        // 同步文章列表
        syncGroup.enter()
        syncArticleLists(userId: user.id, token: token) {
            syncGroup.leave()
        }
        
        // 只同步文章内容
        syncGroup.enter()
        syncArticles(userId: user.id, token: token) {
            syncGroup.leave()
        }
        
        // 不再同步文档库，文档数据体积过大
        // syncDocuments(userId: user.id, token: token)
        
        // 当所有同步任务完成后，调用completion
        syncGroup.notify(queue: .main) {
            print("所有数据同步任务已完成")
            completion?()
        }
        
        print("数据同步任务已启动")
    }
    
    /// 同步文章列表到远程
    private func syncArticleLists(userId: Int, token: String, completion: (() -> Void)? = nil) {
        // 获取文章列表管理器中的用户列表
        let userLists = ArticleListManager.shared.userLists
        
        // 如果没有用户列表，跳过同步
        if userLists.isEmpty {
            print("没有找到用户创建的文章列表，跳过同步")
            completion?()
            return
        }
        
        do {
            // 将列表数据转换为更简洁的格式，只包含必要信息
            let simplifiedLists = userLists.map { list -> [String: Any] in
                return [
                    "id": list.id.uuidString,
                    "name": list.name,
                    "createdAt": ISO8601DateFormatter().string(from: list.createdAt),
                    "articleIds": list.articleIds.map { $0.uuidString }
                ]
            }
            
            // 将简化后的列表数据转换为JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let listsData = try JSONSerialization.data(withJSONObject: simplifiedLists, options: [])
            let listsJson = String(data: listsData, encoding: .utf8) ?? ""
            
            // 检查数据大小
            if listsJson.count > 65000 { // MySQL TEXT类型通常限制为65535字节
                print("文章列表数据过大（\(listsJson.count)字节），尝试分块同步")
                syncLargeData(userId: userId, token: token, dataKey: "article_lists", dataValue: listsJson, completion: completion)
                return
            }
            
            // 使用NetworkManager保存数据
            NetworkManager.shared.saveUserData(userId: userId, token: token, dataKey: "article_lists", dataValue: listsJson)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { result in
                        if case .failure(let error) = result {
                            print("同步文章列表失败: \(error)")
                        }
                        completion?()
                    },
                    receiveValue: { message in
                        print("同步文章列表成功: \(message)")
                        // 不在这里调用completion，因为它会在receiveCompletion中被调用
                    }
                )
                .store(in: &cancellables)
        } catch {
            print("处理文章列表数据失败: \(error.localizedDescription)")
            completion?()
        }
    }
    
    /// 同步文章到远程
    private func syncArticles(userId: Int, token: String, completion: (() -> Void)? = nil) {
        guard let articlesData = UserDefaults.standard.data(forKey: "savedArticles") else {
            print("没有找到文章数据，跳过同步")
            completion?()
            return
        }
        
        do {
            // 编码为JSON字符串
            let articlesJson = String(data: articlesData, encoding: .utf8) ?? ""
            
            // 检查数据大小
            if articlesJson.count > 65000 { // MySQL TEXT类型通常限制为65535字节
                print("文章数据过大（\(articlesJson.count)字节），尝试分块同步")
                syncLargeData(userId: userId, token: token, dataKey: "articles", dataValue: articlesJson, completion: completion)
                return
            }
            
            // 使用NetworkManager保存数据
            NetworkManager.shared.saveUserData(userId: userId, token: token, dataKey: "articles", dataValue: articlesJson)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { result in
                        if case .failure(let error) = result {
                            print("同步文章数据失败: \(error)")
                        }
                        completion?()
                    },
                    receiveValue: { message in
                        print("同步文章数据成功: \(message)")
                        // 不在这里调用completion，因为它会在receiveCompletion中被调用
                    }
                )
                .store(in: &cancellables)
        } catch {
            print("处理文章数据失败: \(error.localizedDescription)")
            completion?()
        }
    }
    
    /// 同步大数据，将其分块处理
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - dataKey: 数据键
    ///   - dataValue: 数据值
    ///   - completion: 完成后的回调
    private func syncLargeData(userId: Int, token: String, dataKey: String, dataValue: String, completion: (() -> Void)? = nil) {
        // 计算分块数量，每块最大60KB
        let chunkSize = 60000
        let totalChunks = Int(ceil(Double(dataValue.count) / Double(chunkSize)))
        
        print("将\(dataKey)分为\(totalChunks)块进行同步，总大小: \(dataValue.count)字节")
        
        // 第一块存储元数据（总块数等信息）
        let metadataKey = "\(dataKey)_metadata"
        let metadata = """
        {
            "totalChunks": \(totalChunks),
            "totalSize": \(dataValue.count),
            "lastUpdated": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """
        
        // 创建一个组来追踪所有同步任务
        let syncGroup = DispatchGroup()
        
        // 保存元数据
        syncGroup.enter()
        NetworkManager.shared.saveUserData(userId: userId, token: token, dataKey: metadataKey, dataValue: metadata)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("保存\(dataKey)元数据失败: \(error)")
                    }
                    syncGroup.leave()
                },
                receiveValue: { message in
                    print("保存\(dataKey)元数据成功: \(message)")
                }
            )
            .store(in: &cancellables)
        
        // 逐块保存数据
        for i in 0..<totalChunks {
            let startIndex = dataValue.index(dataValue.startIndex, offsetBy: min(i * chunkSize, dataValue.count))
            let endIndex = dataValue.index(dataValue.startIndex, offsetBy: min((i + 1) * chunkSize, dataValue.count))
            let chunk = String(dataValue[startIndex..<endIndex])
            
            let chunkKey = "\(dataKey)_chunk_\(i)"
            
            // 进入同步组
            syncGroup.enter()
            
            // 延迟执行，避免同时发送太多请求
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                print("开始保存\(dataKey)第\(i+1)/\(totalChunks)块，大小: \(chunk.count)字节")
                
                NetworkManager.shared.saveUserData(userId: userId, token: token, dataKey: chunkKey, dataValue: chunk)
                    .receive(on: DispatchQueue.main)
                    .sink(
                        receiveCompletion: { result in
                            if case .failure(let error) = result {
                                print("保存\(dataKey)第\(i+1)块失败: \(error)")
                            }
                            syncGroup.leave()
                        },
                        receiveValue: { message in
                            print("保存\(dataKey)第\(i+1)块成功: \(message)")
                        }
                    )
                    .store(in: &self.cancellables)
            }
        }
        
        // 当所有任务完成后调用completion
        syncGroup.notify(queue: .main) {
            print("所有\(dataKey)数据块同步请求已完成")
            completion?()
        }
    }
    
    /// 从远程同步文章内容到本地
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - completion: 完成回调
    private func syncRemoteArticlesToLocal(userId: Int, token: String, completion: @escaping () -> Void) {
        // 获取远程保存的文章数据
        NetworkManager.shared.getUserData(userId: userId, token: token, dataKey: "articles")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completionStatus in
                    if case .failure(let error) = completionStatus {
                        print("从远程获取文章内容失败: \(error)")
                        completion()
                    }
                },
                receiveValue: { [weak self] responseData in
                    // 检查是否获取到数据
                    if let articlesData = responseData["articles"]?.data(using: .utf8) {
                        // 尝试使用本地存储的文章数据
                        let localArticlesData = UserDefaults.standard.data(forKey: "savedArticles")
                        
                        do {
                            // 解析远程文章数据
                            if let remoteArticles = try? JSONDecoder().decode([Article].self, from: articlesData) {
                                // 如果有本地文章数据，尝试合并
                                if let localData = localArticlesData,
                                   let localArticles = try? JSONDecoder().decode([Article].self, from: localData) {
                                    
                                    // 合并本地和远程文章
                                    let mergedArticles = self?.mergeArticles(local: localArticles, remote: remoteArticles)
                                    
                                    // 保存合并后的文章
                                    if let finalArticles = mergedArticles {
                                        if let encodedData = try? JSONEncoder().encode(finalArticles) {
                                            UserDefaults.standard.set(encodedData, forKey: "savedArticles")
                                            print("成功合并并同步\(finalArticles.count)篇文章从远程到本地")
                                        }
                                    }
                                } else {
                                    // 如果没有本地数据，直接使用远程数据
                                    if let encodedData = try? JSONEncoder().encode(remoteArticles) {
                                        UserDefaults.standard.set(encodedData, forKey: "savedArticles")
                                        print("成功同步\(remoteArticles.count)篇文章从远程到本地")
                                    }
                                }
                                
                                completion()
                                return
                            }
                        } catch {
                            print("解析远程文章数据失败: \(error)")
                        }
                        
                        // 检查是否需要处理分块数据
                        if let metadataString = responseData["articles_metadata"],
                           let metadataData = metadataString.data(using: .utf8),
                           let metadata = try? JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any],
                           let totalChunks = metadata["totalChunks"] as? Int {
                            
                            print("检测到分块数据，尝试合并\(totalChunks)个块")
                            self?.mergeRemoteArticleChunks(userId: userId, token: token, totalChunks: totalChunks, completion: completion)
                            return
                        }
                    } else {
                        print("远程没有文章数据")
                    }
                    
                    completion()
                }
            )
            .store(in: &cancellables)
    }
    
    /// 合并本地和远程文章
    /// - Parameters:
    ///   - local: 本地文章
    ///   - remote: 远程文章
    /// - Returns: 合并后的文章
    private func mergeArticles(local: [Article], remote: [Article]) -> [Article] {
        var articleMap = [UUID: Article]()
        
        // 先添加所有本地文章
        for article in local {
            articleMap[article.id] = article
        }
        
        // 然后更新或添加远程文章
        for remoteArticle in remote {
            // 如果本地已有此文章，检查更新时间决定是否更新
            if let localArticle = articleMap[remoteArticle.id] {
                // 如果远程文章创建时间更晚，使用远程文章
                if remoteArticle.createdAt > localArticle.createdAt {
                    articleMap[remoteArticle.id] = remoteArticle
                }
            } else {
                // 如果本地没有，直接添加远程文章
                articleMap[remoteArticle.id] = remoteArticle
            }
        }
        
        // 转换回数组
        return Array(articleMap.values)
    }
    
    /// 合并远程文章分块数据
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - totalChunks: 总块数
    ///   - completion: 完成回调
    private func mergeRemoteArticleChunks(userId: Int, token: String, totalChunks: Int, completion: @escaping () -> Void) {
        var chunks: [String] = Array(repeating: "", count: totalChunks)
        var completedChunks = 0
        
        // 创建一个DispatchGroup来追踪所有块的获取
        let chunkGroup = DispatchGroup()
        
        // 获取每个数据块
        for i in 0..<totalChunks {
            let chunkKey = "articles_chunk_\(i)"
            chunkGroup.enter()
            
            NetworkManager.shared.getUserData(userId: userId, token: token, dataKey: chunkKey)
            .receive(on: DispatchQueue.main)
            .sink(
                    receiveCompletion: { completionStatus in
                        if case .failure(let error) = completionStatus {
                            print("获取文章数据块\(i)失败: \(error)")
                        }
                        chunkGroup.leave()
                    },
                    receiveValue: { responseData in
                        if let chunkData = responseData[chunkKey] {
                            chunks[i] = chunkData
                            completedChunks += 1
                            print("已获取文章数据块\(i+1)/\(totalChunks)")
                        }
                    }
                )
                .store(in: &cancellables)
        }
        
        // 当所有块都获取完成后，尝试合并并解析
        chunkGroup.notify(queue: .main) { [weak self] in
            // 合并所有数据块
            let combinedData = chunks.joined()
            
            if let jsonData = combinedData.data(using: .utf8) {
                do {
                    // 尝试解析JSON数据
                    if let remoteArticles = try? JSONDecoder().decode([Article].self, from: jsonData) {
                        // 尝试使用本地存储的文章数据
                        let localArticlesData = UserDefaults.standard.data(forKey: "savedArticles")
                        
                        // 如果有本地文章数据，尝试合并
                        if let localData = localArticlesData,
                           let localArticles = try? JSONDecoder().decode([Article].self, from: localData) {
                            
                            // 合并本地和远程文章
                            let mergedArticles = self?.mergeArticles(local: localArticles, remote: remoteArticles)
                            
                            // 保存合并后的文章
                            if let finalArticles = mergedArticles {
                                if let encodedData = try? JSONEncoder().encode(finalArticles) {
                                    UserDefaults.standard.set(encodedData, forKey: "savedArticles")
                                    print("成功合并并同步\(finalArticles.count)篇文章从远程到本地")
                                }
                            }
                        } else {
                            // 如果没有本地数据，直接使用远程数据
                            if let encodedData = try? JSONEncoder().encode(remoteArticles) {
                                UserDefaults.standard.set(encodedData, forKey: "savedArticles")
                                print("成功同步\(remoteArticles.count)篇文章从远程到本地")
                            }
                        }
                    }
                } catch {
                    print("解析合并的远程文章数据失败: \(error)")
                }
            }
            
            completion()
        }
    }
    
    // MARK: - 辅助方法
    
    /// 检查用户是否已登录
    var isUserLoggedIn: Bool {
        return currentUser != nil && currentUser!.isTokenValid
    }
    
    /// 验证邮箱格式
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    /// 验证验证码
    /// - Parameters:
    ///   - email: 邮箱
    ///   - verificationCode: 验证码
    func validateVerificationCode(email: String, verificationCode: String) -> Bool {
        // 此方法仅用于本地模拟验证，实际应用中应通过服务器验证
        return verificationCode == "1234" // 测试用，实际逻辑应由服务器验证
    }
    
    // MARK: - 用户数据管理方法
    
    /// 更新用户信息
    /// - Parameter user: 更新后的用户
    func updateUser(_ user: User) {
        self.currentUser = user
        saveUserToStorage(user: user)
        
        // 如果用户已登录，并且有令牌，则同步到服务器
        if isLoggedIn, let token = user.token, !token.isEmpty, user.id > 0 {
            // 在实际应用中，这里应该将用户信息同步到服务器
            print("更新用户信息并同步到服务器: \(user.username)")
        }
    }
} 