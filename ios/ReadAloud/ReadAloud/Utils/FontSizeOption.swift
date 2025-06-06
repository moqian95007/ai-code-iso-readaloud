import Foundation
import SwiftUI

// 字体大小选项枚举，用于管理应用内的字体大小设置
enum FontSizeOption: String, CaseIterable {
    case small = "font_size_small"
    case medium = "font_size_medium"
    case large = "font_size_large"
    case extraLarge = "font_size_extra_large"
    
    // 返回对应的字体大小
    var size: CGFloat {
        switch self {
        case .small: return 14.0
        case .medium: return 18.0
        case .large: return 22.0
        case .extraLarge: return 26.0
        }
    }
    
    // 返回本地化的显示文本
    var localizedText: String {
        return self.rawValue.localized
    }
    
    // 返回下一个大小选项
    func next() -> FontSizeOption {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .extraLarge
        case .extraLarge: return .small
        }
    }
    
    // 从用户默认项中获取保存的字体大小选项
    static func fromUserDefaults() -> FontSizeOption {
        let savedOptionRawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.fontSizeOption) ?? FontSizeOption.medium.rawValue
        return FontSizeOption(rawValue: savedOptionRawValue) ?? .medium
    }
    
    // 保存选项到用户默认项
    func saveToUserDefaults() {
        UserDefaults.standard.set(self.rawValue, forKey: UserDefaultsKeys.fontSizeOption)
        UserDefaults.standard.set(self.size, forKey: UserDefaultsKeys.fontSize)
    }
} 