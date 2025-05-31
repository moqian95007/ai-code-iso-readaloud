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
                VStack(spacing: 20) {
                    // 顶部背景图和标题
                    headerView
                    
                    // 会员特权介绍
                    featuresView
                    
                    // 会员状态显示
                    if let user = userManager.currentUser, user.hasActiveSubscription {
                        activeSubscriptionView(user: user)
                    } else {
                        // 会员套餐选择
                        subscriptionOptionsView
                    }
                    
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
                .padding(.bottom, 30)
            }
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
                .cornerRadius(0)
            
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
            
            VStack(spacing: 15) {
                featureRow(icon: "books.vertical.fill", title: "unlimited_articles".localized, subtitle: "unlimited_articles_desc".localized)
                featureRow(icon: "iphone.and.arrow.forward", title: "sync_across_devices".localized, subtitle: "sync_across_devices_desc".localized)
                featureRow(icon: "icloud.fill", title: "cloud_backup".localized, subtitle: "cloud_backup_desc".localized)
                featureRow(icon: "star.fill", title: "more_features_coming".localized, subtitle: "more_features_coming_desc".localized)
            }
            .padding(.horizontal, 5)
        }
        .padding(.vertical, 15)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .padding(.horizontal, 20)
    }
    
    // 特权行
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(gradientColors[0])
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
            // 订阅信息
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("current_plan".localized + user.subscriptionType.simplifiedDisplayName)
                        .font(.headline)
                    
                    if let endDate = user.subscriptionEndDate {
                        Text("valid_until".localized + formattedDate(endDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(10)
            
            // 管理订阅按钮
            Button(action: {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("manage_subscription".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient(gradient: Gradient(colors: gradientColors),
                                               startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // 会员套餐选择
    private var subscriptionOptionsView: some View {
        VStack(spacing: 15) {
            // 标题
            Text("select_plan".localized)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            if subscriptionService.products.isEmpty && !subscriptionService.isLoading {
                // 如果没有产品并且不在加载中，显示没有产品的提示
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    
                    Text("无法获取订阅产品信息")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text(subscriptionService.errorMessage ?? "请检查网络连接或稍后再试")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // 添加重试按钮
                    Button(action: {
                        print("用户点击重试按钮，重新加载订阅产品")
                        subscriptionService.loadProducts()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重新加载")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.top, 10)
                    
                    // 添加调试信息，仅在开发环境显示
                    #if DEBUG
                    VStack(alignment: .leading, spacing: 5) {
                        Text("调试信息：")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("产品数量：\(subscriptionService.products.count)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("错误信息：\(subscriptionService.errorMessage ?? "无")")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("环境：\(StoreKitConfiguration.shared.isTestEnvironment ? "测试环境" : "生产环境")")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("产品ID：\(ProductIdManager.shared.allSubscriptionProductIds.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                    .padding(.top, 10)
                    #endif
                    
                    // 提供手动恢复购买选项
                    Text("或者尝试恢复之前的购买")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                    
                    Button(action: restorePurchases) {
                        Text("恢复之前的购买")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 5)
                }
                .padding()
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 20)
            } else {
                // 套餐列表
                ForEach(subscriptionService.products.sorted { 
                    getSubscriptionOrder($0.type) > getSubscriptionOrder($1.type) 
                }, id: \.id) { product in
                    subscriptionCard(product: product)
                }
                
                // 购买按钮
                if !subscriptionService.products.isEmpty {
                    Button(action: purchaseSelectedSubscription) {
                        Text("subscribe_now".localized)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                selectedProductId != nil ?
                                LinearGradient(gradient: Gradient(colors: gradientColors),
                                              startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(gradient: Gradient(colors: [Color.gray, Color.gray]),
                                              startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(10)
                    }
                    .disabled(selectedProductId == nil)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // 恢复购买按钮
                    Button(action: restorePurchases) {
                        Text("restore_purchase".localized)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
    
    // 订阅卡片
    private func subscriptionCard(product: SubscriptionProduct) -> some View {
        let isSelected = selectedProductId == product.id
        
        return VStack(spacing: 0) {
            // 标题和价格
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(getSubscriptionTitle(for: product.type))
                        .font(.headline)
                    
                    if let perMonth = product.pricePerMonth, product.type == .yearly || product.type == .halfYearly || product.type == .quarterly {
                        Text(perMonth)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text(product.localizedPrice)
                    .font(.headline)
            }
            
            // 标签
            if product.type == .yearly {
                HStack {
                    Text("save_30_percent".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red)
                        .cornerRadius(4)
                    
                    Spacer()
                }
                .padding(.top, 8)
            } else if product.type == .halfYearly {
                HStack {
                    Text("save_20_percent".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .cornerRadius(4)
                    
                    Spacer()
                }
                .padding(.top, 8)
            } else if product.type == .quarterly {
                HStack {
                    Text("save_10_percent".localized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .cornerRadius(4)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? gradientColors[0] : Color.clear, lineWidth: 2)
                )
        )
        .padding(.horizontal, 20)
        .onTapGesture {
            self.selectedProductId = product.id
        }
    }
    
    // 加载视图
    private var loadingView: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            
            Text(isRestoring ? "restoring".localized : (isPurchasing ? "processing_purchase".localized : "loading_products".localized))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.leading, 10)
        }
        .padding()
    }
    
    // 错误视图
    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.leading, 5)
            
            Spacer()
            
            Button(action: {
                showError = false
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal, 20)
    }
    
    // 底部说明
    private var footerView: some View {
        VStack(spacing: 8) {
            Text("subscription_note".localized)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("subscription_details".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // 关闭按钮
    private var closeButton: some View {
        Button(action: {
            isPresented.wrappedValue = false
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .padding(8)
                .background(Color(UIColor.systemGray6))
                .clipShape(Circle())
        }
    }
    
    // MARK: - 辅助方法
    
    // 获取订阅类型的显示顺序
    private func getSubscriptionOrder(_ type: SubscriptionType) -> Int {
        switch type {
        case .yearly:
            return 4
        case .halfYearly:
            return 3
        case .quarterly:
            return 2
        case .monthly:
            return 1
        case .none:
            return 0
        }
    }
    
    // 根据类型获取订阅名称
    private func getSubscriptionTitle(for type: SubscriptionType) -> String {
        switch type {
        case .monthly:
            return "monthly_subscription".localized
        case .quarterly:
            return "quarterly_subscription".localized
        case .halfYearly:
            return "half_yearly_subscription".localized
        case .yearly:
            return "yearly_subscription".localized
        case .none:
            return "no_subscription".localized
        }
    }
    
    // 格式化日期
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        // 根据当前语言设置选择区域
        let isChineseLanguage = LanguageManager.shared.currentLanguage.languageCode == "zh-Hans"
        formatter.locale = Locale(identifier: isChineseLanguage ? "zh_CN" : "en_US")
        
        // 使用本地化的日期格式
        if isChineseLanguage {
            // 已有自定义的中文格式
            return formatter.string(from: date)
        } else {
            // 使用本地化字符串中定义的日期格式
            let dateString = formatter.string(from: date)
            return dateString
        }
    }
    
    // 购买选中的订阅
    private func purchaseSelectedSubscription() {
        guard let productId = selectedProductId else { return }
        
        isPurchasing = true
        errorMessage = nil
        showError = false
        
        subscriptionService.purchaseSubscription(productId: productId) { result in
            DispatchQueue.main.async {
                self.isPurchasing = false
                
                switch result {
                case .success:
                    // 购买成功，关闭订阅页面
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.isPresented.wrappedValue = false
                    }
                case .failure(let error):
                    // 显示错误
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
    
    // 恢复购买
    private func restorePurchases() {
        isRestoring = true
        errorMessage = nil
        showError = false
        
        // 使用传统的StoreKit API恢复购买，避免重复创建订阅
        print("使用订阅服务恢复购买")
        subscriptionService.restorePurchases { result in
            DispatchQueue.main.async {
                self.isRestoring = false
                
                switch result {
                case .success(let type):
                    if type == nil || type == .none {
                        self.errorMessage = "no_restorable_purchases".localized
                        self.showError = true
                    } else {
                        // 恢复成功，等待1秒后关闭订阅页面
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.isPresented.wrappedValue = false
                        }
                    }
                case .failure(let error):
                    // 显示错误
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
}

struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionView(isPresented: .constant(true))
    }
} 