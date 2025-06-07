import SwiftUI
import StoreKit

/// 会员订阅页面
struct SubscriptionView: View {
    // 环境变量
    @Environment(\.presentationMode) var presentationMode
    
    // 视图模型
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var selectedProductId: String? = nil
    @State private var isPurchasing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var isRestoring: Bool = false
    
    // 渐变颜色
    let gradientColors = [
        Color(red: 0.4, green: 0.2, blue: 0.8),
        Color(red: 0.1, green: 0.3, blue: 0.9)
    ]
    
    // 显示方式绑定
    var isPresented: Binding<Bool>
    
    // 初始化
    init(isPresented: Binding<Bool>) {
        self.isPresented = isPresented
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部背景图和标题
                    headerView
                    
                    VStack(spacing: 20) {
                        // 会员特权介绍
                        featuresView
                        
                        // 选择套餐标题
                        Text("select_plan".localized)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        
                        // 会员状态显示
                        if let user = userManager.currentUser, user.hasActiveSubscription {
                            // 已登录用户且有活跃订阅
                            activeSubscriptionView(user: user)
                            
                            // 添加分隔线
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            
                            // 添加续订或升级提示文本
                            Text("renew_or_upgrade_subscription".localized)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 5)
                        } else if !userManager.isLoggedIn && SubscriptionChecker.shared.hasPremiumAccess {
                            // 未登录用户但有活跃订阅
                            anonymousActiveSubscriptionView()
                            
                            // 添加分隔线
                            Divider()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            
                            // 添加续订或升级提示文本
                            Text("renew_or_upgrade_subscription".localized)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 5)
                            
                            // 添加登录建议
                            loginSuggestionView()
                        }
                        
                        // 无论是否已订阅，都显示会员套餐选择
                        subscriptionOptionsView
                        
                        // 加载中提示
                        if subscriptionService.isLoading || isPurchasing || isRestoring {
                            loadingView
                        }
                        
                        // 错误信息显示
                        if let error = errorMessage, showError {
                            errorView(message: error)
                        }
                        
                        // 底部说明
                        footerView
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
            .background(Color(UIColor.systemBackground))
            .navigationBarTitle(Text("subscribe_pro".localized), displayMode: .inline)
            .navigationBarItems(trailing: closeButton)
            .onAppear {
                print("========== 订阅页面出现 ==========")
                print("当前环境: \(StoreKitConfiguration.shared.isTestEnvironment ? "测试环境" : "生产环境")")
                print("已加载的产品数量: \(subscriptionService.products.count)")
                print("订阅服务加载状态: \(subscriptionService.isLoading ? "正在加载" : "未加载")")
                
                // 检查App Store收据
                if let receiptURL = Bundle.main.appStoreReceiptURL {
                    if let receiptData = try? Data(contentsOf: receiptURL) {
                        print("收据数据长度: \(receiptData.count)")
                        print("收据URL路径: \(receiptURL.path)")
                    } else {
                        print("⚠️ 无法读取收据数据")
                    }
                } else {
                    print("⚠️ 找不到App Store收据URL")
                }
                
                // 加载产品
                print("开始加载订阅产品...")
                subscriptionService.loadProducts()
                
                // 添加产品更新通知观察者
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("SubscriptionProductsUpdated"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("收到产品更新通知")
                    print("产品数量: \(self.subscriptionService.products.count)")
                    
                    if !self.subscriptionService.products.isEmpty {
                        print("可用产品列表:")
                        for (index, product) in self.subscriptionService.products.enumerated() {
                            print("  \(index+1). \(product.type.displayName) - \(product.localizedPrice)")
                        }
                    } else {
                        print("❌ 没有可用的订阅产品")
                        if let error = self.subscriptionService.errorMessage {
                            print("错误信息: \(error)")
                        }
                    }
                }
                
                // 添加订阅状态更新通知观察者
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("SubscriptionStatusUpdated"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("收到订阅状态更新通知")
                    
                    // 等待一秒后关闭页面
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.isPresented.wrappedValue = false
                    }
                }
                
                // 添加恢复购买失败通知观察者
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("SubscriptionRestorationFailed"),
                    object: nil,
                    queue: .main
                ) { notification in
                    self.isRestoring = false
                    
                    // 从通知中获取错误信息
                    let errorMsg = (notification.userInfo?["error"] as? String) ?? "未找到可恢复的购买"
                    self.errorMessage = errorMsg
                    self.showError = true
                    
                    print("恢复购买失败: \(errorMsg)")
                }
            }
            .onDisappear {
                print("========== 订阅页面消失 ==========")
                // 移除通知观察者
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SubscriptionProductsUpdated"), object: nil)
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SubscriptionRestorationFailed"), object: nil)
            }
        }
    }
    
    // MARK: - 子视图
    
    // 顶部视图
    private var headerView: some View {
        ZStack(alignment: .bottomLeading) {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: gradientColors),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 180)
                .edgesIgnoringSafeArea(.top)
            
            // VIP图标和标题
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.yellow)
                    
                    Text("pro_member".localized)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("pro_member_features".localized)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, 5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // 会员特权介绍
    private var featuresView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("pro_features".localized)
                .font(.headline)
                .padding(.horizontal, 20)
            
            VStack(spacing: 20) {
                featureRow(icon: "books.vertical.fill", title: "unlimited_articles".localized, subtitle: "unlimited_articles_desc".localized)
                featureRow(icon: "iphone.and.arrow.forward", title: "sync_across_devices".localized, subtitle: "sync_across_devices_desc".localized)
                featureRow(icon: "icloud.fill", title: "cloud_backup".localized, subtitle: "cloud_backup_desc".localized)
                featureRow(icon: "star.fill", title: "more_features_coming".localized, subtitle: "more_features_coming_desc".localized)
            }
            .padding(.horizontal, 5)
        }
    }
    
    // 特权行
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color.purple)
                .frame(width: 30, height: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 15)
    }
    
    // 活跃订阅视图
    private func activeSubscriptionView(user: User) -> some View {
        VStack(spacing: 15) {
            // 当前订阅信息标题
            Text("current_subscription".localized)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            // 订阅信息卡片
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(user.subscriptionType.simplifiedDisplayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let endDate = user.subscriptionEndDate {
                        Text("valid_until".localized + formattedDate(endDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 添加当前状态标签
                Text("active".localized)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    // 未登录用户的活跃订阅视图
    private func anonymousActiveSubscriptionView() -> some View {
        VStack(spacing: 15) {
            // 当前订阅信息标题
            Text("current_subscription".localized)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            // 订阅信息卡片
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 5) {
                    // 从UserDefaults获取订阅类型信息
                    if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo"),
                       let typeRawValue = subscriptionInfo["type"] as? String,
                       let type = SubscriptionType(rawValue: typeRawValue) {
                        Text(type.simplifiedDisplayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else {
                        Text("pro_member".localized)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    // 从UserDefaults获取到期时间
                    if let subscriptionInfo = UserDefaults.standard.dictionary(forKey: "tempSubscriptionInfo"),
                       let endDateTimeInterval = subscriptionInfo["endDate"] as? TimeInterval {
                        let endDate = Date(timeIntervalSince1970: endDateTimeInterval)
                        Text("valid_until".localized + formattedDate(endDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 添加当前状态标签
                Text("active".localized)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    // 登录建议视图
    private func loginSuggestionView() -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                
                Text("login_to_sync_subscription".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    // 关闭当前页面
                    self.isPresented.wrappedValue = false
                    
                    // 等待页面关闭后再打开登录页面
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // 发送通知，要求打开登录页面
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenLoginView"),
                            object: nil
                        )
                    }
                }) {
                    Text("login".localized)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    // 订阅选项视图
    private var subscriptionOptionsView: some View {
        VStack(spacing: 20) {
            // 订阅选项
            ForEach(subscriptionService.products.sorted(by: { getDiscountPercentage($0) > getDiscountPercentage($1) }), id: \.id) { product in
                productRow(product: product)
            }
            
            // 如果没有可用产品，显示加载中提示
            if subscriptionService.products.isEmpty && !subscriptionService.isLoading {
                Text("loading_products".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            // 恢复购买按钮 - 改为超链接样式
            Button(action: restorePurchases) {
                if isRestoring {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("restore_purchases".localized)
                        .font(.system(size: 15))
                        .foregroundColor(.blue)
                        .underline()
                }
            }
            .disabled(isRestoring)
            .padding(.top, 5)
            .padding(.bottom, 10)
        }
    }
    
    // 获取折扣百分比
    private func getDiscountPercentage(_ product: SubscriptionProduct) -> Int {
        switch product.type {
        case .yearly:
            return 30
        case .halfYearly:
            return 20
        case .quarterly:
            return 10
        default:
            return 0
        }
    }
    
    // 获取折扣标签颜色
    private func getDiscountColor(_ product: SubscriptionProduct) -> Color {
        switch product.type {
        case .yearly:
            return .red
        case .halfYearly:
            return .orange
        case .quarterly:
            return .blue
        default:
            return .gray
        }
    }
    
    // 产品行
    private func productRow(product: SubscriptionProduct) -> some View {
        Button(action: {
            purchaseProduct(product)
        }) {
            VStack(spacing: 8) {
                HStack {
                    Text(product.type.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(product.localizedPrice)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                if let pricePerMonth = product.pricePerMonth {
                    HStack {
                        Text(String(format: "price_per_month".localized, pricePerMonth))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // 显示折扣标签
                        let discount = getDiscountPercentage(product)
                        if discount > 0 {
                            Text(String(format: "save_percent".localized, discount))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(getDiscountColor(product))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedProductId == product.id ? 
                            Color.blue : Color.clear, 
                        lineWidth: 2
                    )
            )
            .padding(.horizontal, 20)
        }
        .disabled(isPurchasing || isRestoring)
    }
    
    // 底部说明
    private var footerView: some View {
        VStack(spacing: 8) {
            Text("subscription_note".localized)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            HStack(spacing: 5) {
                // 隐私政策链接
                Link("privacy_policy".localized, destination: URL(string: "https://readaloud.imoqian.cn/yszc.html")!)
                    .font(.footnote)
                
                Text("•")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                
                // 服务条款链接 - 修改为指向苹果标准EULA
                Link("terms_of_service".localized, destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.footnote)
            }
        }
        .padding(.top, 10)
    }
    
    // 加载视图
    private var loadingView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5)
                .padding()
            
            Text("processing".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 80)
    }
    
    // 错误视图
    private func errorView(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.red)
            .padding()
            .multilineTextAlignment(.center)
            .onAppear {
                // 5秒后自动隐藏错误信息
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        self.showError = false
                    }
                }
            }
    }
    
    // 关闭按钮
    private var closeButton: some View {
        Button(action: {
            self.isPresented.wrappedValue = false
        }) {
            Image(systemName: "xmark")
                .font(.headline)
        }
    }
    
    // MARK: - 辅助方法
    
    // 日期格式化
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // 购买产品
    private func purchaseProduct(_ product: SubscriptionProduct) {
        print("开始购买产品: \(product.type.displayName), 价格: \(product.localizedPrice)")
        
        selectedProductId = product.id
        isPurchasing = true
        errorMessage = nil
        showError = false
        
        // 修改为无需用户登录即可购买
        subscriptionService.purchaseSubscription(productId: product.id) { result in
            isPurchasing = false
            
            switch result {
            case .success(let subscriptionType):
                print("购买成功: \(subscriptionType.rawValue)")
                
                // 显示购买成功提示
                errorMessage = "purchase_success".localized
                showError = true
                
                // 发送通知更新订阅状态
                NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                
            case .failure(let error):
                print("购买失败: \(error.localizedDescription)")
                
                // 显示错误信息
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    // 恢复购买
    private func restorePurchases() {
        print("开始恢复购买")
        
        isRestoring = true
        errorMessage = nil
        showError = false
        
        // 修改为无需用户登录即可恢复购买
        subscriptionService.restorePurchases { result in
            isRestoring = false
            
            switch result {
            case .success(let restoredType):
                print("恢复购买成功: \(restoredType?.rawValue ?? "无")")
                
                if let type = restoredType, type != .none {
                    // 显示恢复成功提示
                    errorMessage = String(format: "restored_subscription".localized, type.displayName)
                    showError = true
                    
                    // 发送通知更新订阅状态
                    NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                } else {
                    // 显示未找到可恢复购买的提示
                    errorMessage = "no_purchases_to_restore".localized
                    showError = true
                }
                
            case .failure(let error):
                print("恢复购买失败: \(error.localizedDescription)")
                
                // 显示错误信息
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionView(isPresented: .constant(true))
    }
} 