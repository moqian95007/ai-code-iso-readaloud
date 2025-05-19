import SwiftUI

struct ProfileView: View {
    // 用户管理器
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var isShowingLogin: Bool = false
    @State private var isShowingSubscription: Bool = false
    @State private var isShowingImportPurchase: Bool = false // 添加导入次数购买状态
    @State private var refreshView: Bool = false  // 添加刷新触发器
    @State private var showLoginAlert: Bool = false // 添加登录提示弹窗状态
    
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
                                HStack {
                                    Image(systemName: "crown.fill")
                                        .foregroundColor(.yellow)
                                    Text("PRO会员")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(15)
                            }
                            
                            // 所有用户都显示剩余导入次数
                            Text("剩余导入\(user.remainingImportCount)次")
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
                        Text("登录/注册")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 45)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.vertical, 15)
                }
                
                // 分割线
                Divider()
                    .padding(.horizontal)
                
                // 设置项目列表
                List {
                    // 会员订阅项 - 不论是否登录都显示
                    Button(action: {
                        if userManager.isLoggedIn {
                            isShowingSubscription = true
                        } else {
                            // 显示登录提示
                            showLoginAlert = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 30)
                            
                            Text("会员订阅")
                                .padding(.leading, 5)
                            
                            Spacer()
                            
                            if let user = userManager.currentUser, user.hasActiveSubscription {
                                Text("PRO会员")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // 购买导入次数项
                    Button(action: {
                        if userManager.isLoggedIn {
                            isShowingImportPurchase = true
                        } else {
                            // 显示登录提示
                            showLoginAlert = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.fill.badge.plus")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            
                            Text("购买导入次数")
                                .padding(.leading, 5)
                            
                            Spacer()
                            
                            if let user = userManager.currentUser {
                                Text("\(user.remainingImportCount)次")
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if userManager.isLoggedIn {
                        settingRow(icon: "person.crop.circle", title: "个人信息")
                    }
                    
                    settingRow(icon: "gear", title: "设置")
                    settingRow(icon: "star.fill", title: "我的收藏")
                    settingRow(icon: "arrow.down.circle.fill", title: "下载管理")
                    settingRow(icon: "moon.fill", title: "深色模式")
                    settingRow(icon: "questionmark.circle", title: "帮助与反馈")
                    settingRow(icon: "info.circle", title: "关于我们")
                    
                    if userManager.isLoggedIn {
                        // 退出登录按钮
                        Button(action: {
                            userManager.logout()
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                    .foregroundColor(.red)
                                    .frame(width: 30)
                                
                                Text("退出登录")
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
            .navigationBarTitle("我的", displayMode: .inline)
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
            }
            .onDisappear {
                // 移除通知观察者
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSNotification.Name("SubscriptionStatusUpdated"),
                    object: nil
                )
            }
            .id(refreshView) // 使用id强制视图在refreshView变化时重新构建
            // 添加登录提示弹窗
            .alert("需要登录", isPresented: $showLoginAlert) {
                Button("登录", role: .none) {
                    isShowingLogin = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请先登录以访问此功能")
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

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
} 