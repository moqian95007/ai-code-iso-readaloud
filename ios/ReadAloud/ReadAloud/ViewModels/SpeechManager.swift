import SwiftUI
import AVFoundation
import MediaPlayer

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
    
    // 当前语音设置
    @Published var selectedRate: Double = UserDefaults.standard.object(forKey: UserDefaultsKeys.selectedRate) as? Double ?? 1.0
    @Published var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedVoiceIdentifier) ?? ""
    
    // 当前文章
    private var currentArticle: Article?
    private var currentText: String = ""
    
    // 计时器
    private var timer: Timer?
    
    private init() {
        synthesizer.delegate = speechDelegate
        
        // 配置音频会话
        setupAudioSession()
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
            self.pauseSpeaking()
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
        isResuming = false
        currentPlaybackPosition = 0
        currentProgress = 0.0
        currentTime = 0.0
        
        // 获取保存的播放位置
        if let articleId = currentArticle?.id {
            currentPlaybackPosition = UserDefaults.standard.integer(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
            currentProgress = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastProgress(for: articleId))
            currentTime = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
            let wasPlaying = UserDefaults.standard.bool(forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            
            isResuming = currentPlaybackPosition > 0
            
            // 更新进度条和时间显示，但不自动开始播放
            if isResuming {
                currentProgress = Double(currentPlaybackPosition) / Double(currentText.count)
                currentTime = totalTime * currentProgress
            }
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
    
    // 开始朗读
    func startSpeaking() {
        // 如果正在播放，先停止当前播放
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            speechDelegate.isSpeaking = false
            stopTimer()
        }
        
        // 重置进度和时间
        currentProgress = 0.0
        currentTime = 0.0
        
        // 重置起始位置为0
        speechDelegate.startPosition = 0
        
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
        // 如果正在播放，先停止当前播放
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            speechDelegate.isSpeaking = false
            stopTimer()
        }
        
        // 设置朗读起始位置
        speechDelegate.startPosition = position
        
        if let articleId = currentArticle?.id {
            // 记录播放开始的时间戳
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: UserDefaultsKeys.lastPlayTime(for: articleId))
            
            // 记录当前我们正在朗读这篇文章
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
        }
        
        if position < 0 || position >= currentText.count {
            startSpeaking()
            return
        }
        
        // 更新进度和时间
        currentProgress = Double(position) / Double(currentText.count)
        currentTime = totalTime * currentProgress
        
        // 获取从指定位置开始的子字符串
        let startIndex = currentText.index(currentText.startIndex, offsetBy: position)
        let subText = String(currentText[startIndex...])
        
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
        
        // 关联utterance和位置
        speechDelegate.setPosition(for: utterance, position: position)
        
        // 开始朗读
        synthesizer.speak(utterance)
        
        // 更新状态
        isPlaying = true
        
        // 更新锁屏界面信息
        updateNowPlayingInfo()
        
        // 开始定时器更新进度
        startTimer()
    }
    
    // 暂停朗读
    func pauseSpeaking() {
        if synthesizer.isSpeaking {
            let currentRange = speechDelegate.highlightRange
            currentPlaybackPosition = currentRange.location + currentRange.length
            isResuming = true
            
            // 停止计时器但保留当前进度
            stopTimer()
            
            // 保存当前播放进度
            savePlaybackProgress()
            
            // 暂停朗读
            synthesizer.stopSpeaking(at: .word)
            
            // 手动确保SpeechDelegate状态正确
            speechDelegate.isSpeaking = false
            
            // 更新状态
            isPlaying = false
            
            // 更新锁屏界面信息
            updateNowPlayingInfo()
            
            print("暂停朗读，当前位置：\(currentPlaybackPosition)，进度：\(currentProgress)")
        }
    }
    
    // 停止朗读
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            
            // 重置所有状态
            speechDelegate.isSpeaking = false
            speechDelegate.startPosition = 0
            isResuming = false
            currentPlaybackPosition = 0
            
            // 重置进度
            currentProgress = 0.0
            currentTime = 0.0
            
            // 更新状态
            isPlaying = false
            
            // 清除保存的播放进度
            if let articleId = currentArticle?.id {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition(for: articleId))
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress(for: articleId))
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackTime(for: articleId))
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying(for: articleId))
            }
            
            // 停止定时器
            stopTimer()
        }
    }
    
    // 跳转到指定进度
    func seekToProgress(_ progress: Double) {
        // 计算新位置
        let newPosition = Int(Double(currentText.count) * progress)
        
        // 根据播放状态决定是立即跳转还是只更新位置
        if isPlaying {
            stopSpeaking()
            startSpeakingFromPosition(newPosition)
        } else {
            currentPlaybackPosition = newPosition
            isResuming = true
            currentProgress = progress
            currentTime = totalTime * progress
            
            // 保存更新后的播放进度
            savePlaybackProgress()
        }
    }
    
    // 后退指定秒数
    func skipBackward(seconds: TimeInterval) {
        // 计算新的时间点，确保不小于0
        let newTime = max(currentTime - seconds, 0)
        // 计算新的进度
        let newProgress = newTime / totalTime
        // 计算对应的文本位置
        let newPosition = Int(Double(currentText.count) * newProgress)
        
        print("后退\(seconds)秒，新时间：\(newTime)，新位置：\(newPosition)")
        
        // 如果正在播放，则停止当前朗读并从新位置开始
        if isPlaying {
            stopSpeaking()
            
            // 更新UI和状态
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = newPosition
            isResuming = true
            
            // 立即从新位置开始播放
            startSpeakingFromPosition(newPosition)
        } else {
            // 仅更新位置
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = newPosition
            isResuming = true
            
            // 保存进度
            savePlaybackProgress()
        }
    }
    
    // 前进指定秒数
    func skipForward(seconds: TimeInterval) {
        // 计算新的时间点
        let newTime = min(currentTime + seconds, totalTime)
        // 计算新的进度
        let newProgress = newTime / totalTime
        // 计算对应的文本位置
        let newPosition = Int(Double(currentText.count) * newProgress)
        
        print("前进\(seconds)秒，新时间：\(newTime)，新位置：\(newPosition)")
        
        // 如果正在播放，则停止当前朗读并从新位置开始
        if isPlaying {
            stopSpeaking()
            
            // 更新UI和状态
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = newPosition
            isResuming = true
            
            // 立即从新位置开始播放
            startSpeakingFromPosition(newPosition)
        } else {
            // 仅更新位置
            currentTime = newTime
            currentProgress = newProgress
            currentPlaybackPosition = newPosition
            isResuming = true
            
            // 保存进度
            savePlaybackProgress()
        }
    }
    
    // 应用新的语速设置
    func applyNewSpeechRate() {
        // 保存设置
        UserDefaults.standard.set(selectedRate, forKey: UserDefaultsKeys.selectedRate)
        
        // 如果正在朗读，需要停止并重新开始
        if isPlaying {
            // 保存当前位置
            let currentPosition = speechDelegate.highlightRange.location
            
            // 停止当前朗读
            synthesizer.stopSpeaking(at: .immediate)
            
            // 从保存的位置以新的语速开始朗读
            startSpeakingFromPosition(currentPosition)
        }
    }
    
    // 应用新的语音设置
    func applyNewVoice() {
        // 保存设置
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: UserDefaultsKeys.selectedVoiceIdentifier)
        
        // 如果正在朗读，需要停止并重新开始
        if isPlaying {
            // 保存当前位置
            let currentPosition = speechDelegate.highlightRange.location
            
            // 停止当前朗读
            synthesizer.stopSpeaking(at: .immediate)
            
            // 从保存的位置以新的语音开始朗读
            startSpeakingFromPosition(currentPosition)
        }
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
                    self.currentProgress = Double(currentPosition) / Double(self.currentText.count)
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
}