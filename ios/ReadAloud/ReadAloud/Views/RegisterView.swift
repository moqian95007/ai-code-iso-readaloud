import SwiftUI

/// 注册视图
struct RegisterView: View {
    // 环境变量
    @Environment(\.presentationMode) var presentationMode
    
    // 用户管理器
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var email: String = ""
    @State private var verificationCode: String = ""
    @State private var passwordError: String? = nil
    @State private var cooldownTime: Int = 0
    @State private var timer: Timer?
    @State private var registrationStep: RegistrationStep = .verifyEmail
    
    // 绑定变量，用于控制此视图的显示状态
    var isPresented: Binding<Bool>
    
    // 注册步骤枚举
    enum RegistrationStep {
        case verifyEmail
        case setPassword
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    // 标题
                    Text("创建账号")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 30)
                    
                    // 根据当前步骤显示不同的界面
                    if registrationStep == .verifyEmail {
                        // 第一步：验证邮箱
                        emailVerificationView
                    } else {
                        // 第二步：设置密码
                        passwordSetupView
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            .navigationBarTitle("注册", displayMode: .inline)
            .navigationBarItems(leading: Button(action: {
                if registrationStep == .setPassword {
                    // 返回到验证邮箱步骤
                    registrationStep = .verifyEmail
                } else {
                    // 关闭注册视图
                    isPresented.wrappedValue = false
                }
            }) {
                Text(registrationStep == .setPassword ? "返回" : "取消")
            })
            .onAppear {
                // 清除之前的验证状态
                userManager.verificationCodeSent = false
                userManager.codeVerified = false
                userManager.error = nil
            }
            .onDisappear {
                // 取消计时器
                timer?.invalidate()
                timer = nil
            }
        }
        // 监听登录状态
        .onChange(of: userManager.isLoggedIn) { newValue in
            if newValue {
                // 登录成功后关闭视图
                isPresented.wrappedValue = false
                presentationMode.wrappedValue.dismiss()
            }
        }
        // 监听验证状态
        .onChange(of: userManager.codeVerified) { newValue in
            if newValue {
                // 如果验证成功，进入下一步
                registrationStep = .setPassword
            }
        }
    }
    
    // MARK: - 子视图
    
    /// 邮箱验证视图
    private var emailVerificationView: some View {
        VStack {
            // 邮箱输入框和验证码发送按钮
            VStack(alignment: .leading) {
                Text("邮箱")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                HStack {
                    TextField("请输入邮箱", text: $email)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.emailAddress)
                    
                    Button(action: {
                        sendVerificationCode()
                    }) {
                        Text(cooldownTime > 0 ? "\(cooldownTime)秒" : "发送验证码")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 100)
                            .padding(.vertical, 10)
                            .background(cooldownTime > 0 ? Color.gray : Color.blue)
                            .cornerRadius(8)
                    }
                    .disabled(cooldownTime > 0 || email.isEmpty || !isValidEmail(email) || userManager.isLoading)
                }
            }
            .padding(.horizontal)
            
            // 验证码输入框
            VStack(alignment: .leading) {
                Text("验证码")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                TextField("请输入验证码", text: $verificationCode)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal)
            
            // 验证成功提示
            if userManager.verificationCodeSent {
                Text(userManager.verificationMessage)
                    .foregroundColor(.green)
                    .padding(.horizontal)
            }
            
            // 错误提示
            if let error = userManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // 验证按钮
            Button(action: {
                verifyCode()
            }) {
                if userManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                } else {
                    Text("验证")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .disabled(userManager.isLoading || !isEmailVerificationFormValid())
            .padding(.horizontal)
        }
    }
    
    /// 密码设置视图
    private var passwordSetupView: some View {
        VStack {
            // 提示信息
            if let suggestedUsername = userManager.suggestedUsername {
                Text("将使用 \(suggestedUsername) 作为您的用户名")
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
            
            // 密码输入框
            VStack(alignment: .leading) {
                Text("密码")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                SecureField("请输入密码", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .onChange(of: password) { _ in
                        validatePassword()
                    }
            }
            .padding(.horizontal)
            
            // 确认密码输入框
            VStack(alignment: .leading) {
                Text("确认密码")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                SecureField("请再次输入密码", text: $confirmPassword)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .onChange(of: confirmPassword) { _ in
                        validatePassword()
                    }
                
                // 密码错误提示
                if let error = passwordError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            
            // 错误提示
            if let error = userManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // 完成注册按钮
            Button(action: {
                completeRegistration()
            }) {
                if userManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                } else {
                    Text("完成注册")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .disabled(userManager.isLoading || !isPasswordFormValid())
            .padding(.horizontal)
        }
    }
    
    // MARK: - 辅助方法
    
    /// 发送验证码
    private func sendVerificationCode() {
        guard isValidEmail(email) else {
            userManager.error = "请输入有效的邮箱地址"
            return
        }
        
        userManager.sendVerificationCode(to: email)
        
        // 开始60秒倒计时
        cooldownTime = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if cooldownTime > 0 {
                cooldownTime -= 1
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
    
    /// 验证验证码
    private func verifyCode() {
        guard isValidEmail(email) else {
            userManager.error = "请输入有效的邮箱地址"
            return
        }
        
        guard !verificationCode.isEmpty else {
            userManager.error = "请输入验证码"
            return
        }
        
        userManager.verifyCode(email: email, code: verificationCode)
    }
    
    /// 完成注册
    private func completeRegistration() {
        guard validatePassword() else {
            return
        }
        
        userManager.completeRegistration(email: email, password: password)
    }
    
    /// 验证密码
    private func validatePassword() -> Bool {
        if password.isEmpty && confirmPassword.isEmpty {
            passwordError = nil
            return false
        } else if password.count < 6 {
            passwordError = "密码至少需要6个字符"
            return false
        } else if password != confirmPassword {
            passwordError = "两次输入的密码不一致"
            return false
        } else {
            passwordError = nil
            return true
        }
    }
    
    /// 邮箱验证表单是否有效
    private func isEmailVerificationFormValid() -> Bool {
        return !email.isEmpty && 
               !verificationCode.isEmpty && 
               isValidEmail(email)
    }
    
    /// 密码表单是否有效
    private func isPasswordFormValid() -> Bool {
        return !password.isEmpty && 
               !confirmPassword.isEmpty && 
               password == confirmPassword && 
               password.count >= 6
    }
    
    /// 验证邮箱格式
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}

struct RegisterView_Previews: PreviewProvider {
    static var previews: some View {
        RegisterView(isPresented: .constant(true))
    }
} 