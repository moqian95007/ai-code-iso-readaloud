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
    }
    
    // 切换到下一个字体大小选项
    func nextFontSize() {
        fontSizeOption = fontSizeOption.next()
        fontSize = fontSizeOption.size
        fontSizeOption.saveToUserDefaults()
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
    
    // 获取滚动视图背景颜色
    func scrollViewBackgroundColor() -> Color {
        return isDarkMode ? Color(uiColor: .darkGray) : Color(uiColor: .secondarySystemBackground)
    }
}