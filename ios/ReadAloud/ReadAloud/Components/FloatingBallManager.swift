import SwiftUI

/// 管理浮动球状态的类
class FloatingBallManager: ObservableObject {
    @Published var isVisible = true
    @Published var position = CGPoint(x: UIScreen.main.bounds.width - 40, y: UIScreen.main.bounds.height * 4/5)
    
    // 单例模式
    static let shared = FloatingBallManager()
    
    private init() {}
    
    // 显示浮动球
    func show() {
        isVisible = true
    }
    
    // 隐藏浮动球
    func hide() {
        isVisible = false
    }
} 