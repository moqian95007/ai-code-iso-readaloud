import Foundation

// 用户默认项键管理结构体，统一管理所有UserDefaults键
struct UserDefaultsKeys {
    // 全局设置键
    static let fontSize = "fontSize"
    static let fontSizeOption = "fontSizeOption"
    static let isDarkMode = "isDarkMode"
    static let selectedRate = "selectedRate"
    static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
    static let selectedVoiceName = "selectedVoiceName"
    static let lastPlayedArticleId = "lastPlayedArticleId"
    
    // 播放模式
    static let playbackMode = "playbackMode"
    
    // 列表循环跳转标记
    static let isFromListRepeat = "isFromListRepeat"
    
    // 为每篇文章创建唯一的键
    static func lastPlaybackPosition(for articleId: UUID) -> String {
        return "lastPlaybackPosition_\(articleId.uuidString)"
    }
    
    static func lastProgress(for articleId: UUID) -> String {
        return "lastProgress_\(articleId.uuidString)"
    }
    
    static func lastPlaybackTime(for articleId: UUID) -> String {
        return "lastPlaybackTime_\(articleId.uuidString)"
    }
    
    static func wasPlaying(for articleId: UUID) -> String {
        return "wasPlaying_\(articleId.uuidString)"
    }
    
    static func lastPlayTime(for articleId: UUID) -> String {
        return "lastPlayTime_\(articleId.uuidString)"
    }
    
    static let lastPlayedArticles = "lastPlayedArticles"
} 