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
            .navigationBarTitle("订阅PRO会员", displayMode: .inline)
            .navigationBarItems(trailing: closeButton)
            .onAppear {
                // 加载产品
                subscriptionService.loadProducts()
                
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
                }
            }
            .onDisappear {
                // 移除通知观察者
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
                    
                    Text("PRO会员")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("解锁全部高级功能，畅享语音朗读")
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
            Text("会员特权")
                .font(.headline)
                .padding(.horizontal, 20)
            
            VStack(spacing: 15) {
                featureRow(icon: "books.vertical.fill", title: "无限文章", subtitle: "不限数量导入文档和文章")
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
                    Text("当前会员: \(user.subscriptionType.simplifiedDisplayName)")
                        .font(.headline)
                    
                    if let endDate = user.subscriptionEndDate {
                        Text("有效期至: \(formattedDate(endDate))")
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
                Text("管理订阅")
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
            Text("选择套餐")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            
            // 套餐列表
            ForEach(subscriptionService.products.sorted { 
                getSubscriptionOrder($0.type) > getSubscriptionOrder($1.type) 
            }, id: \.id) { product in
                subscriptionCard(product: product)
            }
            
            // 购买按钮
            if !subscriptionService.products.isEmpty {
                Button(action: purchaseSelectedSubscription) {
                    Text("立即订阅")
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
                    Text("恢复购买")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.top, 10)
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
                    Text("省30%")
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
                    Text("省20%")
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
                    Text("省10%")
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
            
            Text(isRestoring ? "正在恢复购买..." : (isPurchasing ? "正在处理购买..." : "加载产品信息..."))
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
            Text("订阅说明")
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("· 付款将在确认购买时，从iTunes账户中扣除\n· 订阅会在到期前24小时内自动续费，除非关闭自动续订\n· 您可以在购买后，前往iTunes账户设置管理或取消订阅\n· 已订阅的期间不可取消当前订阅")
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
            return "月度会员"
        case .quarterly:
            return "季度会员"
        case .halfYearly:
            return "半年会员"
        case .yearly:
            return "年度会员"
        case .none:
            return "无订阅"
        }
    }
    
    // 格式化日期
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
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
        
        // 检查是否使用StoreKit 2.0 API
        if #available(iOS 15.0, *), StoreKitConfiguration.shared.isTestEnvironment {
            print("使用StoreKit 2.0恢复购买")
            Task {
                do {
                    var hasRestoredSubscription = false
                    
                    // 使用StoreKit 2.0 API恢复购买
                    for await verification in StoreKit.Transaction.all {
                        do {
                            // 验证交易
                            let transaction = try verification.payloadValue
                            print("恢复购买成功: \(transaction.productID)")
                            hasRestoredSubscription = true
                            
                            // 获取当前用户
                            if let user = userManager.currentUser, user.id > 0 {
                                // 获取订阅类型
                                var subscriptionType: SubscriptionType = .none
                                switch transaction.productID {
                                case "top.ai-toolkit.readaloud.subscription.monthly":
                                    subscriptionType = .monthly
                                case "top.ai-toolkit.readaloud.subscription.quarterly":
                                    subscriptionType = .quarterly
                                case "top.ai-toolkit.readaloud.subscription.halfYearly":
                                    subscriptionType = .halfYearly
                                case "top.ai-toolkit.readaloud.subscription.yearly":
                                    subscriptionType = .yearly
                                default:
                                    subscriptionType = .none
                                }
                                
                                // 计算订阅有效期
                                let startDate = Date()
                                var endDate: Date
                                
                                switch subscriptionType {
                                case .monthly:
                                    endDate = Calendar.current.date(byAdding: .month, value: 1, to: startDate)!
                                case .quarterly:
                                    endDate = Calendar.current.date(byAdding: .month, value: 3, to: startDate)!
                                case .halfYearly:
                                    endDate = Calendar.current.date(byAdding: .month, value: 6, to: startDate)!
                                case .yearly:
                                    endDate = Calendar.current.date(byAdding: .year, value: 1, to: startDate)!
                                case .none:
                                    continue
                                }
                                
                                // 创建新的订阅
                                let subscription = Subscription(
                                    userId: user.id,
                                    type: subscriptionType,
                                    startDate: startDate,
                                    endDate: endDate,
                                    subscriptionId: "\(transaction.productID)_\(UUID().uuidString)"
                                )
                                
                                // 添加订阅记录
                                SubscriptionRepository.shared.addSubscription(subscription)
                                
                                // 发送通知，通知UI更新
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                                }
                            }
                        } catch {
                            print("恢复购买验证失败: \(error.localizedDescription)")
                        }
                    }
                    
                    // 如果没有恢复任何订阅，显示错误信息
                    DispatchQueue.main.async {
                        self.isRestoring = false
                        if !hasRestoredSubscription {
                            self.errorMessage = "未找到可恢复的购买"
                            self.showError = true
                        }
                    }
                }
            }
        } else {
            // 使用传统的StoreKit API恢复购买
            print("使用传统StoreKit API恢复购买")
            subscriptionService.restorePurchases { result in
                DispatchQueue.main.async {
                    self.isRestoring = false
                    
                    switch result {
                    case .success(let type):
                        if type == nil || type == .none {
                            self.errorMessage = "未找到可恢复的购买"
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
}

struct SubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionView(isPresented: .constant(true))
    }
} 