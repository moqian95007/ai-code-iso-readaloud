import Foundation
import Combine

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case invalidData
    case apiError(String)
    case decodingError(Error)
    case networkError(Error)
}

class NetworkManager {
    static let shared = NetworkManager()
    
    // 服务器基础URL
    private let baseURL = "https://readaloud.imoqian.cn/api"
    // 备用HTTP URL（如果HTTPS连接失败）
    private let backupBaseURL = "http://readaloud.imoqian.cn/api"
    
    // 判断是否需要使用备用URL
    private var useBackupURL = false
    
    private init() {}
    
    // MARK: - API请求方法
    
    /// 发送邮箱验证码
    /// - Parameter email: 邮箱地址
    /// - Returns: 包含消息的Publisher
    func sendVerificationCode(email: String) -> AnyPublisher<String, NetworkError> {
        print("准备发送验证码到: \(email)")
        
        // 使用表单数据格式而不是JSON
        let parameters = ["email": email]
        return requestWithFormData(endpoint: "/send_verification_code.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<String>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<String, NetworkError> in
                if response.status == "success" {
                    return Just(response.message ?? "验证码已发送，请查收邮箱")
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "发送验证码失败"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<String, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.sendVerificationCode(email: email)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 发送登录请求
    /// - Parameters:
    ///   - email: 邮箱
    ///   - password: 密码
    /// - Returns: 包含User对象的Publisher
    func login(email: String, password: String) -> AnyPublisher<User, NetworkError> {
        // 使用email参数发送邮箱
        let parameters = ["email": email, "password": password]
        return request(endpoint: "/login.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<User>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<User, NetworkError> in
                if response.status == "success", let user = response.data {
                    return Just(user)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "未知错误"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<User, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.login(email: email, password: password)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 发送注册请求
    /// - Parameters:
    ///   - username: 用户名
    ///   - password: 密码
    ///   - email: 邮箱
    ///   - verificationCode: 验证码
    /// - Returns: 包含User对象的Publisher
    func register(username: String, password: String, email: String, verificationCode: String) -> AnyPublisher<User, NetworkError> {
        let parameters: [String: Any] = [
            "username": username,
            "password": password,
            "email": email,
            "verification_code": verificationCode
        ]
        
        return request(endpoint: "/register.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<User>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<User, NetworkError> in
                if response.status == "success", let user = response.data {
                    return Just(user)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "未知错误"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<User, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.register(username: username, password: password, email: email, verificationCode: verificationCode)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 获取用户数据
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - dataKey: 可选的数据键
    /// - Returns: 包含用户数据的Publisher
    func getUserData(userId: Int, token: String, dataKey: String? = nil) -> AnyPublisher<[String: String], NetworkError> {
        var parameters: [String: Any] = [
            "user_id": userId,
            "token": token
        ]
        
        if let key = dataKey, !key.isEmpty {
            parameters["data_key"] = key
        }
        
        return request(endpoint: "/get_user_data.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<[String: String]>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<[String: String], NetworkError> in
                if response.status == "success", let data = response.data {
                    return Just(data)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "未知错误"))
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// 保存用户数据
    /// - Parameters:
    ///   - userId: 用户ID
    ///   - token: 用户令牌
    ///   - dataKey: 数据键
    ///   - dataValue: 数据值
    /// - Returns: 包含成功或失败消息的Publisher
    func saveUserData(userId: Int, token: String, dataKey: String, dataValue: String) -> AnyPublisher<String, NetworkError> {
        let parameters: [String: Any] = [
            "user_id": userId,
            "token": token,
            "data_key": dataKey,
            "data_value": dataValue
        ]
        
        return request(endpoint: "/save_user_data.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<String>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<String, NetworkError> in
                if response.status == "success" {
                    return Just(response.message ?? "数据保存成功")
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "未知错误"))
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// 用于验证码验证响应的结构体
    struct VerificationResponse: Codable {
        let email: String
        let verified: Bool
        let username_suggestion: String
    }
    
    /// 验证邮箱验证码
    /// - Parameters:
    ///   - email: 邮箱
    ///   - verificationCode: 验证码
    /// - Returns: 包含验证结果的Publisher
    func verifyCode(email: String, verificationCode: String) -> AnyPublisher<VerificationResponse, NetworkError> {
        let parameters: [String: Any] = [
            "email": email,
            "verification_code": verificationCode
        ]
        
        return request(endpoint: "/verify_code.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<VerificationResponse>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<VerificationResponse, NetworkError> in
                if response.status == "success", let data = response.data {
                    return Just(data)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "验证码验证失败"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<VerificationResponse, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.verifyCode(email: email, verificationCode: verificationCode)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 完成注册流程
    /// - Parameters:
    ///   - email: 邮箱
    ///   - password: 密码
    ///   - verificationCode: 验证码
    /// - Returns: 包含User对象的Publisher
    func completeRegistration(email: String, password: String, verificationCode: String) -> AnyPublisher<User, NetworkError> {
        let parameters: [String: Any] = [
            "email": email,
            "password": password,
            "verification_code": verificationCode
        ]
        
        return request(endpoint: "/register.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<User>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<User, NetworkError> in
                if response.status == "success", let user = response.data {
                    return Just(user)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "注册失败"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<User, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.completeRegistration(email: email, password: password, verificationCode: verificationCode)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 使用Apple ID登录
    /// - Parameters:
    ///   - idToken: Apple ID令牌
    ///   - nonce: 加密nonce
    ///   - email: 邮箱
    ///   - fullName: 用户全名
    ///   - appleUserId: Apple用户ID
    /// - Returns: 包含User对象的Publisher
    func loginWithApple(idToken: String, nonce: String, email: String, fullName: String, appleUserId: String) -> AnyPublisher<User, NetworkError> {
        let parameters: [String: Any] = [
            "id_token": idToken,
            "nonce": nonce,
            "email": email,
            "full_name": fullName,
            "apple_user_id": appleUserId,
            "login_type": "apple"
        ]
        
        print("发送Apple登录请求 - 参数: \(parameters)")
        
        return request(endpoint: "/third_party_login.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<User>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<User, NetworkError> in
                if response.status == "success", let user = response.data {
                    return Just(user)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "Apple登录失败"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<User, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.loginWithApple(idToken: idToken, nonce: nonce, email: email, fullName: fullName, appleUserId: appleUserId)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 使用Google账号登录
    /// - Parameters:
    ///   - idToken: Google ID令牌
    ///   - email: 邮箱
    ///   - name: 用户名
    /// - Returns: 包含User对象的Publisher
    func loginWithGoogle(idToken: String, email: String, name: String) -> AnyPublisher<User, NetworkError> {
        let parameters: [String: Any] = [
            "id_token": idToken,
            "email": email,
            "full_name": name,
            "login_type": "google"
        ]
        
        print("发送Google登录请求 - 参数: \(parameters)")
        
        return request(endpoint: "/third_party_login.php", method: "POST", parameters: parameters)
            .decode(type: APIResponse<User>.self, decoder: createDateFormattedDecoder())
            .mapError { error -> NetworkError in
                if let decodingError = error as? DecodingError {
                    print("解码错误: \(decodingError)")
                    return .decodingError(decodingError)
                } else if let networkError = error as? NetworkError {
                    return networkError
                } else {
                    print("未知错误: \(error)")
                    return .networkError(error)
                }
            }
            .flatMap { response -> AnyPublisher<User, NetworkError> in
                if response.status == "success", let user = response.data {
                    return Just(user)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: .apiError(response.message ?? "Google登录失败"))
                        .eraseToAnyPublisher()
                }
            }
            .catch { [weak self] error -> AnyPublisher<User, NetworkError> in
                // 如果遇到网络错误且尚未使用备用URL，尝试使用备用URL
                if case NetworkError.networkError(_) = error, let self = self, !self.useBackupURL {
                    print("主URL失败，尝试使用备用URL")
                    self.useBackupURL = true
                    return self.loginWithGoogle(idToken: idToken, email: email, name: name)
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    /// 执行网络请求并直接返回Data
    /// - Parameters:
    ///   - endpoint: API端点
    ///   - method: HTTP方法
    ///   - parameters: 请求参数
    /// - Returns: 包含原始Data的Publisher
    func performRequest(endpoint: String, method: String, parameters: [String: Any]? = nil) -> AnyPublisher<Data, NetworkError> {
        return request(endpoint: endpoint, method: method, parameters: parameters)
    }
    
    // MARK: - 私有辅助方法
    
    /// 通用网络请求方法
    /// - Parameters:
    ///   - endpoint: API端点
    ///   - method: HTTP方法
    ///   - parameters: 请求参数
    /// - Returns: Data Publisher
    private func request(endpoint: String, method: String, parameters: [String: Any]? = nil) -> AnyPublisher<Data, NetworkError> {
        // 根据条件选择URL基础地址
        let currentBaseURL = useBackupURL ? backupBaseURL : baseURL
        
        // 打印请求信息以便调试
        print("发送请求: \(currentBaseURL + endpoint)")
        
        guard let url = URL(string: currentBaseURL + endpoint) else {
            print("无效URL: \(currentBaseURL + endpoint)")
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // 增加超时时间
        
        if let params = parameters {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: params, options: [])
                request.httpBody = jsonData
                
                // 打印请求参数以便调试
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("请求参数: \(jsonString)")
                }
            } catch {
                print("参数序列化失败: \(error)")
                return Fail(error: NetworkError.invalidData).eraseToAnyPublisher()
            }
        }
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .mapError { error -> NetworkError in
                print("网络错误: \(error.localizedDescription)")
                return NetworkError.networkError(error)
            }
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("无效响应")
                    throw NetworkError.invalidResponse
                }
                
                // 打印响应状态码
                print("响应状态码: \(httpResponse.statusCode)")
                
                // 打印响应数据
                if let responseString = String(data: data, encoding: .utf8) {
                    print("响应数据: \(responseString)")
                    
                    // 检查是否收到HTML错误页面而不是JSON
                    if responseString.contains("<b>Fatal error</b>") || responseString.contains("<br />") {
                        throw NetworkError.apiError("服务器返回错误: \(responseString)")
                    }
                    
                    // 如果响应为空或不是有效JSON，尝试构建一个有效的JSON
                    if responseString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       (!responseString.contains("{") && !responseString.contains("[")) {
                        // 创建一个包含错误信息的JSON字符串
                        let errorJson = """
                        {
                            "status": "error",
                            "message": "服务器返回了无效的响应",
                            "data": null
                        }
                        """
                        if let errorData = errorJson.data(using: .utf8) {
                            return errorData
                        }
                    }
                }
                
                // 检查状态码
                if !(200...299).contains(httpResponse.statusCode) {
                    if let responseString = String(data: data, encoding: .utf8) {
                        throw NetworkError.apiError("服务器错误: \(httpResponse.statusCode), 响应: \(responseString)")
                    } else {
                        throw NetworkError.apiError("服务器错误: \(httpResponse.statusCode)")
                    }
                }
                
                return data
            }
            .mapError { error -> NetworkError in
                if let networkError = error as? NetworkError {
                    return networkError
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// 使用表单数据的网络请求方法
    /// - Parameters:
    ///   - endpoint: API端点
    ///   - method: HTTP方法
    ///   - parameters: 请求参数
    /// - Returns: Data Publisher
    private func requestWithFormData(endpoint: String, method: String, parameters: [String: Any]? = nil) -> AnyPublisher<Data, NetworkError> {
        // 根据条件选择URL基础地址
        let currentBaseURL = useBackupURL ? backupBaseURL : baseURL
        
        // 打印请求信息以便调试
        print("发送表单请求: \(currentBaseURL + endpoint)")
        
        guard let url = URL(string: currentBaseURL + endpoint) else {
            print("无效URL: \(currentBaseURL + endpoint)")
            return Fail(error: NetworkError.invalidURL).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30 // 增加超时时间
        
        if let params = parameters {
            // 使用表单格式而非JSON
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            // 构建表单字符串
            let formItems = params.map { key, value -> String in
                let escapedKey = "\(key)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let escapedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return escapedKey + "=" + escapedValue
            }
            let formString = formItems.joined(separator: "&")
            print("表单数据: \(formString)")
            
            request.httpBody = formString.data(using: .utf8)
        }
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .mapError { error -> NetworkError in
                print("网络错误: \(error.localizedDescription)")
                return NetworkError.networkError(error)
            }
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("无效响应")
                    throw NetworkError.invalidResponse
                }
                
                // 打印响应状态码
                print("响应状态码: \(httpResponse.statusCode)")
                
                // 打印响应数据
                if let responseString = String(data: data, encoding: .utf8) {
                    print("响应数据: \(responseString)")
                    
                    // 检查是否收到HTML错误页面而不是JSON
                    if responseString.contains("<b>Fatal error</b>") || responseString.contains("<br />") {
                        throw NetworkError.apiError("服务器返回错误: \(responseString)")
                    }
                    
                    // 如果响应为空或不是有效JSON，尝试构建一个有效的JSON
                    if responseString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                       (!responseString.contains("{") && !responseString.contains("[")) {
                        // 创建一个包含错误信息的JSON字符串
                        let errorJson = """
                        {
                            "status": "error",
                            "message": "服务器返回了无效的响应",
                            "data": null
                        }
                        """
                        if let errorData = errorJson.data(using: .utf8) {
                            return errorData
                        }
                    }
                }
                
                // 检查状态码
                if !(200...299).contains(httpResponse.statusCode) {
                    if let responseString = String(data: data, encoding: .utf8) {
                        throw NetworkError.apiError("服务器错误: \(httpResponse.statusCode), 响应: \(responseString)")
                    } else {
                        throw NetworkError.apiError("服务器错误: \(httpResponse.statusCode)")
                    }
                }
                
                return data
            }
            .mapError { error -> NetworkError in
                if let networkError = error as? NetworkError {
                    return networkError
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }
    
    // 创建一个配置好日期格式的解码器
    private func createDateFormattedDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }
}

/// API响应结构
struct APIResponse<T: Codable>: Codable {
    let status: String
    let message: String?
    let data: T?
}