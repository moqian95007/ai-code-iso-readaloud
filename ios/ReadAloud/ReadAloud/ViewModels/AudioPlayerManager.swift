import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// 音频播放管理器
class AudioPlayerManager: NSObject, ObservableObject {
    // 单例
    static let shared = AudioPlayerManager()
    
    // 当前播放器
    private var audioPlayer: AVAudioPlayer?
    
    // 播放状态
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var progress: Float = 0
    
    // 播放器更新计时器
    private var updateTimer: Timer?
    
    // 播放配置
    private(set) var currentAudioURL: URL?
    private(set) var currentTitle: String = ""
    private(set) var currentArtist: String = ""
    
    // 播放控制
    var playbackRate: Float = 1.0 {
        didSet {
            audioPlayer?.rate = playbackRate
            updateNowPlayingInfo()
        }
    }
    
    // 初始化
    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteTransportControls()
    }
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            print("音频播放会话设置成功")
        } catch {
            print("设置音频会话失败：\(error)")
        }
    }
    
    // 设置远程控制
    private func setupRemoteTransportControls() {
        // 确保能接收远程控制事件
        UIApplication.shared.beginReceivingRemoteControlEvents()
        
        // 获取远程控制中心
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 移除所有现有的目标
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.seekForwardCommand.removeTarget(nil)
        commandCenter.seekBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        // 播放
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("收到远程播放命令")
            self.play()
            return .success
        }
        
        // 暂停
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("收到远程暂停命令")
            self.pause()
            return .success
        }
        
        // 切换播放/暂停
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("收到切换播放/暂停命令")
            self.isPlaying ? self.pause() : self.play()
            return .success
        }
        
        // 前进/后退
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self,
                  let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            print("收到前进命令：\(skipEvent.interval)秒")
            self.seek(to: self.currentTime + skipEvent.interval)
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self,
                  let skipEvent = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            print("收到后退命令：\(skipEvent.interval)秒")
            self.seek(to: self.currentTime - skipEvent.interval)
            return .success
        }
        
        // 拖动进度条
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            print("收到拖动进度命令：\(positionEvent.positionTime)秒")
            self.seek(to: positionEvent.positionTime)
            return .success
        }
        
        print("远程控制设置完成")
    }
    
    // 播放音频文件
    func playAudio(url: URL, title: String, artist: String) {
        // 如果正在播放，先停止
        if isPlaying {
            stopPlayback()
        }
        
        print("准备播放音频文件：\(url.lastPathComponent)")
        
        do {
            // 创建音频播放器
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackRate
            audioPlayer?.prepareToPlay()
            
            // 保存当前播放信息
            currentAudioURL = url
            currentTitle = title
            currentArtist = artist
            duration = audioPlayer?.duration ?? 0
            
            // 开始播放
            play()
            
            print("音频播放器初始化成功，时长：\(duration)秒")
        } catch {
            print("创建音频播放器失败：\(error)")
        }
    }
    
    // 开始播放
    func play() {
        guard let player = audioPlayer, !isPlaying else { return }
        
        setupAudioSession()
        
        player.play()
        isPlaying = true
        
        // 启动更新计时器
        startUpdateTimer()
        
        // 更新控制中心信息
        updateNowPlayingInfo()
        
        print("开始播放音频")
    }
    
    // 暂停播放
    func pause() {
        guard let player = audioPlayer, isPlaying else { return }
        
        player.pause()
        isPlaying = false
        
        // 停止更新计时器
        stopUpdateTimer()
        
        // 更新控制中心信息
        updateNowPlayingInfo()
        
        print("暂停播放音频")
    }
    
    // 停止播放
    func stopPlayback() {
        guard let player = audioPlayer else { return }
        
        player.stop()
        isPlaying = false
        
        // 停止更新计时器
        stopUpdateTimer()
        
        // 重置播放位置
        player.currentTime = 0
        currentTime = 0
        progress = 0
        
        // 清除控制中心信息
        clearNowPlayingInfo()
        
        print("停止播放音频")
    }
    
    // 跳转到指定位置
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        
        // 确保时间在有效范围内
        let safeTime = max(0, min(time, duration))
        player.currentTime = safeTime
        
        // 更新状态
        currentTime = safeTime
        progress = Float(currentTime / duration)
        
        // 更新控制中心信息
        updateNowPlayingInfo()
        
        print("跳转到\(safeTime)秒")
    }
    
    // 更新控制中心信息
    private func updateNowPlayingInfo() {
        guard let player = audioPlayer else { return }
        
        print("更新控制中心音频信息")
        
        // 创建信息字典
        var nowPlayingInfo = [String: Any]()
        
        // 设置标题和详情
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentArtist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "ReadAloud朗读器"
        
        // 设置总时长和当前播放位置
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // 设置播放速率
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        // 设置媒体类型
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        
        // 添加封面图片
        if let image = UIImage(named: "AppIcon") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        // 应用信息到控制中心
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // 清除控制中心信息
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    // 启动更新计时器
    private func startUpdateTimer() {
        stopUpdateTimer()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updatePlaybackInfo()
        }
    }
    
    // 停止更新计时器
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // 更新播放信息
    private func updatePlaybackInfo() {
        guard let player = audioPlayer else { return }
        
        currentTime = player.currentTime
        progress = duration > 0 ? Float(currentTime / duration) : 0
        
        // 每5秒更新一次控制中心信息
        if Int(currentTime) % 5 == 0 {
            updateNowPlayingInfo()
        }
    }
    
    // 释放资源
    deinit {
        stopUpdateTimer()
        stopPlayback()
        UIApplication.shared.endReceivingRemoteControlEvents()
        print("AudioPlayerManager已释放")
    }
}

// 扩展为AVAudioPlayerDelegate
extension AudioPlayerManager: AVAudioPlayerDelegate {
    // 播放结束
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("音频播放结束，成功：\(flag)")
        
        // 更新状态
        isPlaying = false
        
        // 停止更新计时器
        stopUpdateTimer()
        
        // 更新控制中心
        updateNowPlayingInfo()
        
        // 发送完成通知
        NotificationCenter.default.post(name: NSNotification.Name("AudioPlaybackFinished"), object: nil)
    }
    
    // 播放出错
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("音频解码错误：\(error?.localizedDescription ?? "未知错误")")
        
        // 更新状态
        isPlaying = false
        
        // 停止更新计时器
        stopUpdateTimer()
        
        // 清除控制中心
        clearNowPlayingInfo()
        
        // 发送错误通知
        NotificationCenter.default.post(name: NSNotification.Name("AudioPlaybackError"), object: error)
    }
} 