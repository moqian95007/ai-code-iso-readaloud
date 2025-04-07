import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

/// 播放模式枚举
enum PlaybackMode: String, CaseIterable {
    case singlePlay = "单篇播放"  // 播放完当前文章后停止
    case singleRepeat = "单篇循环"  // 循环播放当前文章
    case listRepeat = "列表循环"  // 循环播放列表中的文章
    
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
        
        // 首先检查合成器是否在朗读
        let isSynthesizerSpeaking = synthesizer.isSpeaking
        
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
        
        // 2. 如果UUID不匹配，尝试通过章节号匹配
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
        
        print("当前文章ID: \(currentArticle.id), 检查ID: \(articleId), ID匹配: \(isIdMatched), 章节匹配: \(isChapterMatched), 合成器状态: \(isSynthesizerSpeaking)")
        
        // 返回是否在播放这篇文章（ID匹配或章节号匹配）
        return (isIdMatched || isChapterMatched) && isSynthesizerSpeaking
    }
    
    // 计时器
    private var timer: Timer?
    
    // 防止重复触发下一篇播放的标志
    private var isProcessingNextArticle: Bool = false
    
    // 实例变量，用于跟踪上次开始朗读的时间
    private var lastStartTime: Date = Date(timeIntervalSince1970: 0)
    
    // 实例变量，用于跟踪上次跳转的时间
    private var lastSkipTime: Date = Date(timeIntervalSince1970: 0)
    
    private init() {
        synthesizer.delegate = speechDelegate
        
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
    
    // 处理朗读完成事件
    @objc private func handleSpeechFinished() {
        print("========= 朗读完成事件触发 =========")
        print("当前模式: \(playbackMode.rawValue)")
        print("isPlaying: \(isPlaying), isResuming: \(isResuming)")
        print("手动暂停标志: \(speechDelegate.wasManuallyPaused)")
        print("起始位置: \(speechDelegate.startPosition)")
        print("正在处理下一篇文章: \(isProcessingNextArticle)")
        
        // 如果已在处理下一篇文章请求，跳过当前处理
        if isProcessingNextArticle {
            print("已在处理下一篇文章请求，跳过当前事件处理")
            return
        }
        
        // 此时synthesizer已经停止朗读，但我们需要确定是自然结束还是手动暂停
        // 手动暂停时会设置isResuming=true，isPlaying=false
        let isUserPaused = isResuming && !isPlaying
        
        // 检查是否是从中间位置开始的播放
        let isStartedFromMiddle = speechDelegate.startPosition > 0
        
        if isUserPaused {
            print("检测到是用户手动暂停，不执行自动播放")
            return
        }
        
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
    private func playNextArticle() {
        print("========= 请求播放下一篇文章 =========")
        
        // 判断当前播放列表状态
        if currentArticle == nil {
            print("当前没有正在播放的文章")
        } else {
            print("当前文章: \(currentArticle!.title)")
        }
        
        print("播放列表文章数: \(lastPlayedArticles.count)")
        print("当前播放模式: \(playbackMode.rawValue)")
        
        // 发送通知请求播放下一篇文章
        NotificationCenter.default.post(
            name: Notification.Name("PlayNextArticle"),
            object: nil
        )
        
        print("已发送PlayNextArticle通知")
        print("=====================================")
    }
    
    // 初始化设置
    func setup(for article: Article) {
        // 如果是同一篇文章，保持当前状态
        if currentArticle?.id == article.id {
            return
        }
        
        // 如果是新文章，重置所有状态
        currentArticle = article
        currentText = article.content
        
        // 计算总时长估计值 (按照每分钟300个汉字的朗读速度估算)
        let wordsCount = Double(currentText.count)
        totalTime = wordsCount / 5.0  // 每秒朗读5个字
        
        // 重置播放状态
        isPlaying = false
        currentProgress = 0.0
        currentTime = 0.0
        
        // 获取保存的播放位置
        if let articleId = currentArticle?.id {
            let savedPosition = UserDefaults.standard.integer(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
            let savedProgress = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastProgress(for: articleId))
            let savedTime = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
            let wasPlaying = UserDefaults.standard.bool(forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            
            // 检查保存的位置是否有效且在文本范围内
            if savedPosition > 0 && savedPosition < currentText.count {
                currentPlaybackPosition = savedPosition
                isResuming = true  // 设置为恢复状态，这样UI会显示"继续朗读"按钮
                
                // 更新进度条和时间显示
                currentProgress = savedProgress > 0 ? savedProgress : Double(savedPosition) / Double(currentText.count)
                currentTime = savedTime > 0 ? savedTime : totalTime * currentProgress
                
                // 强制更新UI状态
                forceUpdateUI(position: savedPosition)
                
                print("恢复播放位置: \(savedPosition)/\(currentText.count), 进度: \(Int(currentProgress * 100))%")
            } else {
                // 如果没有有效的保存位置，重置位置
                currentPlaybackPosition = 0
                isResuming = false
                
                // 重置语音代理状态
                speechDelegate.startPosition = 0
                speechDelegate.highlightRange = NSRange(location: 0, length: 0)
            }
        } else {
            // 新文章，没有历史记录
            currentPlaybackPosition = 0
            isResuming = false
            
            // 重置语音代理状态
            speechDelegate.startPosition = 0
            speechDelegate.highlightRange = NSRange(location: 0, length: 0)
        }
    }
    
    // 获取选择的语音对象
    func getSelectedVoice() -> AVSpeechSynthesisVoice? {
        if selectedVoiceIdentifier.isEmpty {
            // 默认使用第一个中文语音
            let chineseVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "zh") }
            if let defaultVoice = chineseVoices.first {
                selectedVoiceIdentifier = defaultVoice.identifier
                UserDefaults.standard.set(selectedVoiceIdentifier, forKey: UserDefaultsKeys.selectedVoiceIdentifier)
                return defaultVoice
            }
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
        
        return AVSpeechSynthesisVoice.speechVoices().first { $0.identifier == selectedVoiceIdentifier }
    }
    
    // 更新锁屏界面信息
    private func updateNowPlayingInfo() {
        guard let article = currentArticle else { return }
        
        // 创建信息字典
        var nowPlayingInfo = [String: Any]()
        
        // 设置标题和详情
        nowPlayingInfo[MPMediaItemPropertyTitle] = article.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = "ReadAloud App"
        
        // 设置总时长和当前播放位置
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = totalTime
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // 设置播放速率
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 应用信息到锁屏
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // 开始朗读全文
    func startSpeaking() {
        print("开始朗读全文，进行额外的安全检查")
        
        // 防止短时间内重复调用
        let now = Date()
        if now.timeIntervalSince(lastStartTime) < 1.0 && synthesizer.isSpeaking {
            print("⚠️ 短时间内重复启动朗读，已忽略")
            return
        }
        lastStartTime = now
        
        // 如果全局有其他内容在播放，先停止它
        if playbackManager.isPlaying && playbackManager.currentContentId != currentArticle?.id {
            playbackManager.stopPlayback()
        }
        
        // 如果正在播放，先停止当前播放
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            speechDelegate.isSpeaking = false
            stopTimer()
            
            // 延迟一点再重新开始，确保前一个朗读已完全停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.doStartSpeaking()
            }
            return
        }
        
        // 不在播放中，直接开始
        doStartSpeaking()
        
        print("开始朗读完成")
    }
    
    // 实际执行朗读的内部方法
    private func doStartSpeaking() {
        // 重置进度和时间
        currentProgress = 0.0
        currentTime = 0.0
        
        // 重置起始位置为0
        speechDelegate.startPosition = 0
        
        // 重置关键标志
        speechDelegate.wasManuallyPaused = false
        
        // 创建语音合成器使用的话语对象
        let utterance = AVSpeechUtterance(string: currentText)
        
        // 设置语音参数
        if let voice = getSelectedVoice() {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        utterance.rate = Float(selectedRate) * 0.4  // 转换为AVSpeechUtterance接受的范围
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 记录播放开始的时间戳
        if let articleId = currentArticle?.id {
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.lastPlayTime(for: articleId))
            
            // 记录当前我们正在朗读这篇文章
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            
            // 更新全局播放状态
            let contentType: PlaybackContentType = articleId.description.hasPrefix("doc-") ? .document : .article
            playbackManager.startPlayback(contentId: articleId, title: currentArticle?.title ?? "", type: contentType)
        }
        
        // 开始朗读
        synthesizer.speak(utterance)
        
        // 更新状态
        isPlaying = true
        
        // 更新锁屏界面信息
        updateNowPlayingInfo()
        
        // 开始定时器更新进度
        startTimer()
    }
    
    // 从指定位置开始朗读
    func startSpeakingFromPosition(_ position: Int) {
        print("========= 从指定位置开始朗读 =========")
        print("指定位置: \(position)")
        print("文本总长度: \(currentText.count)")
        
        // 如果正在播放，先停止当前播放
        if synthesizer.isSpeaking {
            print("停止当前播放")
            synthesizer.stopSpeaking(at: .immediate)
            speechDelegate.isSpeaking = false
            stopTimer()
        }
        
        // 安全检查：确保位置在有效范围内
        let safePosition = max(0, min(position, currentText.count - 1))
        if safePosition != position {
            print("位置超出范围，调整为安全位置: \(safePosition)")
        }
        
        // 判断是否是从中间位置开始的新播放
        let isResumeFromMiddle = safePosition > 0 && safePosition < currentText.count - 1
        
        // 如果是从中间位置开始的播放（非开头非结尾），应该被视为用户操作，不应触发自动"下一篇"逻辑
        if isResumeFromMiddle || isResuming {
            print("从中间位置开始播放或恢复播放，标记为用户操作")
            // 设置手动暂停标志，防止播放完成后自动跳转
            speechDelegate.wasManuallyPaused = true
        } else {
            // 只有从头开始播放时才重置手动暂停标志
            speechDelegate.wasManuallyPaused = false
            print("从头开始播放，重置手动暂停标志")
        }
        
        // 设置朗读起始位置
        speechDelegate.startPosition = safePosition
        
        // 立即更新进度和高亮范围 - 使用工具方法确保一致性
        forceUpdateUI(position: safePosition)
        
        if let articleId = currentArticle?.id {
            // 记录播放开始的时间戳
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.lastPlayTime(for: articleId))
            
            // 记录当前我们正在朗读这篇文章
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            
            // 更新全局播放状态
            let contentType: PlaybackContentType = articleId.description.hasPrefix("doc-") ? .document : .article
            playbackManager.startPlayback(contentId: articleId, title: currentArticle?.title ?? "", type: contentType)
        }
        
        if safePosition >= currentText.count || currentText.isEmpty {
            print("位置无效或文本为空，从头开始播放")
            startSpeaking()
            return
        }
        
        // 获取从指定位置开始的子字符串
        let startIndex = currentText.index(currentText.startIndex, offsetBy: safePosition)
        let subText = String(currentText[startIndex...])
        
        // 安全检查：确保子文本非空且长度合理
        if subText.isEmpty {
            print("截取的子文本为空，从头开始播放")
            startSpeaking()
            return
        }
        
        // 新增: 检查如果剩余文本太短且接近文章末尾，应该从头开始或跳到下一篇
        let isNearEnd = safePosition > (currentText.count * 9 / 10) // 最后10%
        let isShortText = subText.count < 50 // 文本少于50个字符视为短文本
        
        if isNearEnd && isShortText {
            print("检测到剩余文本过短且接近末尾，可能导致无限循环问题")
            
            // 根据不同播放模式执行相应操作
            if playbackMode == .singleRepeat {
                print("单篇循环模式下，直接重置到文章开头")
                // 重置位置为0
                speechDelegate.startPosition = 0
                
                // 确保正确设置标志
                speechDelegate.wasManuallyPaused = false
                
                // 立即更新进度和高亮范围
                forceUpdateUI(position: 0)
                
                // 从头开始播放
                startSpeaking()
                return
            } else if playbackMode == .listRepeat {
                print("列表循环模式下，准备播放下一篇文章")
                
                // 设置处理标志，防止重复处理
                if !isProcessingNextArticle {
                    isProcessingNextArticle = true
                    
                    // 停止当前播放
                    stopSpeaking(resetResumeState: true)
                    
                    // 重置起始位置
                    speechDelegate.startPosition = 0
                    speechDelegate.wasManuallyPaused = false
                    
                    // 立即更新进度和高亮范围
                    forceUpdateUI(position: 0)
                    
                    // 延迟发送通知，确保UI有时间更新
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: Notification.Name("PlayNextArticle"),
                            object: nil
                        )
                        
                        // 延迟重置处理标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.isProcessingNextArticle = false
                        }
                    }
                    return
                }
            }
        }
        
        print("从位置 \(safePosition) 开始播放文本，长度: \(subText.count)")
        
        // 创建语音合成器使用的话语对象
        let utterance = AVSpeechUtterance(string: subText)
        
        // 设置语音参数，应用选择的语音
        if let voice = getSelectedVoice() {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        
        // 设置语速
        utterance.rate = Float(selectedRate) * 0.4
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 关联utterance和位置
        speechDelegate.setPosition(for: utterance, position: safePosition)
        
        // 开始朗读
        synthesizer.speak(utterance)
        
        // 更新状态
        isPlaying = true
        isResuming = false  // 重置恢复状态，因为现在已经开始播放了
        
        // 更新锁屏界面信息
        updateNowPlayingInfo()
        
        // 开始定时器更新进度
        startTimer()
    }
    
    // 暂停朗读
    func pauseSpeaking(updateGlobalState: Bool = true) {
        guard isPlaying else { return }
        
        // 添加防抖动，避免短时间内多次触发
        let now = Date()
        if now.timeIntervalSince(lastStartTime) < 0.5 {
            print("暂停操作太频繁，忽略")
            return
        }
        
        // 记录下播放位置
        if !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .immediate)
        }
        
        // 停止计时器
        timer?.invalidate()
        timer = nil
        
        // 更新状态
        isPlaying = false
        isResuming = true
        
        // 保存播放进度
        if let articleId = currentArticle?.id {
            UserDefaults.standard.set(currentPlaybackPosition, forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
            UserDefaults.standard.set(currentProgress, forKey: UserDefaultsKeys.lastProgress(for: articleId))
            UserDefaults.standard.set(currentTime, forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            
            // 无论updateGlobalState参数如何，始终更新全局状态
            // 这是为了确保全局状态与本地状态一致
            playbackManager.pausePlayback()
            
            // 添加额外的日志
            print("暂停朗读 - 已更新本地状态和全局状态")
            print("本地状态: isPlaying=\(isPlaying), 全局状态: \(playbackManager.isPlaying)")
        }
        
        // 更新锁屏控制中心信息
        updateNowPlayingInfo()
        
        // 检查是否是被定时器触发的暂停
        let timerManager = TimerManager.shared
        if timerManager.isTimerActive && timerManager.selectedOption != .afterChapter && timerManager.remainingSeconds <= 0 {
            // 发送通知
            NotificationCenter.default.post(name: Notification.Name("TimerCompleted"), object: nil)
        }
    }
    
    // 停止朗读
    func stopSpeaking(resetResumeState: Bool = true) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            
            // 重置所有状态
            speechDelegate.isSpeaking = false
            speechDelegate.startPosition = 0
            
            // 只有在指定需要重置恢复状态时才重置
            if resetResumeState {
                isResuming = false
                currentPlaybackPosition = 0
                
                // 重置进度
                currentProgress = 0.0
                currentTime = 0.0
                
                // 清除保存的播放进度
                if let articleId = currentArticle?.id {
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress(for: articleId))
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
                }
            }
            
            // 更新状态
            isPlaying = false
            
            // 更新全局播放状态
            playbackManager.stopPlayback()
            
            // 停止定时器
            stopTimer()
        }
    }
    
    // 跳转到指定进度位置
    func seekToProgress(_ progress: Double) {
        print("========= 跳转到进度位置 =========")
        
        // 确保进度值在有效范围内
        let clampedProgress = max(0, min(1, progress))
        print("目标进度: \(Int(clampedProgress * 100))%")
        
        // 计算对应的字符位置
        let targetPosition = Int(clampedProgress * Double(currentText.count))
        print("计算的目标位置: \(targetPosition)/\(currentText.count)")
        
        // 更新当前位置和进度
        currentPlaybackPosition = targetPosition
        
        // 立即更新UI显示，确保一致性
        forceUpdateUI(position: targetPosition)
        
        // 如果正在播放，停止当前播放并从新位置开始
        if isPlaying {
            // 确保标记手动操作
            speechDelegate.wasManuallyPaused = true
            
            // 从新位置开始播放
            startSpeakingFromPosition(targetPosition)
        } else {
            // 如果不在播放，仅更新位置和UI显示，但不开始播放
            // 设置语音代理的起始位置
            speechDelegate.startPosition = targetPosition
            
            // 保存播放位置，以便下次点击"继续上次播放"时从此位置开始
            if let articleId = currentArticle?.id {
                UserDefaults.standard.set(targetPosition, forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
                UserDefaults.standard.set(clampedProgress, forKey: UserDefaultsKeys.lastProgress(for: articleId))
                UserDefaults.standard.set(currentTime, forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
            }
        }
        
        // 设置恢复状态为true，表示有保存的播放位置
        if targetPosition > 0 {
            isResuming = true
        }
        
        print("成功跳转到新位置并更新UI")
        print("=======================================")
    }
    
    // 后退指定秒数
    func skipBackward(seconds: TimeInterval) {
        print("========= 后退\(seconds)秒 =========")
        print("文本总长度: \(currentText.count)")
        
        // 如果文本为空，不进行操作
        if currentText.isEmpty {
            print("文本为空，无法后退")
            return
        }
        
        // 计算新的时间点，确保不小于0
        let newTime = max(currentTime - seconds, 0)
        // 计算新的进度
        let newProgress = newTime / totalTime
        // 计算对应的文本位置
        let newPosition = Int(Double(currentText.count) * newProgress)
        
        // 确保位置在有效范围内
        let safePosition = max(0, min(newPosition, currentText.count - 1))
        
        print("后退\(seconds)秒，新时间：\(newTime)，新位置：\(safePosition)")
        
        // 标记为手动操作，防止触发自动循环
        speechDelegate.wasManuallyPaused = true
        
        // 如果正在播放，则停止当前朗读并从新位置开始
        if isPlaying {
            // 停止当前朗读但不重置恢复状态
            stopSpeaking(resetResumeState: false)
            
            // 更新UI和状态
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = safePosition
            isResuming = true
            
            // 延迟一点再开始播放，确保之前的停止已经完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("从新位置开始播放")
                // 确保设置正确的标志，防止从中间位置播放结束后自动循环
                self.speechDelegate.wasManuallyPaused = true
                self.startSpeakingFromPosition(safePosition)
            }
        } else {
            // 仅更新位置
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = safePosition
            isResuming = true
            
            // 保存进度
            savePlaybackProgress()
            print("只更新位置，不开始播放")
        }
        
        print("=====================================")
    }
    
    // 前进指定秒数
    func skipForward(seconds: TimeInterval) {
        print("========= 前进\(seconds)秒 =========")
        print("文本总长度: \(currentText.count)")
        print("当前暂停标志: \(speechDelegate.wasManuallyPaused)")
        
        // 防止短时间内重复调用
        let now = Date()
        if now.timeIntervalSince(self.lastSkipTime) < 1.0 {
            print("⚠️ 跳转操作间隔太短，忽略此次请求")
            return
        }
        self.lastSkipTime = now
        
        // 如果文本为空，不进行操作
        if currentText.isEmpty {
            print("文本为空，无法前进")
            return
        }
        
        // 计算新的时间点
        let newTime = min(currentTime + seconds, totalTime)
        // 计算新的进度
        let newProgress = newTime / totalTime
        // 计算对应的文本位置
        let newPosition = Int(Double(currentText.count) * newProgress)
        
        // 确保位置在有效范围内
        let safePosition = max(0, min(newPosition, currentText.count - 1))
        
        print("前进\(seconds)秒，新时间：\(newTime)，新位置：\(safePosition)")
        
        // 特殊处理：列表中只有一篇文章且接近末尾的情况
        let isNearEnd = safePosition >= currentText.count - 10 // 如果只剩下10个字符，视为接近末尾
        
        if isNearEnd {
            print("已接近文章末尾，根据播放模式决定操作")
            
            // 特殊处理：列表循环中只有一篇文章的情况
            if playbackMode == .listRepeat && lastPlayedArticles.count == 1 {
                print("列表循环中只有一篇文章：直接重置到开头")
                
                // 从头开始播放当前文章
                currentPlaybackPosition = 0
                currentProgress = 0.0
                currentTime = 0.0
                speechDelegate.startPosition = 0
                
                // 设置标记，防止自动循环
                isProcessingNextArticle = true
                speechDelegate.wasManuallyPaused = true
                
                // 停止当前播放
                if synthesizer.isSpeaking {
                    synthesizer.stopSpeaking(at: .immediate)
                    speechDelegate.isSpeaking = false
                    stopTimer()
                }
                
                // 使用较长延迟确保完全重置
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // 重置标记，开始新播放
                    self.speechDelegate.wasManuallyPaused = false
                    self.speechDelegate.startPosition = 0
                    self.isProcessingNextArticle = false
                    
                    // 从头开始播放
                    self.startSpeaking()
                    print("单文章列表循环：重新从头开始播放")
                }
                return
            }
            // 其他模式的处理
            else if playbackMode == .singleRepeat {
                print("单篇循环模式：直接重置到开头")
                // 从头开始播放当前文章
                currentPlaybackPosition = 0
                currentProgress = 0.0
                currentTime = 0.0
                
                // 确保重置起始位置
                speechDelegate.startPosition = 0
                
                if isPlaying {
                    // 确保完全停止当前播放
                    stopSpeaking(resetResumeState: true)
                    
                    // 延迟一点再开始播放，确保之前的停止已经完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // 重置标志，防止在新播放中错误地识别为手动暂停
                        self.speechDelegate.wasManuallyPaused = false
                        self.speechDelegate.startPosition = 0
                        
                        // 从头开始播放
                        self.startSpeaking()
                    }
                } else {
                    // 不在播放状态，只重置位置
                    savePlaybackProgress()
                }
                return
            } else if playbackMode == .listRepeat {
                print("列表循环模式（多篇）：准备播放下一篇文章")
                
                // 重置起始位置，避免下一篇文章从中间开始
                speechDelegate.startPosition = 0
                
                if isPlaying {
                    // 确保完全停止当前播放
                    stopSpeaking(resetResumeState: true)
                    
                    // 延迟发送播放下一篇通知
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // 重置标志
                        self.speechDelegate.wasManuallyPaused = false
                        self.isProcessingNextArticle = true
                        
                        // 发送通知请求播放下一篇
                        NotificationCenter.default.post(
                            name: Notification.Name("PlayNextArticle"),
                            object: nil
                        )
                        
                        // 延迟重置标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.isProcessingNextArticle = false
                        }
                    }
                } else {
                    // 不在播放状态，只重置位置
                    currentPlaybackPosition = 0
                    currentProgress = 0.0
                    currentTime = 0.0
                    savePlaybackProgress()
                }
                return
            }
        }
        
        // 标记为手动操作，防止触发自动循环
        speechDelegate.wasManuallyPaused = true
        
        // 如果正在播放，则停止当前朗读并从新位置开始
        if isPlaying {
            // 停止当前朗读但不重置恢复状态
            stopSpeaking(resetResumeState: false)
            
            // 更新UI和状态
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = safePosition
            isResuming = true
            
            // 延迟一点再开始播放，确保之前的停止已经完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("从新位置开始播放")
                // 确保设置正确的标志，防止从中间位置播放结束后自动循环
                self.speechDelegate.wasManuallyPaused = true
                self.startSpeakingFromPosition(safePosition)
            }
        } else {
            // 仅更新位置
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = safePosition
            isResuming = true
            
            // 保存进度
            savePlaybackProgress()
            print("只更新位置，不开始播放")
        }
        
        print("=====================================")
    }
    
    // 应用新的语速设置
    func applyNewSpeechRate() {
        print("========= 应用新的语速设置 =========")
        // 保存设置
        UserDefaults.standard.set(selectedRate, forKey: UserDefaultsKeys.selectedRate)
        
        // 如果正在朗读，需要停止并重新开始
        if isPlaying {
            // 保存当前位置
            let currentPosition = speechDelegate.highlightRange.location
            print("保存当前朗读位置: \(currentPosition)")
            
            // 设置标记为手动操作，防止触发自动循环
            speechDelegate.wasManuallyPaused = true
            
            // 停止当前朗读但不重置恢复状态
            synthesizer.stopSpeaking(at: .immediate)
            speechDelegate.isSpeaking = false
            
            // 短暂延迟后从保存的位置以新的语速开始朗读
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("以新语速从位置 \(currentPosition) 继续朗读")
                self.startSpeakingFromPosition(currentPosition)
            }
        }
        print("=====================================")
    }
    
    // 应用新的语音设置
    func applyNewVoice() {
        print("========= 应用新的语音设置 =========")
        // 保存设置
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: UserDefaultsKeys.selectedVoiceIdentifier)
        
        // 如果正在朗读，需要停止并重新开始
        if isPlaying {
            // 保存当前位置
            let currentPosition = speechDelegate.highlightRange.location
            print("保存当前朗读位置: \(currentPosition)")
            
            // 设置标记为手动操作，防止触发自动循环
            speechDelegate.wasManuallyPaused = true
            
            // 停止当前朗读但不重置恢复状态
            synthesizer.stopSpeaking(at: .immediate)
            speechDelegate.isSpeaking = false
            
            // 短暂延迟后从保存的位置以新的语音开始朗读
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("以新语音从位置 \(currentPosition) 继续朗读")
                self.startSpeakingFromPosition(currentPosition)
            }
        }
        print("=====================================")
    }
    
    // 保存播放进度
    func savePlaybackProgress() {
        if let articleId = currentArticle?.id {
            UserDefaults.standard.set(currentPlaybackPosition, forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
            UserDefaults.standard.set(currentProgress, forKey: UserDefaultsKeys.lastProgress(for: articleId))
            UserDefaults.standard.set(currentTime, forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
            UserDefaults.standard.set(isPlaying, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
        }
    }
    
    // 启动计时器，定期更新进度
    private func startTimer() {
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if !self.isDragging && self.speechDelegate.isSpeaking {
                let currentPosition = self.speechDelegate.highlightRange.location
                if self.currentText.count > 0 && currentPosition > 0 {
                    // 计算正常进度
                    let calculatedProgress = Double(currentPosition) / Double(self.currentText.count)
                    
                    // 检查是否接近文章末尾（例如剩余不到5%的内容）
                    if currentPosition >= Int(Double(self.currentText.count) * 0.95) {
                        // 随着接近末尾，逐渐接近100%
                        let remainingPercentage = Double(self.currentText.count - currentPosition) / Double(self.currentText.count)
                        let adjustedProgress = 1.0 - (remainingPercentage * 0.5) // 缓慢接近1.0
                        self.currentProgress = min(adjustedProgress, 1.0)
                    } else {
                        self.currentProgress = calculatedProgress
                    }
                    
                    self.currentTime = self.totalTime * self.currentProgress
                    
                    // 每隔几秒保存一次播放进度
                    if Int(self.currentTime) % 5 == 0 { // 每5秒保存一次
                        self.currentPlaybackPosition = currentPosition
                        self.savePlaybackProgress()
                    }
                }
            }
        }
    }
    
    // 停止计时器
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // 查找段落是否包含高亮范围
    func paragraphContainsHighlight(paragraph: String, fullText: String) -> Bool {
        if !speechDelegate.isSpeaking {
            return false
        }
        
        // 计算段落在全文中的范围
        if let startIndex = fullText.range(of: paragraph)?.lowerBound {
            let paragraphStart = fullText.distance(from: fullText.startIndex, to: startIndex)
            let paragraphEnd = paragraphStart + paragraph.count
            
            // 检查朗读范围是否与段落范围重叠
            let highlightRange = speechDelegate.highlightRange
            return highlightRange.location >= paragraphStart && highlightRange.location < paragraphEnd
        }
        return false
    }
    
    // 格式化时间显示
    func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    // 清理资源
    func cleanup() {
        stopTimer()
        // 只保存播放进度，但不暂停播放
        savePlaybackProgress()
    }
    
    // 切换播放模式
    func togglePlaybackMode() {
        let modes = PlaybackMode.allCases
        if let currentIndex = modes.firstIndex(of: playbackMode) {
            let nextIndex = (currentIndex + 1) % modes.count
            playbackMode = modes[nextIndex]
        } else {
            playbackMode = .singlePlay
        }
        
        // 保存设置
        UserDefaults.standard.set(playbackMode.rawValue, forKey: UserDefaultsKeys.playbackMode)
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
        lastPlayedArticles = articles
        saveLastPlayedArticles()
    }
    
    // 保存当前播放位置
    private func saveCurrentPosition() {
        if let currentArticle = currentArticle {
            let key = UserDefaultsKeys.lastPlaybackTime(for: currentArticle.id)
            UserDefaults.standard.set(currentTime, forKey: key)
        }
    }
    
    // 保存播放状态
    private func savePlaybackState() {
        if let currentArticle = currentArticle {
            let key = UserDefaultsKeys.wasPlaying(for: currentArticle.id)
            UserDefaults.standard.set(isPlaying, forKey: key)
        }
    }
    
    // 保存播放位置
    private func savePlaybackPosition() {
        if let currentArticle = currentArticle {
            let key = UserDefaultsKeys.lastPlayTime(for: currentArticle.id)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        }
    }
    
    // 重置播放标志，供外部调用
    func resetPlaybackFlags() {
        isProcessingNextArticle = false
    }
    
    // 获取当前正在播放的文章
    func getCurrentArticle() -> Article? {
        if let article = currentArticle {
            print("SpeechManager.getCurrentArticle: 返回当前文章: \(article.title), ID: \(article.id)")
            return article
        } else if !lastPlayedArticles.isEmpty {
            print("SpeechManager.getCurrentArticle: 当前文章为nil，返回播放列表中的第一篇文章")
            return lastPlayedArticles.first
        }
        print("SpeechManager.getCurrentArticle: 没有可用的文章")
        return nil
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
}