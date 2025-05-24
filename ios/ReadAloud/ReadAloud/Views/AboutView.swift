import SwiftUI
import UIKit

struct AboutView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var developerModeManager = DeveloperModeManager.shared
    
    // 版本和构建号
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    // Toast状态
    @State private var showToast = false
    @State private var toastMessage = ""
    
    // 开发者菜单状态
    @State private var showDeveloperMenu = false
    
    var body: some View {
        NavigationView {
            List {
                // 应用图标和名称
                Section {
                    HStack {
                        // 使用UIKit获取应用图标
                        Image(uiImage: UIApplication.shared.icon ?? UIImage(systemName: "app.fill")!)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .cornerRadius(12)
                            .padding(.vertical, 10)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ReadAloud")
                                .font(.headline)
                            Text("app_tagline".localized)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.leading, 8)
                        
                        Spacer()
                    }
                }
                
                // 版本信息
                Section {
                    HStack {
                        Text("version".localized)
                        Spacer()
                        Text("\(appVersion)(\(buildNumber))")
                            .foregroundColor(.gray)
                            .versionTapDetection() // 添加版本号点击检测
                    }
                }
                
                // 隐私政策和服务条款
                Section(header: Text("legal_info".localized)) {
                    Link(destination: URL(string: "https://readaloud.imoqian.cn/yszc.html")!) {
                        HStack {
                            Text("privacy_policy".localized)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Link(destination: URL(string: "https://readaloud.imoqian.cn/fwtk.html")!) {
                        HStack {
                            Text("terms_of_service".localized)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // 技术支持
                Section(header: Text("support".localized)) {
                    Link(destination: URL(string: "https://readaloud.imoqian.cn/jszc.html")!) {
                        HStack {
                            Text("technical_support".localized)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Link("send_feedback_email".localized, destination: URL(string: "mailto:readaloud@ai-toolkit.top")!)
                }
                
                // 开发者选项（仅在开发者模式激活时显示）
                if developerModeManager.isEnabled {
                    Section(header: Text("developer_options".localized)) {
                        Button(action: {
                            showDeveloperMenu = true
                        }) {
                            HStack {
                                Text("view_logs".localized)
                                Spacer()
                                Image(systemName: "terminal.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            LogManager.shared.clearLogs()
                            toastMessage = "logs_cleared".localized
                            showToast = true
                        }) {
                            HStack {
                                Text("clear_logs".localized)
                                Spacer()
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("sandbox_environment".localized)
                            Spacer()
                            Text(StoreKitConfiguration.shared.isTestEnvironment ? "yes".localized : "no".localized)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // 版权信息
                Section {
                    HStack {
                        Spacer()
                        Text("© 2024 ReadAloud. All rights reserved.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("about".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: {
                isPresented = false
            }) {
                Text("done".localized)
                    .bold()
            })
            .sheet(isPresented: $showDeveloperMenu) {
                DeveloperMenuView()
            }
            .onChange(of: developerModeManager.isDeveloperModeEnabled) { newValue in
                // 当开发者模式状态改变时显示提示
                toastMessage = newValue ? "developer_mode_enabled".localized : "developer_mode_disabled".localized
                showToast = true
            }
            .overlay(
                ToastView(message: toastMessage, isShowing: $showToast)
                    .padding(.bottom, 100)
                , alignment: .bottom
            )
        }
    }
}

/// Toast视图
struct ToastView: View {
    let message: String
    @Binding var isShowing: Bool
    
    var body: some View {
        if isShowing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isShowing = false
                }
            }
            
            return AnyView(
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .transition(.opacity)
                    .animation(.easeInOut)
            )
        } else {
            return AnyView(EmptyView())
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView(isPresented: .constant(true))
    }
} 