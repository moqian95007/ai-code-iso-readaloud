import Foundation

/// 用户设置模型，用于存储和同步用户设置
struct UserSettings: Codable {
    // 显示设置
    var fontSize: CGFloat
    var fontSizeOption: String
    var isDarkMode: Bool
    
    // 朗读设置
    var selectedRate: Float
    var selectedVoiceIdentifier: String?
    var selectedVoiceName: String?
    
    // 播放设置
    var playbackMode: String
    var timerOption: String
    var customTimerMinutes: Int
    
    // 初始化方法 - 从UserDefaults创建
    init() {
        // 从UserDefaults读取设置
        self.fontSize = UserDefaults.standard.object(forKey: UserDefaultsKeys.fontSize) as? CGFloat ?? 18.0
        self.fontSizeOption = UserDefaults.standard.string(forKey: UserDefaultsKeys.fontSizeOption) ?? FontSizeOption.medium.rawValue
        self.isDarkMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isDarkMode)
        self.selectedRate = UserDefaults.standard.float(forKey: UserDefaultsKeys.selectedRate)
        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedVoiceIdentifier)
        self.selectedVoiceName = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedVoiceName)
        self.playbackMode = UserDefaults.standard.string(forKey: UserDefaultsKeys.playbackMode) ?? PlaybackMode.singlePlay.rawValue
        self.timerOption = UserDefaults.standard.string(forKey: UserDefaultsKeys.timerOption) ?? "off"
        self.customTimerMinutes = UserDefaults.standard.integer(forKey: UserDefaultsKeys.customTimerMinutes)
    }
    
    // 应用设置到UserDefaults
    func applyToUserDefaults() {
        UserDefaults.standard.set(fontSize, forKey: UserDefaultsKeys.fontSize)
        UserDefaults.standard.set(fontSizeOption, forKey: UserDefaultsKeys.fontSizeOption)
        UserDefaults.standard.set(isDarkMode, forKey: UserDefaultsKeys.isDarkMode)
        UserDefaults.standard.set(selectedRate, forKey: UserDefaultsKeys.selectedRate)
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: UserDefaultsKeys.selectedVoiceIdentifier)
        UserDefaults.standard.set(selectedVoiceName, forKey: UserDefaultsKeys.selectedVoiceName)
        UserDefaults.standard.set(playbackMode, forKey: UserDefaultsKeys.playbackMode)
        UserDefaults.standard.set(timerOption, forKey: UserDefaultsKeys.timerOption)
        UserDefaults.standard.set(customTimerMinutes, forKey: UserDefaultsKeys.customTimerMinutes)
        
        // 发送通知，告知设置已更新
        NotificationCenter.default.post(name: NSNotification.Name("UserSettingsUpdated"), object: nil)
    }
} 