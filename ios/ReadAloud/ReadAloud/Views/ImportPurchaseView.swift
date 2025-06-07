import SwiftUI
import StoreKit

/// 购买导入次数视图
struct ImportPurchaseView: View {
    // 环境变量
    @Environment(\.presentationMode) var presentationMode
    
    // 视图模型
    @ObservedObject private var importService = ImportPurchaseService.shared
    @ObservedObject private var userManager = UserManager.shared
    
    // 状态变量
    @State private var selectedProductId: String? = nil
    @State private var isPurchasing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var purchasedCount: Int = 0
    
    // 渐变颜色
    let gradientColors = [
        Color(red: 0.2, green: 0.6, blue: 0.8),
        Color(red: 0.1, green: 0.4, blue: 0.9)
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
                    
                    // 当前导入次数状态
                    if let user = userManager.currentUser {
                        currentStatusView(user: user)
                    }
                    
                    // 购买选项
                    purchaseOptionsView
                    
                    // 加载中提示
                    if importService.isLoading || isPurchasing {
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
            .navigationBarTitle(Text("buy_import_count".localized), displayMode: .inline)
            .navigationBarItems(trailing: closeButton)
            .onAppear {
                // 加载产品
                importService.loadProducts()
            }
            .alert("purchase_success".localized, isPresented: $showSuccessAlert) {
                Button("ok".localized, role: .cancel) {
                    // 关闭当前视图
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isPresented.wrappedValue = false
                    }
                }
            } message: {
                Text(String(format: "purchased_import_count".localized, purchasedCount))
            }
        }
    }
    
    // MARK: - 子视图
    
    // 关闭按钮
    private var closeButton: some View {
        Button(action: {
            isPresented.wrappedValue = false
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
    }
    
    // 顶部视图
    private var headerView: some View {
        ZStack(alignment: .bottomLeading) {
            // 渐变背景
            LinearGradient(gradient: Gradient(colors: gradientColors),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 150)
                .cornerRadius(0)
            
            // 图标和标题
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "doc.fill.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    
                    Text("import_count".localized)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("buy_import_desc".localized)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, 5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // 当前状态视图
    private func currentStatusView(user: User) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("current_status".localized)
                .font(.headline)
                .padding(.horizontal, 20)
            
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                        Text("remaining_import_count".localized)
                            .font(.system(size: 16, weight: .medium))
                    }
                    
                    Text("\(user.remainingImportCount) \("times".localized)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if user.hasActiveSubscription {
                    VStack(alignment: .center, spacing: 5) {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                            Text("member_privilege".localized)
                                .font(.system(size: 16, weight: .medium))
                        }
                        
                        Text("unlimited_import".localized)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 20)
        }
    }
    
    // 购买选项视图
    private var purchaseOptionsView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("select_purchase_plan".localized)
                .font(.headline)
                .padding(.horizontal, 20)
            
            ForEach(importService.products.sorted(by: { $0.count < $1.count }), id: \.id) { product in
                productCard(product: product)
            }
            
            // 购买按钮
            if !importService.products.isEmpty {
                Button(action: purchaseSelectedProduct) {
                    Text("buy_now".localized)
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
            }
        }
        .padding(.top, 5)
    }
    
    // 产品卡片
    private func productCard(product: ImportPurchaseService.ImportProduct) -> some View {
        Button(action: {
            selectedProductId = product.id
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(product.count) \("import_times".localized)")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text(product.localizedPrice)
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .strokeBorder(
                            selectedProductId == product.id ? gradientColors[0] : Color.gray,
                            lineWidth: 2
                        )
                        .frame(width: 26, height: 26)
                    
                    if selectedProductId == product.id {
                        Circle()
                            .fill(gradientColors[0])
                            .frame(width: 18, height: 18)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selectedProductId == product.id ? gradientColors[0] : Color.gray.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 加载视图
    private var loadingView: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            
            Text(isPurchasing ? "processing".localized : "loading_products".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.leading, 8)
        }
        .padding()
    }
    
    // 错误视图
    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .padding(.leading, 5)
            
            Spacer()
            
            Button(action: {
                showError = false
                errorMessage = nil
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal, 20)
    }
    
    // 底部描述
    private var footerView: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("purchase_note".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("import_purchase_details".localized)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            
            // 添加隐私政策和EULA链接
            HStack(spacing: 5) {
                // 隐私政策链接
                Link("privacy_policy".localized, destination: URL(string: "https://readaloud.imoqian.cn/yszc.html")!)
                    .font(.footnote)
                
                Text("•")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                
                // 服务条款链接 - 使用苹果标准EULA
                Link("terms_of_service".localized, destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.footnote)
            }
            .padding(.top, 5)
        }
    }
    
    // MARK: - 操作方法
    
    // 购买选中的产品
    private func purchaseSelectedProduct() {
        guard let productId = selectedProductId else { return }
        
        // 开始购买
        isPurchasing = true
        
        importService.purchaseImportCount(productId: productId) { result in
            isPurchasing = false
            
            switch result {
            case .success(let count):
                purchasedCount = count
                showSuccessAlert = true
                
                // 成功购买后，清除选中状态
                selectedProductId = nil
                
                // 发送通知刷新UI
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                    print("购买成功后发送刷新通知")
                }
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
} 