import SwiftUI

// 添加登录提示类型枚举
enum LoginPromptType {
    case subscription
    case importPurchase
}

struct ProfileView: View {
    // 用户管理器
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var isShowingLogin: Bool = false
    @State private var isShowingSubscription: Bool = false
    @State private var isShowingImportPurchase: Bool = false // 添加导入次数购买状态
    @State private var isShowingLanguageSettings: Bool = false // 添加语言设置状态
    @State private var refreshView: Bool = false  // 添加刷新触发器
    @State private var showLoginAlert: Bool = false // 添加登录提示弹窗状态
    @State private var isShowingAbout: Bool = false // 添加关于页面状态
    @State private var showDeleteAccountAlert: Bool = false // 添加删除账户确认弹窗状态
    @State private var deleteAccountMessage: String = "" // 添加删除账户操作的消息
    @State private var showDeleteAccountResultAlert: Bool = false // 添加删除账户结果弹窗状态
    @State private var deleteAccountSuccess: Bool = false // 添加删除账户操作结果状态
    @State private var isShowingAccountSettings: Bool = false // 添加账号设置状态
    @State private var isLoggingOut = false
    
    // 添加登录提示相关状态
    @State private var showLoginPromptAlert: Bool = false
    @State private var currentLoginPromptType: LoginPromptType = .subscription
    @State private var loginPromptMessage: String = ""
    @State private var loginPromptTitle: String = ""
    @State private var continueAction: () -> Void = {}
    
    // 语言管理器
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 用户头像
                Image(systemName: userManager.isLoggedIn ? "person.circle.fill" : "person.slash.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .padding(.top, 50)
                
                // 用户名或登录按钮
                if userManager.isLoggedIn, let user = userManager.currentUser {
                    // 显示用户头像和信息区域
                    VStack(spacing: 10) {
                        // 显示用户名（如果有）
                        if !user.username.isEmpty {
                            Text(user.username)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        
                        // 显示电子邮箱（如果有）
                        if !user.email.isEmpty {
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        // 显示会员状态和剩余导入次数
                        VStack(spacing: 8) {
                            // 如果是PRO会员，显示会员标签
                            if user.hasActiveSubscription {
                                VStack(spacing: 5) {
                                    HStack {
                                        Image(systemName: "crown.fill")
                                            .foregroundColor(.yellow)
                                        Text("pro_member".localized)
                                            .foregroundColor(.orange)
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 12)
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(15)
                                    
                                    // 显示到期时间
                                    if let endDate = user.subscriptionEndDate {
                                        HStack {
                                            Image(systemName: "calendar")
                                                .foregroundColor(.gray)
                                                .font(.system(size: 12))
                                            Text("valid_until".localized + formattedDate(endDate))
                                                .foregroundColor(.gray)
                                                .font(.system(size: 12))
                                        }
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 8)
                                        .background(Color(UIColor.systemGray6))
                                        .cornerRadius(10)
                                    }
                                }
                            }
                            
                            // 所有用户都显示剩余导入次数
                            Text("remaining_imports".localized(with: userManager.getRemainingImportCount()))
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(15)
                        }
                        .padding(.top, 5)
                    }
                    .padding(.bottom, 10)
                } else {
                    // 显示登录/注册按钮
                    Button(action: {
                        isShowingLogin = true
                    }) {
                        Text("login_register".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 45)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.vertical, 15)
                    
                    // 添加未登录用户显示会员状态和剩余导入次数
                    VStack(spacing: 8) {
                        // 如果是PRO会员，显示会员标签
                        if SubscriptionChecker.shared.hasPremiumAccess {
                            VStack(spacing: 5) {
                                HStack {
                                    Image(systemName: "crown.fill")
                                        .foregroundColor(.yellow)
                                    Text("pro_member".localized)
                                        .foregroundColor(.orange)
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(15)
                                
                                // 显示到期时间，从UserDefaults获取
                                if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo"),
                                   let endDateTimeInterval = subscriptionInfo["endDate"] as? TimeInterval {
                                    let endDate = Date(timeIntervalSince1970: endDateTimeInterval)
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 12))
                                        Text("valid_until".localized + formattedDate(endDate))
                                            .foregroundColor(.gray)
                                            .font(.system(size: 12))
                                    }
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 8)
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        
                        // 显示剩余导入次数
                        let remainingImports = userManager.getRemainingImportCount()
                        Text("remaining_imports".localized(with: remainingImports))
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(15)
                    }
                    .padding(.top, 5)
                }
                
                // 分割线
                Divider()
                    .padding(.horizontal)
                
                // 设置项目列表
                List {
                    // 订阅会员项
                    Button(action: {
                        // 检查用户是否已登录
                        if !userManager.isLoggedIn {
                            // 显示登录提示
                            showLoginPrompt(forAction: .subscription)
                        } else {
                            isShowingSubscription = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 30)
                            
                            Text("subscription".localized)
                                .padding(.leading, 5)
                            
                            Spacer()
                            
                            if userManager.isLoggedIn, let user = userManager.currentUser, user.hasActiveSubscription {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("pro_member".localized)
                                        .font(.system(size: 14))
                                        .foregroundColor(.orange)
                                    
                                    if let endDate = user.subscriptionEndDate {
                                        Text("valid_until".localized + formattedDate(endDate))
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                            } else if !userManager.isLoggedIn && SubscriptionChecker.shared.hasPremiumAccess {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("pro_member".localized)
                                        .font(.system(size: 14))
                                        .foregroundColor(.orange)
                                    
                                    if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo"),
                                       let endDateTimeInterval = subscriptionInfo["endDate"] as? TimeInterval {
                                        let endDate = Date(timeIntervalSince1970: endDateTimeInterval)
                                        Text("valid_until".localized + formattedDate(endDate))
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 购买导入次数项
                    Button(action: {
                        // 检查用户是否已登录
                        if !userManager.isLoggedIn {
                            // 显示登录提示
                            showLoginPrompt(forAction: .importPurchase)
                        } else {
                            isShowingImportPurchase = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.fill.badge.plus")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            Text("buy_imports".localized)
                                .padding(.leading, 5)
                            
                            Spacer()
                            
                            // 显示统一的导入次数
                            Text("\(userManager.getRemainingImportCount())")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 语言设置选项
                    Button(action: {
                        isShowingLanguageSettings = true
                    }) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            Text("language".localized)
                                .padding(.leading, 5)
                            
                            Spacer()
                            
                            Text(languageManager.currentLanguage.displayName)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 添加账号设置选项
                    if userManager.isLoggedIn {
                        Button(action: {
                            isShowingAccountSettings = true
                        }) {
                            HStack {
                                Image(systemName: "person.text.rectangle")
                                    .foregroundColor(.blue)
                                    .frame(width: 30)
                                
                                Text("account_settings".localized)
                                    .foregroundColor(.blue)
                                    .padding(.leading, 5)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // 添加关于我们选项
                    Button(action: {
                        isShowingAbout = true
                    }) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            Text("about_us".localized)
                                .padding(.leading, 5)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if userManager.isLoggedIn {
                        // 退出登录按钮
                        Button(action: {
                            isLoggingOut = true
                            // 延迟一下再执行退出登录，以显示加载界面
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                userManager.logout()
                                // 给一些时间显示加载界面，然后隐藏
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isLoggingOut = false
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                    .foregroundColor(.red)
                                    .frame(width: 30)
                                
                                Text("logout".localized)
                                    .foregroundColor(.red)
                                    .padding(.leading, 5)
                                
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
                Spacer()
            }
            .navigationBarTitle("tab_profile".localized, displayMode: .inline)
            .onAppear {
                // 添加订阅状态更新通知观察者
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("SubscriptionStatusUpdated"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("ProfileView: 收到订阅状态更新通知")
                    self.refreshView.toggle() // 触发界面刷新
                }
                
                // 添加打开登录页面通知观察者
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("OpenLoginView"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("ProfileView: 收到打开登录页面通知")
                    isShowingLogin = true
                }
            }
            .onDisappear {
                // 移除通知观察者
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSNotification.Name("SubscriptionStatusUpdated"),
                    object: nil
                )
                
                // 移除打开登录页面通知观察者
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSNotification.Name("OpenLoginView"),
                    object: nil
                )
            }
            .id(refreshView) // 使用id强制视图在refreshView变化时重新构建
            // 添加登录提示弹窗（旧版，保留以供兼容）
            .alert("login_required".localized, isPresented: $showLoginAlert) {
                Button("login".localized, role: .none) {
                    isShowingLogin = true
                }
                Button("cancel".localized, role: .cancel) {}
            } message: {
                Text("login_required_message".localized)
            }
            // 添加自定义登录提示弹窗
            .alert(loginPromptTitle, isPresented: $showLoginPromptAlert) {
                Button("login".localized, role: .none) {
                    isShowingLogin = true
                }
                Button("continue_without_login".localized, role: .cancel) {
                    // 执行继续操作
                    continueAction()
                }
            } message: {
                Text(loginPromptMessage)
            }
            // 添加删除账户确认弹窗
            .alert("delete_account_confirm_title".localized, isPresented: $showDeleteAccountAlert) {
                Button("delete".localized, role: .destructive) {
                    // 调用删除账户方法
                    userManager.deleteAccount { success, message in
                        self.deleteAccountSuccess = success
                        self.deleteAccountMessage = message ?? (success ? "delete_account_success".localized : "delete_account_failed".localized)
                        self.showDeleteAccountResultAlert = true
                    }
                }
                Button("cancel".localized, role: .cancel) {}
            } message: {
                Text("delete_account_confirm_message".localized)
            }
            // 添加删除账户结果弹窗
            .alert(deleteAccountSuccess ? "success".localized : "error".localized, isPresented: $showDeleteAccountResultAlert) {
                Button("ok".localized, role: .cancel) {}
            } message: {
                Text(deleteAccountMessage)
            }
        }
        .sheet(isPresented: $isShowingLogin) {
            LoginView(isPresented: $isShowingLogin)
        }
        .sheet(isPresented: $isShowingSubscription) {
            SubscriptionView(isPresented: $isShowingSubscription)
        }
        .sheet(isPresented: $isShowingImportPurchase) {
            ImportPurchaseView(isPresented: $isShowingImportPurchase)
        }
        .sheet(isPresented: $isShowingLanguageSettings) {
            LanguageSettingsView(isPresented: $isShowingLanguageSettings)
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutView(isPresented: $isShowingAbout)
        }
        .sheet(isPresented: $isShowingAccountSettings) {
            AccountSettingsView(showDeleteAccountAlert: $showDeleteAccountAlert)
        }
        .overlay(
            // 退出登录加载覆盖层
            ZStack {
                if isLoggingOut {
                    Color.black.opacity(0.7)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("syncing_data".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .background(Color(.systemBackground).opacity(0.2))
                    .cornerRadius(20)
                    .shadow(radius: 15)
                }
            }
            .animation(.easeInOut, value: isLoggingOut)
        )
    }
    
    // 设置行
    private func settingRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(title)
                .padding(.leading, 5)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

// 账号设置视图
struct AccountSettingsView: View {
    @Binding var showDeleteAccountAlert: Bool
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        List {
            // 删除账户按钮
            Button(action: {
                showDeleteAccountAlert = true
                presentationMode.wrappedValue.dismiss() // 关闭当前视图以显示弹窗
            }) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .foregroundColor(.red)
                        .frame(width: 30)
                    
                    Text("delete_account".localized)
                        .foregroundColor(.red)
                        .padding(.leading, 5)
                    
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle("account_settings".localized, displayMode: .inline)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}

// 添加扩展，提供辅助方法
extension ProfileView {
    /// 格式化日期为可读形式
    /// - Parameter date: 日期对象
    /// - Returns: 格式化后的字符串
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// 添加showLoginPrompt方法
extension ProfileView {
    /// 显示登录提示
    /// - Parameter forAction: 登录提示类型
    private func showLoginPrompt(forAction: LoginPromptType) {
        currentLoginPromptType = forAction
        
        switch forAction {
        case .subscription:
            loginPromptTitle = "login_required_title".localized
            loginPromptMessage = "subscription_login_message".localized
            continueAction = {
                isShowingSubscription = true
            }
        case .importPurchase:
            loginPromptTitle = "login_required_title".localized
            loginPromptMessage = "import_login_message".localized
            continueAction = {
                isShowingImportPurchase = true
            }
        }
        
        showLoginPromptAlert = true
    }
} 