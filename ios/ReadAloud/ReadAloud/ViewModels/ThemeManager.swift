import SwiftUI

/// 管理应用主题设置的类
class ThemeManager: ObservableObject {
    // 共享实例
    static let shared = ThemeManager()
    
    // 当前主题设置
    @Published var isDarkMode: Bool
    @Published var fontSize: CGFloat
    @Published var fontSizeOption: FontSizeOption
    
    private init() {
        // 从UserDefaults读取保存的设置
        self.isDarkMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isDarkMode)
        self.fontSize = UserDefaults.standard.object(forKey: UserDefaultsKeys.fontSize) as? CGFloat ?? 18.0
        let savedOptionRawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.fontSizeOption) ?? FontSizeOption.medium.rawValue
        self.fontSizeOption = FontSizeOption(rawValue: savedOptionRawValue) ?? .medium
    }
    
    // 切换深色/浅色模式
    func toggleDarkMode() {
        isDarkMode.toggle()
        UserDefaults.standard.set(isDarkMode, forKey: UserDefaultsKeys.isDarkMode)
        
        // 发送通知，通知设置已更新
        NotificationCenter.default.post(name: NSNotification.Name("UserSettingsUpdated"), object: nil)
    }
    
    // 切换到下一个字体大小选项
    func nextFontSize() {
        fontSizeOption = fontSizeOption.next()
        fontSize = fontSizeOption.size
        fontSizeOption.saveToUserDefaults()
        
        // 发送通知，通知设置已更新
        NotificationCenter.default.post(name: NSNotification.Name("UserSettingsUpdated"), object: nil)
    }
    
    // 获取背景颜色
    func backgroundColor() -> Color {
        return isDarkMode ? Color.black : Color.white
    }
    
    // 获取前景颜色
    func foregroundColor() -> Color {
        return isDarkMode ? Color.white : Color.black
    }
    
    // 获取高亮背景颜色
    func highlightBackgroundColor(isHighlighted: Bool) -> Color {
        if isHighlighted {
            return isDarkMode ? Color.yellow.opacity(0.4) : Color.yellow.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    // 获取高亮背景颜色 - 播放状态版本
    func highlightBackgroundColor(isHighlighted: Bool, isPlayingHighlight: Bool = true) -> Color {
        if isHighlighted {
            if isPlayingHighlight {
                // 播放状态下使用黄色高亮
                return isDarkMode ? Color.yellow.opacity(0.4) : Color.yellow.opacity(0.3)
            } else {
                // 恢复状态下使用蓝色高亮
                return isDarkMode ? Color.blue.opacity(0.2) : Color.blue.opacity(0.15)
            }
        } else {
            return Color.clear
        }
    }
    
    // 获取高亮背景颜色 - 增强版
    func enhancedHighlightBackgroundColor(isHighlighted: Bool, range: Double) -> Color {
        if isHighlighted {
            let opacity = range * 0.5 + 0.2 // 范围从0.2到0.7
            return isDarkMode ? Color.yellow.opacity(opacity) : Color.yellow.opacity(opacity * 0.75)
        } else {
            return Color.clear
        }
    }
    
    // 获取滚动视图背景颜色
    func scrollViewBackgroundColor() -> Color {
        return isDarkMode ? Color(uiColor: .darkGray) : Color(uiColor: .secondarySystemBackground)
    }
}