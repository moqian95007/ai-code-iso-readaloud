import Foundation
import Combine

// 支持的语言选项
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system" // 跟随系统
    case english = "en"
    case chinese = "zh-Hans"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .system:
            return "follow_system".localized
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }
    
    var languageCode: String {
        switch self {
        case .system:
            // 获取系统语言，如果不是中文则默认为英文
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            return preferredLanguage.starts(with: "zh") ? "zh-Hans" : "en"
        default:
            return self.rawValue
        }
    }
}

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    // 定义使用的本地化Bundle
    private var currentBundle: Bundle?
    
    // 当前语言设置
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            updateBundle()
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }
    
    init() {
        // 从UserDefaults中加载保存的语言设置，默认为跟随系统
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        currentLanguage = AppLanguage(rawValue: savedLanguage) ?? .system
        updateBundle()
    }
    
    // 切换到指定语言
    func setLanguage(_ language: AppLanguage) {
        if currentLanguage != language {
            currentLanguage = language
        }
    }
    
    // 更新使用的Bundle
    private func updateBundle() {
        let languageCode = currentLanguage.languageCode
        print("正在更新语言Bundle为: \(languageCode)")
        
        // 获取应用主Bundle
        guard let bundlePath = Bundle.main.path(forResource: languageCode, ofType: "lproj") else {
            print("无法找到语言资源: \(languageCode).lproj")
            currentBundle = Bundle.main
            return
        }
        
        currentBundle = Bundle(path: bundlePath)
        print("成功加载语言Bundle: \(languageCode)")
    }
    
    // 获取当前语言的本地化字符串
    func localizedString(for key: String, defaultValue: String? = nil) -> String {
        // 使用当前语言Bundle获取本地化字符串
        var localizedString = NSLocalizedString(key, tableName: nil, bundle: currentBundle ?? Bundle.main, value: key, comment: "")
        
        // 如果返回的是键名本身（即没有找到本地化版本），使用默认值
        if localizedString == key && defaultValue != nil {
            localizedString = defaultValue!
        }
        
        return localizedString
    }
}

// 通知名称扩展
extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

// String扩展，方便本地化
extension String {
    var localized: String {
        return LanguageManager.shared.localizedString(for: self, defaultValue: self)
    }
    
    // 带参数的本地化函数
    func localized(with arguments: CVarArg...) -> String {
        let localizedFormat = LanguageManager.shared.localizedString(for: self, defaultValue: self)
        return String(format: localizedFormat, arguments: arguments)
    }
} 