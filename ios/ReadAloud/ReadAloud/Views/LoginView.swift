import SwiftUI
import AuthenticationServices

/// 登录视图
struct LoginView: View {
    // 环境变量
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    
    // 用户管理器
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isShowingRegister: Bool = false
    
    // 绑定变量，用于控制此视图的显示状态
    var isPresented: Binding<Bool>
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 15) {
                    // 标题
                    Text("账号登录")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 20)
                    
                    // 邮箱输入框
                    VStack(alignment: .leading) {
                        Text("邮箱")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        TextField("请输入邮箱", text: $email)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                    }
                    .padding(.horizontal)
                    
                    // 密码输入框
                    VStack(alignment: .leading) {
                        Text("密码")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        SecureField("请输入密码", text: $password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    
                    // 错误提示
                    if let error = userManager.error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // 登录按钮
                    Button(action: {
                        userManager.login(email: email, password: password)
                    }) {
                        if userManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(8)
                        } else {
                            Text("登录")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                    .disabled(userManager.isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal)
                    
                    // 注册链接
                    Button(action: {
                        isShowingRegister = true
                    }) {
                        Text("没有账号？立即注册")
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)
                    
                    // 分隔线
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        
                        Text("或")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    // Apple登录按钮
                    Button(action: {
                        signInWithApple()
                    }) {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text("通过 Apple 继续")
                                .font(.headline)
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                .background(colorScheme == .dark ? Color.black : Color.white)
                                .cornerRadius(8)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Google登录按钮
                    Button(action: {
                        signInWithGoogle()
                    }) {
                        HStack {
                            Image("google_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("通过 Google 继续")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                .background(Color.white)
                                .cornerRadius(8)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitle("登录", displayMode: .inline)
            .navigationBarItems(leading: Button(action: {
                isPresented.wrappedValue = false
            }) {
                Text("取消")
            })
            .sheet(isPresented: $isShowingRegister) {
                RegisterView(isPresented: $isShowingRegister)
            }
            .background(Color(UIColor.systemBackground))
        }
        // 监听登录状态
        .onChange(of: userManager.isLoggedIn) { newValue in
            if newValue {
                // 登录成功后关闭视图
                isPresented.wrappedValue = false
                presentationMode.wrappedValue.dismiss()
            }
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - 登录方法
    
    private func signInWithApple() {
        // 使用AppleSignInHandler处理Apple登录流程
        AppleSignInHandler.shared.startSignInWithAppleFlow(onSuccess: { idToken, nonce, email, fullName, appleUserId in
            // 登录成功后调用UserManager的Apple登录方法
            userManager.loginWithApple(idToken: idToken, nonce: nonce, email: email, fullName: fullName, appleUserId: appleUserId)
        }, onError: { error in
            // 登录失败显示错误
            userManager.error = error.localizedDescription
        })
    }
    
    private func signInWithGoogle() {
        // 使用GoogleSignInHandler启动Google登录流程
        GoogleSignInHandler.shared.startSignInWithGoogleFlow(
            onSuccess: { (idToken, email, name) in
                print("Google登录成功：用户 \(name)，邮箱 \(email)")
                
                // 调用API进行Google登录
                userManager.loginWithGoogle(idToken: idToken, email: email, name: name)
            },
            onError: { errorMessage in
                // 更新错误状态
                userManager.error = errorMessage
            }
        )
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(isPresented: .constant(true))
    }
}

// MARK: - Apple Sign In 处理类
/// 处理Apple登录的类，负责管理Apple认证流程
class AppleSignInHandler: NSObject {
    static let shared = AppleSignInHandler()
    
    // 回调闭包
    private var onSuccessHandler: ((String, String, String, String, String) -> Void)?
    private var onErrorHandler: ((Error) -> Void)?
    
    // 保存当前nonce
    private var currentNonce: String?
    
    /// 开始Apple登录流程
    /// - Parameters:
    ///   - onSuccess: 成功回调，返回(idToken, nonce, email, fullName, appleUserId)
    ///   - onError: 失败回调，返回错误信息
    func startSignInWithAppleFlow(onSuccess: @escaping (String, String, String, String, String) -> Void, onError: @escaping (Error) -> Void) {
        self.onSuccessHandler = onSuccess
        self.onErrorHandler = onError
        
        // 生成随机nonce，用于防止重放攻击
        let nonce = UserManager.shared.randomNonceString()
        currentNonce = nonce
        
        // 创建Apple登录请求
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        // 设置nonce，将被加密到JWT中
        request.nonce = UserManager.shared.sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

// MARK: - Apple Sign In 扩展
extension AppleSignInHandler: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let window = UIApplication.shared.windows.first else {
            fatalError("没有可用的窗口")
        }
        return window
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // 打印完整的Apple凭证信息
            print("------- Apple登录详细信息 -------")
            print("User ID: \(appleIDCredential.user)")
            print("Full Name: \(String(describing: appleIDCredential.fullName))")
            print("Email: \(String(describing: appleIDCredential.email))")
            print("实名认证状态: \(String(describing: appleIDCredential.realUserStatus.rawValue))")
            
            if let fullName = appleIDCredential.fullName {
                print("First Name: \(String(describing: fullName.givenName))")
                print("Middle Name: \(String(describing: fullName.middleName))")
                print("Last Name: \(String(describing: fullName.familyName))")
                print("Nickname: \(String(describing: fullName.nickname))")
                print("Name Prefix: \(String(describing: fullName.namePrefix))")
                print("Name Suffix: \(String(describing: fullName.nameSuffix))")
            }
            
            if let authorizationCode = appleIDCredential.authorizationCode {
                let authCodeString = String(data: authorizationCode, encoding: .utf8) ?? "N/A"
                print("Authorization Code: \(authCodeString)")
            }
            
            print("------- Apple登录详细信息结束 -------")
            
            guard let nonce = currentNonce else {
                print("无效的状态：登录回调时没有nonce")
                let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的状态：登录回调时没有nonce"])
                onErrorHandler?(error)
                return
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("无法获取身份令牌")
                let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取身份令牌"])
                onErrorHandler?(error)
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("无法序列化令牌字符串")
                let error = NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法序列化令牌字符串"])
                onErrorHandler?(error)
                return
            }
            
            // 获取用户信息
            let email = appleIDCredential.email ?? ""
            var fullName = ""
            
            if let firstName = appleIDCredential.fullName?.givenName,
               let lastName = appleIDCredential.fullName?.familyName {
                fullName = "\(firstName) \(lastName)"
            } else if let firstName = appleIDCredential.fullName?.givenName {
                fullName = firstName
            } else if let lastName = appleIDCredential.fullName?.familyName {
                fullName = lastName
            } else {
                // 如果没有名字信息，使用user标识符的一部分作为用户名
                fullName = "AppleUser_\(appleIDCredential.user.prefix(5))"
            }
            
            print("Apple登录成功: 邮箱 \(email), 名称 \(fullName), User ID: \(appleIDCredential.user)")
            
            // 调用成功回调
            onSuccessHandler?(idTokenString, nonce, email, fullName, appleIDCredential.user)
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Apple登录失败: \(error.localizedDescription)")
        
        // 处理特定类型的错误
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                print("用户取消了登录")
                onErrorHandler?(NSError(domain: "AppleSignIn", code: authError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "用户取消了登录"]))
            case .invalidResponse:
                print("无效的响应")
                onErrorHandler?(NSError(domain: "AppleSignIn", code: authError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "无效的响应"]))
            case .notHandled:
                print("请求未被处理")
                onErrorHandler?(NSError(domain: "AppleSignIn", code: authError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "请求未被处理"]))
            case .failed:
                print("授权失败")
                onErrorHandler?(NSError(domain: "AppleSignIn", code: authError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "授权失败"]))
            case .notInteractive:
                print("请求需要交互但无法显示")
                onErrorHandler?(NSError(domain: "AppleSignIn", code: authError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "请求需要交互但无法显示"]))
            @unknown default:
                print("未知错误: \(authError.code.rawValue)")
                onErrorHandler?(NSError(domain: "AppleSignIn", code: authError.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "未知错误: \(authError.code.rawValue)"]))
            }
        } else {
            onErrorHandler?(error)
        }
    }
} 