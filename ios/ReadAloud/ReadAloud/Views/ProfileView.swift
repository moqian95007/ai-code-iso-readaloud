import SwiftUI

struct ProfileView: View {
    // 用户管理器
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var isShowingLogin: Bool = false
    
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
        }
        .sheet(isPresented: $isShowingLogin) {
            LoginView(isPresented: $isShowingLogin)
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