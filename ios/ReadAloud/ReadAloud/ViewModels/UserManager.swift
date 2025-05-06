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
    func loginWithApple(idToken: String, nonce: String, email: String, fullName: String) {
        isLoading = true
        error = nil
        
        // TODO: 实现和后端的Apple登录验证
        // 这里可以调用NetworkManager中的方法与服务器通信
        
        // 临时模拟登录成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isLoading = false
            
            // 创建模拟用户，注意使用正确的属性名和类型
            let user = User(
                id: 1,
                username: fullName.isEmpty ? "AppleUser" : fullName,
                email: email.isEmpty ? "apple_user@example.com" : email,
                token: "simulated_token_for_apple",
                registerDate: Date(),
                lastLogin: Date(),
                status: "active"
            )
            
            self.currentUser = user
            self.isLoggedIn = true
            self.saveUserToStorage(user: user)
        }
    }
    
    /// 使用Google账号登录
    /// - Parameters:
    ///   - idToken: Google ID令牌
    ///   - email: 邮箱
    ///   - name: 姓名
    func loginWithGoogle(idToken: String, email: String, name: String) {
        isLoading = true
        error = nil
        
        // TODO: 实现和后端的Google登录验证
        // 这里可以调用NetworkManager中的方法与服务器通信
        
        // 临时模拟登录成功
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isLoading = false
            
            // 创建模拟用户，注意使用正确的属性名和类型
            let user = User(
                id: 2,
                username: name.isEmpty ? "GoogleUser" : name,
                email: email.isEmpty ? "google_user@example.com" : email,
                token: "simulated_token_for_google",
                registerDate: Date(),
                lastLogin: Date(),
                status: "active"
            )
            
            self.currentUser = user
            self.isLoggedIn = true
            self.saveUserToStorage(user: user)
        }
    }
    
    // MARK: - Apple登录辅助方法
    
    /// 生成随机nonce用于防止重放攻击
    /// - Parameter length: nonce长度
    /// - Returns: 随机字符串
    func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("无法生成随机nonce. SecRandomCopyBytes失败，错误 \(errorCode)")
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
    
    /// 对nonce进行SHA256哈希处理
    /// - Parameter input: 输入字符串
    /// - Returns: SHA256哈希后的字符串
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // MARK: - 用户认证方法
    
    /// 用户登录
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
                }
            )
            .store(in: &cancellables)
    }
    
    /// 发送验证码
    /// - Parameter email: 邮箱地址
    func sendVerificationCode(email: String) {
        print("开始发送验证码到邮箱: \(email)")
        
        guard !email.isEmpty else {
            self.error = "请输入邮箱地址"
            return
        }
        
        // 验证邮箱格式
        guard isValidEmail(email) else {
            self.error = "请输入有效的邮箱地址"
            return
        }
        
        isLoading = true
        error = nil
        verificationCodeSent = false
        
        // 打印开始发送网络请求
        print("正在发送验证码请求...")
        
        // 使用延迟执行，确保UI更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NetworkManager.shared.sendVerificationCode(email: email)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { [weak self] completion in
                        self?.isLoading = false
                        print("验证码请求完成，状态: \(completion)")
                        
                        if case .failure(let error) = completion {
                            if case NetworkError.apiError(let message) = error {
                                self?.error = message
                                print("API错误: \(message)")
                            } else if case NetworkError.networkError(let error) = error {
                                self?.error = "网络错误: \(error.localizedDescription)"
                                print("网络错误: \(error)")
                            } else if case NetworkError.invalidURL = error {
                                self?.error = "无效的URL"
                                print("无效URL错误")
                            } else if case NetworkError.invalidResponse = error {
                                self?.error = "服务器响应无效"
                                print("无效响应错误")
                            } else if case NetworkError.invalidData = error {
                                self?.error = "数据无效"
                                print("无效数据错误")
                            } else if case NetworkError.decodingError(let error) = error {
                                print("解码错误: \(error)")
                                let errorMessage = "数据解析错误: \(error.localizedDescription)"
                                self?.error = errorMessage
                                self?.isLoading = false
                                self?.verificationCodeSent = false
                            } else {
                                self?.error = "发送验证码失败，请稍后再试"
                                print("其他错误: \(error)")
                            }
                            self?.verificationCodeSent = false
                        }
                    },
                    receiveValue: { [weak self] message in
                        print("成功收到验证码发送确认: \(message)")
                        self?.verificationMessage = message
                        self?.verificationCodeSent = true
                    }
                )
                .store(in: &self.cancellables)
        }
    }
    
    /// 用户注册
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    ///   - email: 电子邮箱
    ///   - verificationCode: 邮箱验证码
    func register(username: String, password: String, email: String, verificationCode: String) {
        isLoading = true
        error = nil
        
        NetworkManager.shared.register(username: username, password: password, email: email, verificationCode: verificationCode)
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
                }
            )
            .store(in: &cancellables)
    }
    
    /// 用户登出
    func logout() {
        currentUser = nil
        isLoggedIn = false
        clearUserFromStorage()
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
    func verifyCode(email: String, verificationCode: String) {
        isLoading = true
        error = nil
        
        print("正在验证邮箱: \(email) 的验证码")
        
        // 保存验证码，以便后续使用
        lastVerificationCode = verificationCode
        
        NetworkManager.shared.verifyCode(email: email, verificationCode: verificationCode)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        if case NetworkError.apiError(let message) = error {
                            self?.error = message
                        } else if case NetworkError.decodingError(_) = error {
                            self?.error = "响应解析错误，请联系客服"
                        } else if case NetworkError.networkError(_) = error {
                            self?.error = "网络连接错误，请检查网络"
                        } else if case NetworkError.invalidURL = error {
                            self?.error = "无效的URL"
                        } else if case NetworkError.invalidResponse = error {
                            self?.error = "服务器响应无效"
                        } else if case NetworkError.invalidData = error {
                            self?.error = "数据无效"
                        } else {
                            self?.error = "验证验证码失败，请稍后再试"
                        }
                        self?.codeVerified = false
                    }
                },
                receiveValue: { [weak self] response in
                    print("验证码验证成功: \(response)")
                    self?.codeVerified = true
                    self?.verifiedEmail = email
                    
                    // 提取推荐的用户名
                    self?.suggestedUsername = response.username_suggestion
                }
            )
            .store(in: &cancellables)
    }
    
    /// 完成注册
    /// - Parameters:
    ///   - password: 密码
    func completeRegistration(password: String) {
        guard let email = verifiedEmail, codeVerified else {
            error = "请先验证验证码"
            return
        }
        
        guard let verificationCode = lastVerificationCode else {
            error = "验证码信息丢失，请重新验证"
            return
        }
        
        isLoading = true
        error = nil
        
        // 使用原始验证码而不是固定字符串
        NetworkManager.shared.completeRegistration(email: email, password: password, verificationCode: verificationCode)
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
                    // 重置验证状态
                    self?.codeVerified = false
                    self?.verifiedEmail = nil
                    self?.suggestedUsername = nil
                    self?.lastVerificationCode = nil
                }
            )
            .store(in: &cancellables)
    }
} 