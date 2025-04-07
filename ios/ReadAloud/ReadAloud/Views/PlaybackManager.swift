import SwiftUI
import Combine

/// 内容类型枚举，用于区分不同的播放内容类型
enum PlaybackContentType: String, Codable {
    case article
    case document
    case none
}

/// 全局播放状态管理器
/// 负责管理整个应用的播放状态，确保同一时间只有一个内容在播放
class PlaybackManager: ObservableObject {
    // 单例模式
    static let shared = PlaybackManager()
    
    // 当前播放状态
    @Published var isPlaying: Bool = false {
        didSet {
            if oldValue != isPlaying {
                notifyPlaybackStateChanged()
            }
        }
    }
    
    // 当前播放的内容类型
    @Published var contentType: PlaybackContentType = .none {
        didSet {
            savePlaybackState()
        }
    }
    
    // 当前播放的内容ID
    @Published var currentContentId: UUID? {
        didSet {
            savePlaybackState()
        }
    }
    
    // 当前播放的内容标题
    @Published var currentTitle: String = "" {
        didSet {
            savePlaybackState()
        }
    }
    
    // 通知名称
    static let playbackStateChangedNotification = Notification.Name("PlaybackStateChanged")
    
    // 私有初始化方法，不再依赖于 SpeechManager
    private init() {
        // 加载保存的播放状态
        loadPlaybackState()
        
        // 添加通知监听，而不是直接订阅属性
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChanged),
            name: Notification.Name("SpeechManagerPlaybackStateChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartPlaybackRequest),
            name: Notification.Name("StartPlaybackRequest"),
            object: nil
        )
    }
    
    @objc private func handlePlaybackStateChanged(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let isPlaying = userInfo["isPlaying"] as? Bool {
            // 在主线程更新UI状态
            DispatchQueue.main.async {
                self.isPlaying = isPlaying
            }
        }
    }
    
    @objc private func handleStartPlaybackRequest(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let contentId = userInfo["contentId"] as? UUID,
           let title = userInfo["title"] as? String,
           let contentTypeString = userInfo["contentType"] as? String {
            
            let type = contentTypeString == "document" ? PlaybackContentType.document : PlaybackContentType.article
            
            // 更新状态
            DispatchQueue.main.async {
                self.currentContentId = contentId
                self.currentTitle = title
                self.contentType = type
                self.isPlaying = true
                self.savePlaybackState()
            }
        }
    }
    
    // 开始播放
    func startPlayback(contentId: UUID, title: String, type: PlaybackContentType) {
        // 如果当前有其他内容在播放，先停止它
        if isPlaying && currentContentId != contentId {
            stopPlayback()
        }
        
        // 更新当前播放内容信息
        currentContentId = contentId
        currentTitle = title
        contentType = type
        
        // 发送通知
        notifyPlaybackStateChanged()
        
        // 保存状态
        savePlaybackState()
    }
    
    // 暂停播放 - 只通过通知来控制 SpeechManager
    func pausePlayback() {
        NotificationCenter.default.post(
            name: Notification.Name("PausePlaybackRequest"),
            object: nil
        )
    }
    
    // 停止播放 - 只通过通知来控制 SpeechManager
    func stopPlayback() {
        NotificationCenter.default.post(
            name: Notification.Name("StopPlaybackRequest"),
            object: nil
        )
    }
    
    // 恢复播放
    func resumePlayback() -> Bool {
        if isPlaying {
            return true // 已经在播放中
        }
        
        guard let contentId = currentContentId, !currentTitle.isEmpty else {
            return false // 没有可恢复的内容
        }
        
        // 根据内容类型恢复播放
        switch contentType {
        case .article:
            // 发送打开文章的通知
            let userInfo: [String: Any] = [
                "articleId": contentId,
                "useLastPlaylist": true
            ]
            
            NotificationCenter.default.post(
                name: Notification.Name("OpenArticle"),
                object: nil,
                userInfo: userInfo
            )
            return true
            
        case .document:
            // 发送打开文档的通知
            let userInfo: [String: Any] = [
                "documentId": contentId
            ]
            
            NotificationCenter.default.post(
                name: Notification.Name("OpenDocument"),
                object: nil,
                userInfo: userInfo
            )
            return true
            
        case .none:
            return false
        }
    }
    
    // 检查是否正在播放指定内容
    func isPlayingContent(id: UUID) -> Bool {
        return isPlaying && currentContentId == id
    }
    
    // 获取当前播放内容的信息
    func getCurrentPlaybackInfo() -> (id: UUID?, title: String, type: PlaybackContentType) {
        return (currentContentId, currentTitle, contentType)
    }
    
    // 保存播放状态
    private func savePlaybackState() {
        let userDefaults = UserDefaults.standard
        
        // 保存内容ID
        if let contentId = currentContentId {
            userDefaults.set(contentId.uuidString, forKey: "global_playback_content_id")
        } else {
            userDefaults.removeObject(forKey: "global_playback_content_id")
        }
        
        // 保存标题
        userDefaults.set(currentTitle, forKey: "global_playback_title")
        
        // 保存内容类型
        userDefaults.set(contentType.rawValue, forKey: "global_playback_content_type")
    }
    
    // 加载播放状态
    private func loadPlaybackState() {
        let userDefaults = UserDefaults.standard
        
        // 加载内容ID
        if let contentIdString = userDefaults.string(forKey: "global_playback_content_id"),
           let contentId = UUID(uuidString: contentIdString) {
            currentContentId = contentId
        }
        
        // 加载标题
        currentTitle = userDefaults.string(forKey: "global_playback_title") ?? ""
        
        // 加载内容类型
        if let typeString = userDefaults.string(forKey: "global_playback_content_type"),
           let type = PlaybackContentType(rawValue: typeString) {
            contentType = type
        }
    }
    
    // 发送播放状态变更通知
    private func notifyPlaybackStateChanged() {
        let userInfo: [String: Any] = [
            "isPlaying": isPlaying,
            "contentType": contentType.rawValue,
            "contentId": currentContentId?.uuidString ?? "",
            "title": currentTitle
        ]
        
        NotificationCenter.default.post(
            name: PlaybackManager.playbackStateChangedNotification,
            object: self,
            userInfo: userInfo
        )
    }
} 