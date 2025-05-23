import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

/// 播放模式枚举
enum PlaybackMode: String, CaseIterable {
    case singlePlay = "single_play"  // 播放完当前文章后停止
    case singleRepeat = "single_repeat"  // 循环播放当前文章
    case listRepeat = "list_repeat"  // 循环播放列表中的文章
    
    var iconName: String {
        switch self {
        case .singlePlay:
            return "play.circle"
        case .singleRepeat:
            return "repeat.1"
        case .listRepeat:
            return "repeat"
        }
    }
}

// 引入 Views/PlaybackManager.swift 中定义的类型
// PlaybackContentType 和 PlaybackManager 在 Views/PlaybackManager.swift 中定义

/// 管理语音合成和朗读的类
class SpeechManager: ObservableObject {
    // 共享实例
    static let shared = SpeechManager()
    
    // 语音合成器和代理
    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate.shared
    
    // 当前朗读状态
    @Published var isPlaying = false
    @Published var currentProgress: Double = 0.0
    @Published var currentTime: TimeInterval = 0.0
    @Published var totalTime: TimeInterval = 0.0
    @Published var currentPlaybackPosition: Int = 0
    @Published var isResuming: Bool = false
    @Published var isDragging: Bool = false
    
    // 播放模式
    @Published var playbackMode: PlaybackMode = .listRepeat
    
    // 上一次播放的文章列表
    @Published var lastPlayedArticles: [Article] = []
    
    // 当前语音设置
    @Published var selectedRate: Double = UserDefaults.standard.object(forKey: UserDefaultsKeys.selectedRate) as? Double ?? 1.0
    @Published var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedVoiceIdentifier) ?? ""
    
    // 音频处理进度 (新增)
    @Published var audioProcessingProgress: Double = 0.0
    
    // 当前文章
    private var currentArticle: Article?
    private var currentText: String = ""
    
    // 全局播放管理器 - 使用延迟加载避免循环依赖
    private lazy var playbackManager: PlaybackManager = {
        return PlaybackManager.shared
    }()
    
    // 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // 为SpeechDelegate提供访问当前文本的方法
    var currentTextCount: Int {
        return currentText.count
    }
    
    // 提供获取当前文本的方法
    func getCurrentText() -> String {
        return currentText
    }
    
    // 检查指定ID的文章是否正在播放
    func isArticlePlaying(articleId: UUID) -> Bool {
        print("检查文章ID: \(articleId) 是否在播放")
        
        // 获取合成器的实际播放状态，考虑暂停状态
        let isSynthesizerSpeaking = getSpeakingState()
        print("合成器实际播放状态: \(isSynthesizerSpeaking)")
        
        // 如果合成器不在朗读，快速返回false
        if !isSynthesizerSpeaking {
            print("合成器未在朗读，返回false")
            return false
        }
        
        // 检查是否有当前文章
        guard let currentArticle = currentArticle else {
            print("当前没有活跃的文章，返回false")
            return false
        }
        
        // 1. 首先检查UUID是否精确匹配
        let isIdMatched = currentArticle.id == articleId
        
        // 2. 检查是否是文档ID匹配（Document.id 与 Article.listId 匹配）
        let isDocumentMatched = currentArticle.listId == articleId
        if isDocumentMatched {
            print("文档ID匹配成功: 当前文章的listId与检查ID匹配")
            return true
        }
        
        // 3. 如果ID不匹配，尝试通过章节号匹配
        var isChapterMatched = false
        
        // 提取章节编号的匹配模式，如 "第13章"
        let titlePattern = "第(\\d+)章"
        
        // 从当前播放中的文章标题中提取章节号
        if let currentTitleMatch = currentArticle.title.range(of: titlePattern, options: .regularExpression) {
            let currentTitleStr = currentArticle.title
            let currentStartIndex = currentTitleStr.index(after: currentTitleMatch.lowerBound) // 跳过"第"字
            let currentEndIndex = currentTitleStr.firstIndex(of: "章") ?? currentTitleStr.endIndex
            
            if currentStartIndex < currentEndIndex {
                let currentChapterNumStr = String(currentTitleStr[currentStartIndex..<currentEndIndex])
                
                // 从文档库中寻找匹配的文章标题
                for article in lastPlayedArticles {
                    if article.id == articleId && article.title.contains("章") {
                        if let articleTitleMatch = article.title.range(of: titlePattern, options: .regularExpression) {
                            let articleTitleStr = article.title
                            let articleStartIndex = articleTitleStr.index(after: articleTitleMatch.lowerBound)
                            let articleEndIndex = articleTitleStr.firstIndex(of: "章") ?? articleTitleStr.endIndex
                            
                            if articleStartIndex < articleEndIndex {
                                let articleChapterNumStr = String(articleTitleStr[articleStartIndex..<articleEndIndex])
                                
                                // 比较章节号
                                if currentChapterNumStr == articleChapterNumStr {
                                    isChapterMatched = true
                                    print("章节号匹配成功: 当前章节号\(currentChapterNumStr) = 检查章节号\(articleChapterNumStr)")
                                    break
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("当前文章ID: \(currentArticle.id), 检查ID: \(articleId), ID匹配: \(isIdMatched), 文档匹配: \(isDocumentMatched), 章节匹配: \(isChapterMatched), 合成器状态: \(isSynthesizerSpeaking)")
        
        // 返回是否在播放这篇文章（ID匹配、文档匹配或章节匹配）
        return (isIdMatched || isDocumentMatched || isChapterMatched) && isSynthesizerSpeaking
    }
    
    // 计时器
    private var timer: Timer?
    
    // 防止重复触发下一篇播放的标志
    private var isProcessingNextArticle: Bool = false
    
    // 实例变量，用于跟踪上次开始朗读的时间
    private var lastStartTime: Date = Date(timeIntervalSince1970: 0)
    
    // 实例变量，用于跟踪上次跳转的时间
    private var lastSkipTime: Date = Date(timeIntervalSince1970: 0)
    
    // 当前音频文件URL
    private var currentAudioFileURL: URL?
    
    // 是否正在处理音频文件
    @Published var isProcessingAudio: Bool = false
    
    // 是否在处理完成后停止播放
    private var shouldStopAfterProcessing: Bool = false
    
    private init() {
        // 不再需要设置合成器代理
        // synthesizer.delegate = speechDelegate
        
        // 配置音频会话
        setupAudioSession()
        
        // 加载保存的播放模式
        if let savedMode = UserDefaults.standard.string(forKey: UserDefaultsKeys.playbackMode),
           let mode = PlaybackMode(rawValue: savedMode) {
            playbackMode = mode
        }
        
        // 加载上次播放的文章列表
        loadLastPlayedArticles()
        
        // 监听朗读状态变化
        setupSpeechDelegateObserver()
        
        // 延迟设置PlaybackManager观察者，避免初始化时的循环依赖
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupPlaybackManagerObserver()
        }
        
        // 监听用户登录后的数据重载通知
        NotificationCenter.default.publisher(for: Notification.Name("ReloadArticlesData"))
            .sink { [weak self] _ in
                print("SpeechManager收到ReloadArticlesData通知，重新加载上次播放列表")
                self?.loadLastPlayedArticles()
            }
            .store(in: &cancellables)
            
        // 监听AudioFileManager的生成进度
        setupAudioProgressObserver()
    }
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            
            // 注册远程控制事件
            setupRemoteTransportControls()
        } catch {
            print("设置音频会话失败: \(error.localizedDescription)")
        }
    }
    
    // 设置远程控制
    private func setupRemoteTransportControls() {
        // 获取远程控制中心
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 添加播放/暂停处理
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, !self.isPlaying else { return .success }
            
            if self.isResuming {
                self.startSpeakingFromPosition(self.currentPlaybackPosition)
            } else {
                self.startSpeaking()
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, self.isPlaying else { return .success }
            self.pauseSpeaking(updateGlobalState: false)
            return .success
        }
        
        // 添加前进/后退处理
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self,
                  let skipEvent = event as? MPSkipIntervalCommandEvent else { return .success }
            self.skipForward(seconds: skipEvent.interval)
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self,
                  let skipEvent = event as? MPSkipIntervalCommandEvent else { return .success }
            self.skipBackward(seconds: skipEvent.interval)
            return .success
        }
    }
    
    // 设置朗读状态监听器
    private func setupSpeechDelegateObserver() {
        // 监听朗读完成事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpeechFinished),
            name: NSNotification.Name("SpeechFinished"),
            object: nil
        )
    }
    
    // 设置PlaybackManager监听器
    private func setupPlaybackManagerObserver() {
        // 监听全局播放管理器的状态变化
        playbackManager.$isPlaying
            .sink { [weak self] isPlaying in
                // 如果全局播放状态变为已停止，但本地状态仍为播放中，则停止本地播放
                guard let self = self else { return }
                
                if !isPlaying && self.isPlaying {
                    // 防止循环调用：只有当状态不一致时才调用暂停
                    DispatchQueue.main.async {
                        self.pauseSpeaking(updateGlobalState: false)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // 设置音频处理进度观察器
    private func setupAudioProgressObserver() {
        // 每隔100毫秒检查一次进度
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 只有正在处理音频时才更新进度
            if self.isProcessingAudio {
                let progress = Double(AudioFileManager.shared.generationProgress)
                
                // 只有当进度有明显变化时才更新UI
                if abs(self.audioProcessingProgress - progress) > 0.01 {
                    self.audioProcessingProgress = progress
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // 处理朗读完成事件
    @objc private func handleSpeechFinished() {
        print("========= 朗读完成事件触发 =========")
        print("当前模式: \(playbackMode.rawValue)")
        print("isPlaying: \(isPlaying), isResuming: \(isResuming)")
        print("手动暂停标志: \(speechDelegate.wasManuallyPaused)")
        print("接近文章末尾标志: \(speechDelegate.isNearArticleEnd)")
        print("起始位置: \(speechDelegate.startPosition)")
        print("正在处理下一篇文章: \(isProcessingNextArticle)")
        
        // 如果已在处理下一篇文章请求，跳过当前处理
        if isProcessingNextArticle {
            print("已在处理下一篇文章请求，跳过当前事件处理")
            return
        }
        
        // 此时synthesizer已经停止朗读，但我们需要确定是自然结束还是手动暂停
        // 手动暂停时会设置isResuming=true，isPlaying=false，同时wasManuallyPaused=true
        let isUserPaused = isResuming && !isPlaying && speechDelegate.wasManuallyPaused && !speechDelegate.isNearArticleEnd
        
        // 检查是否是从中间位置开始的播放
        let isStartedFromMiddle = speechDelegate.startPosition > 0
        
        if isUserPaused {
            print("检测到是用户手动暂停，不执行自动播放")
            return
        }
        
        // 如果来到这里，要么是自然播放结束，要么是接近文章末尾的特殊情况
        print("检测到自然播放结束或接近文章末尾特殊情况，准备处理后续播放")
        
        // 检查定时关闭选项 - 播完本章后停止
        let timerManager = TimerManager.shared
        if timerManager.isTimerActive && timerManager.selectedOption == .afterChapter {
            print("检测到[播完本章后停止]定时选项，停止播放")
            
            // 重置所有状态
            isResuming = false
            currentPlaybackPosition = 0
            currentProgress = 0.0
            currentTime = 0.0
            isPlaying = false
            
            // 清除保存的播放进度
            if let articleId = currentArticle?.id {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress(for: articleId))
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            }
            
            // 取消定时器
            timerManager.cancelTimer()
            
            // 发送定时器完成通知
            NotificationCenter.default.post(name: Notification.Name("TimerCompleted"), object: nil)
            
            // 更新UI
            updateNowPlayingInfo()
            return
        }
        
        // 处理从中间位置开始播放且完成的情况
        if isStartedFromMiddle && !speechDelegate.wasManuallyPaused {
            print("从中间位置开始的播放已完成，直接跳到下一篇或重置")
            // 标记为已处理，防止在切换到下一篇时重复触发
            speechDelegate.wasManuallyPaused = true
            
            if playbackMode == .listRepeat {
                print("列表循环模式下从中间位置完成播放，准备播放下一篇")
                // 确保进度条显示为100%
                currentProgress = 1.0
                currentTime = totalTime
                
                // 设置标志防止重复处理
                isProcessingNextArticle = true
                
                // 重置起始位置为0，避免下一篇文章从中间开始
                speechDelegate.startPosition = 0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.playNextArticle()
                    // 延迟重置标志，确保通知已被处理
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isProcessingNextArticle = false
                    }
                }
                return
            } else if playbackMode == .singleRepeat {
                print("单篇循环模式下从中间位置完成播放，准备从头开始")
                // 临时设置进度为100%，显示朗读完成
                currentProgress = 1.0
                currentTime = totalTime
                
                // 重置起始位置为0
                speechDelegate.startPosition = 0
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // 确保重置所有状态，以便从头开始播放
                    self.isResuming = false
                    self.currentPlaybackPosition = 0
                    self.currentProgress = 0.0
                    self.currentTime = 0.0
                    self.speechDelegate.startPosition = 0
                    self.speechDelegate.wasManuallyPaused = false
                    
                    print("开始单篇循环播放")
                    self.startSpeaking()
                }
                return
            }
        }
        
        print("检测到是自然播放结束，准备根据播放模式执行相应操作")
        
        // 确保进度条显示为100%
        if !isUserPaused {
            currentProgress = 1.0
            currentTime = totalTime
        }
        
        // 根据不同播放模式执行相应操作
        switch playbackMode {
        case .singlePlay:
            print("单篇播放模式: 播放结束后重置进度并更新UI")
            // 重置所有状态
            isResuming = false
            currentPlaybackPosition = 0
            currentProgress = 0.0
            currentTime = 0.0
            isPlaying = false
            
            // 清除保存的播放进度
            if let articleId = currentArticle?.id {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress(for: articleId))
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            }
            
            // 更新UI
            updateNowPlayingInfo()
            break
            
        case .singleRepeat:
            print("单篇循环模式: 准备重新开始播放当前文章")
            
            // 重置起始位置为0
            speechDelegate.startPosition = 0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 确保重置所有状态，以便从头开始播放
                self.isResuming = false
                self.currentPlaybackPosition = 0
                self.currentProgress = 0.0
                self.currentTime = 0.0
                self.speechDelegate.wasManuallyPaused = false
                self.speechDelegate.startPosition = 0
                
                print("开始单篇循环播放")
                self.startSpeaking()
            }
            
        case .listRepeat:
            print("列表循环模式: 准备播放下一篇文章")
            
            // 重置起始位置为0，避免下一篇文章从中间开始
            speechDelegate.startPosition = 0
            
            // 特殊处理：防止由于多次触发导致的重复播放
            if !isProcessingNextArticle {
                isProcessingNextArticle = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.playNextArticle()
                    // 延迟重置标志，确保通知已被处理
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isProcessingNextArticle = false
                    }
                }
            } else {
                print("已在处理下一篇文章请求，忽略重复触发")
            }
        }
        
        print("=====================================")
    }
    
    // 播放列表中的下一篇文章
    func playNextArticle() {
        print("========= 准备播放下一篇文章 =========")
        
        guard let currentArticle = currentArticle,
              !lastPlayedArticles.isEmpty else {
            print("没有当前文章或文章列表为空，无法播放下一篇")
            return
        }
        
        print("当前文章: \(currentArticle.title), ID: \(currentArticle.id)")
        
        // 查找当前文章在列表中的索引
        guard let index = lastPlayedArticles.firstIndex(where: { $0.id == currentArticle.id }) else {
            print("当前文章不在播放列表中，尝试查找同名文章")
            
            // 尝试匹配标题
            if let indexByTitle = lastPlayedArticles.firstIndex(where: { $0.title == currentArticle.title }) {
                let nextIndex = (indexByTitle + 1) % lastPlayedArticles.count
                let nextArticle = lastPlayedArticles[nextIndex]
                
                print("根据标题匹配找到下一篇文章: \(nextArticle.title), ID: \(nextArticle.id)")
                startSpeaking(article: nextArticle)
                return
            } else {
                print("无法在列表中找到当前文章，从列表第一篇开始")
                if let firstArticle = lastPlayedArticles.first {
                    startSpeaking(article: firstArticle)
                }
                return
            }
        }
        
        // 获取下一篇文章（如果已是最后一篇，则返回第一篇）
        let nextIndex = (index + 1) % lastPlayedArticles.count
        let nextArticle = lastPlayedArticles[nextIndex]
        
        print("下一篇文章: \(nextArticle.title), ID: \(nextArticle.id)")
        
        // 开始播放下一篇文章
        startSpeaking(article: nextArticle)
        
        print("=====================================")
    }
    
    // 跳转到上一篇文章
    func playPreviousArticle() {
        print("========= 准备播放上一篇文章 =========")
        
        guard let currentArticle = currentArticle,
              !lastPlayedArticles.isEmpty else {
            print("没有当前文章或文章列表为空，无法播放上一篇")
            return
        }
        
        print("当前文章: \(currentArticle.title), ID: \(currentArticle.id)")
        
        // 查找当前文章在列表中的索引
        guard let index = lastPlayedArticles.firstIndex(where: { $0.id == currentArticle.id }) else {
            print("当前文章不在播放列表中，尝试查找同名文章")
            
            // 尝试匹配标题
            if let indexByTitle = lastPlayedArticles.firstIndex(where: { $0.title == currentArticle.title }) {
                let prevIndex = (indexByTitle - 1 + lastPlayedArticles.count) % lastPlayedArticles.count
                let prevArticle = lastPlayedArticles[prevIndex]
                
                print("根据标题匹配找到上一篇文章: \(prevArticle.title), ID: \(prevArticle.id)")
                startSpeaking(article: prevArticle)
                return
            } else {
                print("无法在列表中找到当前文章，从列表最后一篇开始")
                if let lastArticle = lastPlayedArticles.last {
                    startSpeaking(article: lastArticle)
                }
                return
            }
        }
        
        // 获取上一篇文章（如果已是第一篇，则返回最后一篇）
        let prevIndex = (index - 1 + lastPlayedArticles.count) % lastPlayedArticles.count
        let prevArticle = lastPlayedArticles[prevIndex]
        
        print("上一篇文章: \(prevArticle.title), ID: \(prevArticle.id)")
        
        // 开始播放上一篇文章
        startSpeaking(article: prevArticle)
        
        print("=====================================")
    }
    
    // 核心功能：从指定位置开始播放文章
    func startSpeakingFromPosition(_ position: Int) {
        print("========= 从位置\(position)开始朗读 =========")
        
        // 如果当前文章为空，使用全局管理器的当前文章
        if currentText.isEmpty {
            print("没有要朗读的文本，中止操作")
            return
        }
        
        var text = currentText
        
        // 安全检查: 确保位置有效
        let safePosition = min(max(0, position), text.count - 1)
        print("安全位置: \(safePosition)")
        
        // 如果位置为0，从头开始；否则从指定位置开始
        if safePosition > 0 {
            // 从指定位置截取文本
            let startIndex = text.index(text.startIndex, offsetBy: safePosition)
            text = String(text[startIndex...])
            print("截取后的文本长度: \(text.count)")
        }
        
        // 记录位置以便恢复
        if safePosition > 0 {
            print("设置恢复标志")
            isResuming = true
            currentPlaybackPosition = safePosition
            
            // 保存当前播放位置，用于下次启动时恢复
            if let articleId = currentArticle?.id {
                UserDefaults.standard.set(safePosition, forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
                UserDefaults.standard.set(true, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
                UserDefaults.standard.set(currentProgress, forKey: UserDefaultsKeys.lastProgress(for: articleId))
                UserDefaults.standard.set(currentTime, forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
            }
        } else {
            isResuming = false
            currentPlaybackPosition = 0
        }
        
        // 生成并播放音频文件
        generateAndPlayAudio(text: text, position: safePosition)
    }
    
    // 开始朗读指定文章
    func startSpeaking(article: Article? = nil) {
        // 记录开始时间
        lastStartTime = Date()
        
        // 如果没有提供文章，使用当前文章；如果当前也没有，返回
        var articleToRead = article
        if articleToRead == nil {
            articleToRead = currentArticle
            
            if articleToRead == nil {
                print("没有可朗读的文章，已中止")
                return
            }
        }
        
        // 获取文章文本
        guard let textArticle = articleToRead else {
            print("文章为空，已中止")
            return
        }
        
        if textArticle.content.isEmpty {
            print("文章内容为空，已中止")
            return
        }
        
        let articleText = textArticle.content
        
        // 更新当前文章和文本
        currentArticle = textArticle
        currentText = articleText
        
        // 重置进度
        currentPlaybackPosition = 0
        isResuming = false
        
        // 直接开始朗读，从头开始
        print("准备朗读文章: \(textArticle.title), ID: \(textArticle.id)")
        print("文本长度: \(articleText.count)字符")
        
        // 更新最后播放的文章位置
        if let index = lastPlayedArticles.firstIndex(where: { $0.id == textArticle.id }) {
            // 已在播放列表中，更新顺序（可选）
            // 此处可以考虑是否需要调整列表顺序
        } else if !lastPlayedArticles.isEmpty {
            // 如果不在列表中，但有播放列表，则可能是需要添加到列表
            print("当前文章不在播放列表中，尝试查找相关文章")
            
            // 判断是否是同一文档的不同章节
            if let currentListId = textArticle.listId,
               let firstIndex = lastPlayedArticles.firstIndex(where: { $0.listId == currentListId }) {
                print("找到同一文档的其他章节，使用现有播放列表")
            } else {
                // 完全不相关的文章，可能需要重建播放列表
                print("当前文章与播放列表无关，考虑更新播放列表")
            }
        }
        
        // 生成并播放音频文件
        generateAndPlayAudio(text: articleText, position: 0)
    }
    
    // 暂停朗读
    func pauseSpeaking(updateGlobalState: Bool = true) {
        print("========= 暂停朗读 =========")
        print("isPlaying: \(isPlaying), isResuming: \(isResuming)")
        
        // 如果不在播放，直接返回
        guard isPlaying else {
            print("当前没有朗读正在进行，忽略暂停请求")
            return
        }
        
        // 暂停AudioFileManager的播放
        AudioFileManager.shared.pausePlayback()
        
        // 更新状态
        isPlaying = false
        isResuming = true
        
        // 停止计时器
        stopTimer()
        
        // 保存播放进度
        savePlaybackProgress()
        
        // 更新锁屏界面信息
        updateNowPlayingInfo()
        
        // 同步全局状态
        if updateGlobalState && playbackManager.isPlaying {
            playbackManager.pausePlayback()
        }
        
        print("暂停成功，当前进度: \(currentProgress), 时间: \(currentTime)秒")
        print("=====================================")
    }
    
    // 继续朗读
    func resumeSpeaking() {
        print("========= 继续朗读 =========")
        
        // 如果已在播放，直接返回
        guard !isPlaying else {
            print("已经在朗读中，忽略继续请求")
            return
        }
        
        // 如果有正在暂停的音频播放，恢复播放
        if AudioFileManager.shared.audioPlayer != nil {
            print("发现暂停的音频播放，恢复播放")
            AudioFileManager.shared.resumePlayback()
            isPlaying = true
            startTimer()
            
            // 更新锁屏界面信息
            updateNowPlayingInfo()
            
            // 更新全局状态
            if !playbackManager.isPlaying {
                if let articleId = currentArticle?.id {
                    let contentType: PlaybackContentType = articleId.description.hasPrefix("doc-") ? .document : .article
                    playbackManager.startPlayback(
                        contentId: articleId,
                        title: currentArticle?.title ?? "未知文章",
                        type: contentType
                    )
                }
            }
            
            return
        }
        
        // 如果有恢复标记和位置，从上次位置开始
        if isResuming && currentPlaybackPosition > 0 {
            print("从上次位置 \(currentPlaybackPosition) 继续朗读")
            startSpeakingFromPosition(currentPlaybackPosition)
        } else {
            // 否则从头开始
            print("没有恢复信息，从头开始朗读")
            startSpeaking()
        }
        
        print("=====================================")
    }
    
    // 停止朗读
    func stopSpeaking(resetResumeState: Bool = false) {
        print("========= 停止朗读 =========")
        
        // 停止音频播放
        AudioFileManager.shared.stopPlayback()
        
        // 停止计时器
        stopTimer()
        
        // 更新状态
        isPlaying = false
        if resetResumeState {
            isResuming = false
            currentPlaybackPosition = 0
            currentProgress = 0.0
            currentTime = 0.0
        }
        
        // 更新锁屏界面信息
        updateNowPlayingInfo()
        
        // 同步全局状态
        if playbackManager.isPlaying {
            playbackManager.stopPlayback()
        }
        
        print("朗读已停止，resetResumeState: \(resetResumeState)")
        print("=====================================")
    }
    
    // 生成并播放音频文件
    private func generateAndPlayAudio(text: String, position: Int) {
        // 设置处理状态
        isProcessingAudio = true
        audioProcessingProgress = 0.0
        
        // 获取当前文章ID作为唯一标识符
        let uniqueID = currentArticle?.id.uuidString ?? UUID().uuidString
        
        // 获取当前选择的语音
        let selectedVoice = getSelectedVoice()
        
        // 设置朗读速率
        let actualRate = Float(selectedRate) * 0.4
        
        print("开始生成音频文件...")
        print("语音ID: \(selectedVoiceIdentifier)")
        print("语音名称: \(selectedVoice?.name ?? "默认")")
        print("朗读速率: \(actualRate)")
        
        // 生成音频文件
        AudioFileManager.shared.generateAudioFile(
            from: text,
            voice: selectedVoice,
            rate: actualRate,
            uniqueID: uniqueID
        ) { [weak self] fileURL in
            guard let self = self else { return }
            
            // 重置处理状态
            self.isProcessingAudio = false
            self.audioProcessingProgress = 1.0
            
            if let url = fileURL {
                print("音频文件生成成功: \(url.path)")
                
                // 保存当前音频文件URL
                self.currentAudioFileURL = url
                
                // 更新总时长（估计值）
                self.totalTime = Double(text.count) / 15.0  // 粗略估计：每秒15个字符
                
                // 更新朗读状态
                self.isPlaying = true
                
                // 更新锁屏界面信息
                self.updateNowPlayingInfo()
                
                // 更新全局状态
                if !self.playbackManager.isPlaying {
                    if let articleId = self.currentArticle?.id {
                        let contentType: PlaybackContentType = articleId.description.hasPrefix("doc-") ? .document : .article
                        self.playbackManager.startPlayback(
                            contentId: articleId,
                            title: self.currentArticle?.title ?? "未知文章",
                            type: contentType
                        )
                    }
                }
                
                // 播放音频文件
                AudioFileManager.shared.playAudioFile(url: url) {
                    // 播放完成后的处理
                    print("音频文件播放完成")
                    self.handlePlaybackFinished()
                }
                
                // 开始计时器更新进度
                self.startTimer()
                
            } else {
                print("音频文件生成失败")
                self.isPlaying = false
                
                // 通知用户生成失败
                NotificationCenter.default.post(
                    name: Notification.Name("AudioGenerationFailed"),
                    object: nil
                )
            }
        }
    }
    
    // 开始计时器更新进度
    private func startTimer() {
        stopTimer() // 确保没有多个计时器同时运行
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            
            // AudioFileManager.shared是单例，不需要通过条件绑定
            let audioManager = AudioFileManager.shared
            if audioManager.isPlaying {
                // 使用音频文件的实际进度
                self.currentProgress = Double(audioManager.getProgress())
                self.currentTime = audioManager.getCurrentTime()
                self.totalTime = audioManager.getDuration()
            } else {
                // 没有音频文件信息时的简单递增
                self.currentTime += 0.5
                if self.totalTime > 0 {
                    self.currentProgress = min(self.currentTime / self.totalTime, 1.0)
                }
            }
            
            // 更新锁屏界面信息
            self.updateNowPlayingInfo()
        }
    }
    
    // 停止计时器
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // 处理播放完成
    private func handlePlaybackFinished() {
        print("=========处理播放完成=========")
        
        // 停止计时器
        stopTimer()
        
        // 更新状态
        isPlaying = false
        
        // 保存播放进度（标记为已完成）
        if let articleId = currentArticle?.id {
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress(for: articleId))
        }
        
        // 更新UI
        currentProgress = 1.0
        currentTime = totalTime
        self.objectWillChange.send()
        
        // 更新锁屏界面信息
        updateNowPlayingInfo()
        
        // 根据播放模式处理后续操作
        switch playbackMode {
        case .singlePlay:
            // 单次播放模式，重置所有状态
            isResuming = false
            currentPlaybackPosition = 0
            currentProgress = 0.0
            currentTime = 0.0
            
        case .singleRepeat:
            // 单篇循环模式，从头再次播放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 重置状态并重新播放
                self.isResuming = false
                self.currentPlaybackPosition = 0
                self.currentProgress = 0.0
                self.currentTime = 0.0
                self.startSpeaking()
            }
            
        case .listRepeat:
            // 列表循环模式，播放下一篇
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.playNextArticle()
            }
        }
        
        // 检查定时关闭选项
        let timerManager = TimerManager.shared
        if timerManager.isTimerActive && timerManager.selectedOption == .afterChapter {
            print("定时关闭选项：播完本章后停止")
            
            // 取消定时器
            timerManager.cancelTimer()
            
            // 发送定时器完成通知
            NotificationCenter.default.post(name: Notification.Name("TimerCompleted"), object: nil)
        }
        
        print("=====================================")
    }
    
    // 保存播放进度
    func savePlaybackProgress() {
        guard let articleId = currentArticle?.id else { return }
        
        // 保存当前播放位置
        UserDefaults.standard.set(currentPlaybackPosition, forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
        
        // 保存是否正在播放
        UserDefaults.standard.set(isPlaying, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
        
        // 保存当前进度
        UserDefaults.standard.set(currentProgress, forKey: UserDefaultsKeys.lastProgress(for: articleId))
        
        // 保存当前时间
        UserDefaults.standard.set(currentTime, forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
    }
    
    // 获取选择的语音
    func getSelectedVoice() -> AVSpeechSynthesisVoice? {
        if selectedVoiceIdentifier.isEmpty {
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
        
        // 从系统获取所有可用语音
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // 查找匹配的语音
        for voice in voices {
            if voice.identifier == selectedVoiceIdentifier {
                return voice
            }
        }
        
        // 若没有找到匹配的语音，返回中文语音
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }
    
    // 更新锁屏界面信息
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        
        if let currentArticle = currentArticle {
            // 设置标题
            nowPlayingInfo[MPMediaItemPropertyTitle] = currentArticle.title
            
            // 注释掉author相关代码，因为Article类型没有author成员
            // if let author = currentArticle.author, !author.isEmpty {
            //     nowPlayingInfo[MPMediaItemPropertyArtist] = author
            // }
        }
        
        // 设置持续时间
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = totalTime
        
        // 设置当前播放位置
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // 设置播放速率（1.0表示正常播放，0.0表示暂停）
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 设置封面图像（如果有）
        if let albumArt = UIImage(named: "AppIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: albumArt.size) { _ in
                return albumArt
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        // 更新系统锁屏界面信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // 前进跳过
    func skipForward(seconds: TimeInterval) {
        // 如果距离上次跳转时间不足0.5秒，忽略此次跳转
        let now = Date()
        if now.timeIntervalSince(lastSkipTime) < 0.5 {
            print("忽略频繁的跳转请求")
            return
        }
        lastSkipTime = now
        
        guard isPlaying || isResuming else {
            print("当前没有朗读进行中，无法跳转")
            return
        }
        
        // 如果有音频文件在播放，直接设置其播放位置
        if AudioFileManager.shared.isPlaying {
            let currentPosition = AudioFileManager.shared.getCurrentTime()
            let duration = AudioFileManager.shared.getDuration()
            let newPosition = min(currentPosition + seconds, duration)
            
            // 设置新的播放位置
            AudioFileManager.shared.setPlaybackPosition(newPosition)
            
            // 更新UI状态
            currentTime = newPosition
            if duration > 0 {
                currentProgress = Double(newPosition / duration)
            }
            
            // 更新锁屏界面信息
            updateNowPlayingInfo()
            
            return
        }
        
        // 如果没有音频文件播放但有进度信息，更新进度
        if totalTime > 0 {
            let newTime = min(currentTime + seconds, totalTime)
            currentTime = newTime
            currentProgress = Double(newTime / totalTime)
            
            // 如果有文本内容，计算新的位置
            if !currentText.isEmpty {
                // 估算一个合理的字符位置（每秒约15个字符）
                let charactersPerSecond = 15.0
                let estimatedPosition = Int(currentTime * charactersPerSecond)
                currentPlaybackPosition = min(estimatedPosition, currentText.count - 1)
            }
            
            // 如果当前不在播放中但有恢复标志，更新恢复位置
            if !isPlaying && isResuming {
                // 保存新的恢复位置
                savePlaybackProgress()
            }
            
            // 更新锁屏界面信息
            updateNowPlayingInfo()
        }
    }
    
    // 后退跳过
    func skipBackward(seconds: TimeInterval) {
        // 如果距离上次跳转时间不足0.5秒，忽略此次跳转
        let now = Date()
        if now.timeIntervalSince(lastSkipTime) < 0.5 {
            print("忽略频繁的跳转请求")
            return
        }
        lastSkipTime = now
        
        guard isPlaying || isResuming else {
            print("当前没有朗读进行中，无法跳转")
            return
        }
        
        // 如果有音频文件在播放，直接设置其播放位置
        if AudioFileManager.shared.isPlaying {
            let currentPosition = AudioFileManager.shared.getCurrentTime()
            let newPosition = max(currentPosition - seconds, 0)
            
            // 设置新的播放位置
            AudioFileManager.shared.setPlaybackPosition(newPosition)
            
            // 更新UI状态
            currentTime = newPosition
            let duration = AudioFileManager.shared.getDuration()
            if duration > 0 {
                currentProgress = Double(newPosition / duration)
            }
            
            // 更新锁屏界面信息
            updateNowPlayingInfo()
            
            return
        }
        
        // 如果没有音频文件播放但有进度信息，更新进度
        if totalTime > 0 {
            let newTime = max(currentTime - seconds, 0)
            currentTime = newTime
            currentProgress = Double(newTime / totalTime)
            
            // 如果有文本内容，计算新的位置
            if !currentText.isEmpty {
                // 估算一个合理的字符位置（每秒约15个字符）
                let charactersPerSecond = 15.0
                let estimatedPosition = Int(currentTime * charactersPerSecond)
                currentPlaybackPosition = max(0, min(estimatedPosition, currentText.count - 1))
            }
            
            // 如果当前不在播放中但有恢复标志，更新恢复位置
            if !isPlaying && isResuming {
                // 保存新的恢复位置
                savePlaybackProgress()
            }
            
            // 更新锁屏界面信息
            updateNowPlayingInfo()
        }
    }
    
    // 标记当前文章为已读
    func markCurrentArticleAsRead() {
        guard let articleId = currentArticle?.id else { return }
        
        // 发送通知以标记文章为已读
        NotificationCenter.default.post(
            name: Notification.Name("MarkArticleAsRead"),
            object: nil,
            userInfo: ["articleId": articleId]
        )
    }
    
    // 切换播放模式
    func togglePlaybackMode() {
        switch playbackMode {
        case .singlePlay:
            playbackMode = .singleRepeat
        case .singleRepeat:
            playbackMode = .listRepeat
        case .listRepeat:
            playbackMode = .singlePlay
        }
        
        // 保存设置
        UserDefaults.standard.set(playbackMode.rawValue, forKey: UserDefaultsKeys.playbackMode)
    }
    
    // 为新文章准备语音合成器
    func setup(for article: Article) {
        print("========= SpeechManager.setup =========")
        print("设置文章: \(article.title)")
        print("文章ID: \(article.id.uuidString)")
        print("内容长度: \(article.content.count)")
        
        // 检查是否是文章切换标志
        if speechDelegate.isArticleSwitching {
            print("检测到文章切换标志，确保不会触发自动播放逻辑")
        }
        
        // 检查是否有文章正在播放，如果有强制参数就忽略正在播放的检查
        if isPlaying && currentArticle != nil && currentArticle?.id != article.id {
            print("⚠️ 警告：当前有其他文章正在播放，仅设置界面显示但不修改播放状态")
            print("当前播放文章: \(currentArticle?.title ?? "未知"), ID: \(currentArticle?.id.uuidString ?? "未知")")
            print("要设置的文章: \(article.title), ID: \(article.id.uuidString)")
            
            // 添加设置文章切换标志，防止自动播放下一篇文章
            speechDelegate.isArticleSwitching = true
            print("已设置isArticleSwitching=true，防止触发自动播放逻辑")
            
            // 在此情况下，仅设置显示用的文本，但不更改播放状态和当前文章
            // 这样界面可以显示新打开的文章内容，但不会影响当前正在播放的内容
            print("保留当前播放状态，仅更新UI显示")
            
            // 停止当前界面的计时器，防止更新不相关文章的进度条
            stopTimer()
            
            return
        }
        
        // 保存当前文章引用
        self.currentArticle = article
        self.currentText = article.content
        
        // 更新UI显示的状态
        self.currentProgress = 0.0
        self.currentTime = 0.0
        
        // 估算总时长 - 基于中文平均朗读速度约为每分钟200个字
        // 考虑语速，selectedRate 1.0 是正常速度
        let wordsPerMinute = 200.0 * selectedRate
        let estimatedMinutes = Double(article.content.count) / wordsPerMinute
        self.totalTime = estimatedMinutes * 60.0
        
        // 更新播放位置信息
        self.currentPlaybackPosition = 0
        
        // 检查是否需要恢复上次的播放进度
        let lastPlayedArticleId = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastPlayedArticleId)
        if let lastArticleIdStr = lastPlayedArticleId,
           let lastArticleId = UUID(uuidString: lastArticleIdStr),
           lastArticleId == article.id {
            
            print("检测到需要恢复上次播放进度")
            print("上次播放的文章ID: \(lastArticleIdStr)")
            
            // 读取保存的播放位置
            let savedPosition = UserDefaults.standard.integer(forKey: UserDefaultsKeys.lastPlaybackPosition(for: lastArticleId))
            let savedProgress = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastProgress(for: lastArticleId))
            let isFromListRepeat = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isFromListRepeat)
            
            print("保存的播放位置: \(savedPosition)")
            print("保存的播放进度: \(savedProgress)")
            print("是否来自列表循环模式: \(isFromListRepeat)")
            
            // 如果位置有效且不是从列表循环模式跳转过来的
            if savedPosition > 0 && !isFromListRepeat {
                self.currentPlaybackPosition = min(savedPosition, article.content.count - 1)
                self.currentProgress = min(savedProgress, 1.0)
                self.isResuming = true
                
                // 根据位置计算当前时间
                self.currentTime = self.totalTime * self.currentProgress
                
                print("恢复播放位置到: \(self.currentPlaybackPosition)，进度: \(self.currentProgress * 100)%")
            } else {
                self.isResuming = false
                print("放弃恢复进度，从头开始播放")
                // 重置恢复标志
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isFromListRepeat)
            }
        } else {
            self.isResuming = false
            print("无需恢复进度，从头开始播放")
        }
        
        print("设置完成，总时长估计: \(formatTime(totalTime))")
        print("===================================")
    }
    
    // 获取当前正在播放的文章
    func getCurrentArticle() -> Article? {
        return currentArticle
    }
    
    // 强制设置文章，忽略当前播放状态
    func forceSetup(for article: Article) {
        print("========= SpeechManager.forceSetup =========")
        print("强制设置文章: \(article.title)")
        print("文章ID: \(article.id.uuidString)")
        
        // 如果有文章正在播放，停止它
        if isPlaying {
            // 确保在停止之前设置标志，这样不会触发"播放完成"逻辑
            speechDelegate.isArticleSwitching = true
            print("已设置isArticleSwitching=true，防止触发自动播放逻辑")
            
            speechDelegate.wasManuallyPaused = true
            stopSpeaking(resetResumeState: true)
            
            // 检查标志是否被意外重置
            if !speechDelegate.isArticleSwitching {
                print("⚠️ 警告：stopSpeaking后isArticleSwitching已被意外重置为false，重新设置为true")
                speechDelegate.isArticleSwitching = true
            }
        }
        
        // 保存当前文章引用
        self.currentArticle = article
        self.currentText = article.content
        
        // 更新UI显示的状态
        self.currentProgress = 0.0
        self.currentTime = 0.0
        
        // 估算总时长
        let wordsPerMinute = 200.0 * selectedRate
        let estimatedMinutes = Double(article.content.count) / wordsPerMinute
        self.totalTime = estimatedMinutes * 60.0
        
        // 重置播放位置信息
        self.currentPlaybackPosition = 0
        self.isResuming = false
        
        // 确保代理状态重置
        speechDelegate.startPosition = 0
        speechDelegate.wasManuallyPaused = false
        
        print("强制设置完成，从头开始播放")
        print("===================================")
        
        // 强制刷新UI状态
        self.objectWillChange.send()
    }
    
    // 强制更新UI状态（进度条和高亮）- 供外部调用
    func forceUpdateUI(position: Int? = nil) {
        // 确保在主线程执行UI更新
        DispatchQueue.main.async {
            // 获取要更新的位置
            let updatePosition = position ?? self.currentPlaybackPosition
            
            // 只有在有效文本长度内才更新
            if self.currentText.count > 0 && updatePosition >= 0 && updatePosition < self.currentText.count {
                // 计算正确的进度
                let progress = Double(updatePosition) / Double(self.currentText.count)
                
                // 更新进度相关属性
                self.currentProgress = progress
                self.currentTime = self.totalTime * progress
                
                // 更新语音代理状态
                self.speechDelegate.startPosition = updatePosition
                self.speechDelegate.highlightRange = NSRange(location: updatePosition, length: 0)
                
                // 更新锁屏信息
                self.updateNowPlayingInfo()
                
                // 强制UI更新
                self.objectWillChange.send()
                
                print("强制更新UI - 位置: \(updatePosition)/\(self.currentText.count), 进度: \(Int(progress * 100))%")
            } else if updatePosition > 0 {
                print("警告: 无法更新UI，位置 \(updatePosition) 超出文本范围 0-\(self.currentText.count)")
            }
        }
        
        // 确保总时间已正确计算
        if self.totalTime <= 0 && self.currentArticle != nil {
            // 重新计算总时间
            let wordsPerMinute = 200.0 * selectedRate
            let estimatedMinutes = Double(self.currentText.count) / wordsPerMinute
            self.totalTime = estimatedMinutes * 60.0
            print("重新计算总时间: \(self.formatTime(self.totalTime))")
        }
        
        // 确保进度与时间一致
        if self.totalTime > 0 {
            self.currentTime = self.totalTime * self.currentProgress
        }
        
        // 强制通知UI更新
        self.objectWillChange.send()
    }
    
    // 获取合成器当前状态
    func getSynthesizerStatus() -> Bool {
        // 主要状态检查：检查合成器是否真正在播放
        let isSpeaking = synthesizer.isSpeaking
        let isPaused = synthesizer.isPaused
        
        // 更可靠的合成器状态检测：如果合成器处于暂停状态，则不应该被认为是在播放
        let actualSpeakingState = isSpeaking && !isPaused
        
        // 添加更多日志信息，包括详细的状态信息
        if let currentArticle = currentArticle {
            print("获取合成器状态 - 原始isSpeaking: \(isSpeaking), isPaused: \(isPaused), 实际播放状态: \(actualSpeakingState), 当前文章: \(currentArticle.title), ID: \(currentArticle.id)")
        } else {
            print("获取合成器状态 - 原始isSpeaking: \(isSpeaking), isPaused: \(isPaused), 实际播放状态: \(actualSpeakingState), 没有当前文章")
        }
        
        // 检查全局状态 - 是否有其他文章正在播放
        let playbackManager = PlaybackManager.shared
        let isGlobalPlayingDifferentContent = playbackManager.isPlaying && 
                                              playbackManager.currentContentId != currentArticle?.id && 
                                              playbackManager.currentContentId != nil
        
        // 如果全局有其他内容在播放，记录日志但不做改变
        if isGlobalPlayingDifferentContent {
            print("检测到全局有其他内容正在播放 - ID: \(playbackManager.currentContentId?.uuidString ?? "未知"), 标题: \(playbackManager.currentTitle)")
            print("不更新全局状态，保持其播放状态")
            return actualSpeakingState
        }
        
        // 如果合成器正在朗读，但UI状态不同步，记录额外信息帮助调试
        if actualSpeakingState && !isPlaying {
            if let currentArticle = currentArticle {
                print("状态不一致 - 合成器正在朗读但UI显示为暂停，当前文章: \(currentArticle.title), ID: \(currentArticle.id)")
                
                // 更新本地状态
                isPlaying = true
                self.objectWillChange.send()
                
                // 更新全局播放状态
                let contentType: PlaybackContentType = currentArticle.id.description.hasPrefix("doc-") ? .document : .article
                playbackManager.startPlayback(contentId: currentArticle.id, title: currentArticle.title, type: contentType)
            } else {
                print("状态不一致 - 合成器正在朗读但UI显示为暂停，且没有当前文章")
            }
        } else if !actualSpeakingState && isPlaying {
            // 如果合成器已停止但UI状态仍为播放，同样更新
            print("状态不一致 - 合成器已停止但UI仍显示为播放")
            
            // 更新本地状态
            isPlaying = false
            self.objectWillChange.send()
            
            // 更新全局播放状态
            playbackManager.stopPlayback()
        } else {
            // 确保全局状态与本地状态一致
            if let currentArticle = currentArticle {
                if isPlaying != playbackManager.isPlaying {
                    print("本地与全局状态不一致，正在同步 - 本地: \(isPlaying), 全局: \(playbackManager.isPlaying)")
                    if isPlaying {
                        let contentType: PlaybackContentType = currentArticle.id.description.hasPrefix("doc-") ? .document : .article
                        playbackManager.startPlayback(contentId: currentArticle.id, title: currentArticle.title, type: contentType)
                    } else {
                        playbackManager.stopPlayback()
                    }
                }
            }
        }
        
        return actualSpeakingState
    }
    
    // 获取合成器的实际播放状态
    private func getSpeakingState() -> Bool {
        // 主要状态检查：检查合成器是否真正在播放
        let isSpeaking = synthesizer.isSpeaking
        let isPaused = synthesizer.isPaused
        
        // 更可靠的合成器状态检测：如果合成器处于暂停状态，则不应该被认为是在播放
        let actualSpeakingState = isSpeaking && !isPaused
        
        // 添加更多日志信息，包括详细的状态信息
        if let currentArticle = currentArticle {
            print("获取合成器状态 - 原始isSpeaking: \(isSpeaking), isPaused: \(isPaused), 实际播放状态: \(actualSpeakingState), 当前文章: \(currentArticle.title), ID: \(currentArticle.id)")
        } else {
            print("获取合成器状态 - 原始isSpeaking: \(isSpeaking), isPaused: \(isPaused), 实际播放状态: \(actualSpeakingState), 没有当前文章")
        }
        
        // 检查全局状态 - 是否有其他文章正在播放
        let playbackManager = PlaybackManager.shared
        let isGlobalPlayingDifferentContent = playbackManager.isPlaying && 
                                              playbackManager.currentContentId != currentArticle?.id && 
                                              playbackManager.currentContentId != nil
        
        // 如果全局有其他内容在播放，记录日志但不做改变
        if isGlobalPlayingDifferentContent {
            print("检测到全局有其他内容正在播放 - ID: \(playbackManager.currentContentId?.uuidString ?? "未知"), 标题: \(playbackManager.currentTitle)")
            print("不更新全局状态，保持其播放状态")
            return actualSpeakingState
        }
        
        // 如果合成器正在朗读，但UI状态不同步，记录额外信息帮助调试
        if actualSpeakingState && !isPlaying {
            if let currentArticle = currentArticle {
                print("状态不一致 - 合成器正在朗读但UI显示为暂停，当前文章: \(currentArticle.title), ID: \(currentArticle.id)")
                
                // 更新本地状态
                isPlaying = true
                self.objectWillChange.send()
                
                // 更新全局播放状态
                let contentType: PlaybackContentType = currentArticle.id.description.hasPrefix("doc-") ? .document : .article
                playbackManager.startPlayback(contentId: currentArticle.id, title: currentArticle.title, type: contentType)
            } else {
                print("状态不一致 - 合成器正在朗读但UI显示为暂停，且没有当前文章")
            }
        } else if !actualSpeakingState && isPlaying {
            // 如果合成器已停止但UI状态仍为播放，同样更新
            print("状态不一致 - 合成器已停止但UI仍显示为播放")
            
            // 更新本地状态
            isPlaying = false
            self.objectWillChange.send()
            
            // 更新全局播放状态
            playbackManager.stopPlayback()
        } else {
            // 确保全局状态与本地状态一致
            if let currentArticle = currentArticle {
                if isPlaying != playbackManager.isPlaying {
                    print("本地与全局状态不一致，正在同步 - 本地: \(isPlaying), 全局: \(playbackManager.isPlaying)")
                    if isPlaying {
                        let contentType: PlaybackContentType = currentArticle.id.description.hasPrefix("doc-") ? .document : .article
                        playbackManager.startPlayback(contentId: currentArticle.id, title: currentArticle.title, type: contentType)
                    } else {
                        playbackManager.stopPlayback()
                    }
                }
            }
        }
        
        return actualSpeakingState
    }
    
    // 计算当前朗读位置
    private func calculateCurrentPosition() -> Int {
        // 首先尝试从高亮区域获取当前位置
        if speechDelegate.highlightRange.location > 0 {
            // 如果有高亮区域，使用它的位置
            return speechDelegate.highlightRange.location
        }
        
        // 如果没有高亮区域，根据进度估算位置
        let estimatedPosition = Int(currentProgress * Double(currentText.count))
        
        // 如果进度接近0但已经开始播放了一段时间，使用默认的最小值
        if estimatedPosition < 5 && currentTime > 2.0 {
            return 5 // 假设至少已经朗读了几个字符
        }
        
        return estimatedPosition
    }
    
    // 清空播放列表和相关状态
    func clearPlaylist() {
        // 停止当前播放
        if isPlaying {
            stopSpeaking()
        }
        
        // 清空播放列表
        lastPlayedArticles = []
        
        // 保存空的播放列表
        saveLastPlayedArticles()
        
        // 重置播放状态
        currentProgress = 0.0
        currentTime = 0.0
        totalTime = 0.0
        currentPlaybackPosition = 0
        isResuming = false
        
        // 清空当前文章
        currentArticle = nil
        currentText = ""
        
        print("播放列表和相关状态已清空")
    }
    
    // 提供一个方法，可以直接获取和更新当前播放时间
    func getCurrentTimeInfo() -> (current: TimeInterval, total: TimeInterval) {
        // 如果正在播放但时间没有更新，则手动推进
        if isPlaying && speechDelegate.isSpeaking {
            // 检测到正在播放但时间可能停滞
            // 强制触发UI更新
            objectWillChange.send()
        }
        
        return (currentTime, totalTime)
    }
    
    // 更新UI中的播放进度
    private func updatePlaybackProgress() {
        guard isPlaying else { return }
        
        // 根据播放方式获取进度
        if let _ = currentAudioFileURL {
            // 使用音频文件播放
            // AudioFileManager.shared是单例，不需要通过条件绑定
            let audioManager = AudioFileManager.shared
            let progress = audioManager.getProgress()
            let currentAudioTime = audioManager.getCurrentTime()
            let duration = audioManager.getDuration()
            
            if duration > 0 {
                currentProgress = Double(progress)
                currentTime = currentAudioTime
                
                // 计算当前位置（用于高亮）
                let position = calculatePositionFromProgress(currentProgress)
                let range = NSRange(location: position, length: 1)
                
                // 更新高亮范围
                speechDelegate.highlightRange = range
            }
        } else if synthesizer.isSpeaking {
            // 使用直接合成播放
            // 直接使用当前进度
        }
        
        // 通知UI更新
        self.objectWillChange.send()
    }
    
    // 跳转到指定时间
    func skipToTime(_ targetTime: TimeInterval) {
        guard !isDragging, isPlaying, totalTime > 0 else { return }
        
        // 计算目标进度
        let targetProgress = targetTime / totalTime
        let targetPosition = calculatePositionFromProgress(targetProgress)
        
        print("跳转到时间: \(formatTime(targetTime)), 位置: \(targetPosition)")
        
        // 使用不同的处理方式
        if let fileURL = currentAudioFileURL {
            // 如果使用音频文件播放，尝试设置播放位置
            let duration = AudioFileManager.shared.getDuration()
            if duration > 0 {
                // 计算目标音频时间
                let audioTargetTime = duration * targetProgress
                
                // 直接设置音频播放位置
                AudioFileManager.shared.setPlaybackPosition(audioTargetTime)
                
                // 更新当前进度和时间
                currentProgress = targetProgress
                currentTime = targetTime
                
                // 更新高亮范围
                let range = NSRange(location: targetPosition, length: 1)
                speechDelegate.highlightRange = range
                
                print("已设置音频播放位置到: \(audioTargetTime)秒")
                return
            }
        }
        
        // 如果使用直接合成或音频文件处理失败，重新从目标位置开始播放
        self.stopSpeaking(resetResumeState: true)
        self.currentPlaybackPosition = targetPosition
        self.currentProgress = targetProgress
        self.currentTime = targetTime
        self.isResuming = true
        
        // 延迟一点点再开始播放，避免状态未完全更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.startSpeakingFromPosition(targetPosition)
        }
    }
    
    // 获取AudioFileManager的播放进度
    func getAudioProgress() -> Float {
        return AudioFileManager.shared.getProgress()
    }
    
    // 获取当前播放的音频文件时长
    func getAudioDuration() -> TimeInterval {
        return AudioFileManager.shared.getDuration()
    }
    
    // 获取当前播放的音频文件时间
    func getAudioCurrentTime() -> TimeInterval {
        return AudioFileManager.shared.getCurrentTime()
    }
    
    // 根据进度计算位置
    private func calculatePositionFromProgress(_ progress: Double) -> Int {
        // 确保进度在有效范围内
        let validProgress = max(0, min(1, progress))
        
        // 计算当前文本中的位置
        let position = Int(validProgress * Double(currentText.count))
        
        // 确保位置在有效范围内
        return max(0, min(position, currentText.count - 1))
    }
    
    // 加载上一次播放的文章列表
    private func loadLastPlayedArticles() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.lastPlayedArticles),
           let articles = try? JSONDecoder().decode([Article].self, from: data) {
            lastPlayedArticles = articles
        }
    }
    
    // 保存上一次播放的文章列表
    private func saveLastPlayedArticles() {
        if let data = try? JSONEncoder().encode(lastPlayedArticles) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.lastPlayedArticles)
        }
    }
    
    // 更新播放列表
    func updatePlaylist(_ articles: [Article]) {
        self.lastPlayedArticles = articles
        
        // 保存到UserDefaults中
        if let encoded = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(encoded, forKey: UserDefaultsKeys.lastPlayedArticles)
        }
    }
    
    // 格式化时间
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // 跳转到指定进度位置
    func seekToProgress(_ progress: Double) {
        // 确保有效的进度值
        let validProgress = max(0, min(1, progress))
        
        // 如果总时长有效，计算目标时间
        if totalTime > 0 {
            let targetTime = validProgress * totalTime
            skipToTime(targetTime)
        } else {
            // 如果没有有效的总时长，尝试直接根据进度跳转
            let targetPosition = calculatePositionFromProgress(validProgress)
            stopSpeaking(resetResumeState: true)
            currentPlaybackPosition = targetPosition
            currentProgress = validProgress
            isResuming = true
            
            // 延迟一点点再开始播放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startSpeakingFromPosition(targetPosition)
            }
        }
    }
    
    // 重置播放标志，用于在视图之间切换时避免状态不一致
    func resetPlaybackFlags() {
        // 重置SpeechDelegate中的标志
        speechDelegate.wasManuallyPaused = false
        speechDelegate.isNearArticleEnd = false
        speechDelegate.isArticleSwitching = false
        speechDelegate.startPosition = 0
        
        // 确保自身的状态标志一致
        isProcessingNextArticle = false
    }
}