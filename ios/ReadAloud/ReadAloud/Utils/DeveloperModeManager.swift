import Foundation
import SwiftUI
import Combine

/// 开发者模式管理器
class DeveloperModeManager: ObservableObject {
    // 单例模式
    static let shared = DeveloperModeManager()
    
    // 发布开发者模式状态
    @Published var isDeveloperModeEnabled: Bool = false
    
    // 点击计数器和计时器
    private var tapCount = 0
    private var tapTimer: Timer?
    private let requiredTaps = 5
    private let tapTimeout = 3.0
    
    // UserDefaults键
    private let developerModeKey = "isDeveloperModeEnabled"
    
    // 私有初始化方法
    private init() {
        // 从UserDefaults加载状态
        isDeveloperModeEnabled = UserDefaults.standard.bool(forKey: developerModeKey)
    }
    
    /// 处理版本号点击
    func handleVersionTap() {
        // 增加点击计数
        tapCount += 1
        
        // 记录点击
        LogManager.shared.log("版本号被点击 (\(tapCount)/\(requiredTaps))", level: .debug, category: "开发者模式")
        
        // 重置计时器
        tapTimer?.invalidate()
        
        // 如果达到所需点击次数，激活开发者模式
        if tapCount >= requiredTaps {
            toggleDeveloperMode()
            tapCount = 0
            return
        }
        
        // 设置超时计时器
        tapTimer = Timer.scheduledTimer(withTimeInterval: tapTimeout, repeats: false) { [weak self] _ in
            self?.resetTapCount()
        }
    }
    
    /// 切换开发者模式
    private func toggleDeveloperMode() {
        isDeveloperModeEnabled.toggle()
        
        // 保存到UserDefaults
        UserDefaults.standard.set(isDeveloperModeEnabled, forKey: developerModeKey)
        
        // 记录日志
        let status = isDeveloperModeEnabled ? "启用" : "禁用"
        LogManager.shared.log("开发者模式已\(status)", level: .info, category: "开发者模式")
        
        // 显示提示
        showDeveloperModeToast(enabled: isDeveloperModeEnabled)
    }
    
    /// 重置点击计数
    private func resetTapCount() {
        if tapCount > 0 {
            LogManager.shared.log("版本号点击计数重置", level: .debug, category: "开发者模式")
            tapCount = 0
        }
    }
    
    /// 显示开发者模式状态提示
    private func showDeveloperModeToast(enabled: Bool) {
        let message = enabled ? "开发者模式已启用" : "开发者模式已禁用"
        #if os(iOS)
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
        #endif
        
        // 在这里可以添加Toast提示
        // 由于SwiftUI没有内置的Toast，可以使用第三方库或自定义视图
        // 或者依赖调用者在外部显示Toast
    }
    
    /// 检查开发者模式是否启用
    var isEnabled: Bool {
        return isDeveloperModeEnabled
    }
}

/// 版本点击检测视图修饰器
struct VersionTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                DeveloperModeManager.shared.handleVersionTap()
            }
    }
}

extension View {
    /// 添加版本号点击检测
    func versionTapDetection() -> some View {
        self.modifier(VersionTapModifier())
    }
} 