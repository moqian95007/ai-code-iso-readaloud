import Foundation
import AVFoundation
import UIKit

/**
 * AudioFileManager类负责音频文件的生成和管理
 * 真正生成物理音频文件，然后再播放
 */
class AudioFileManager: NSObject, AVAudioPlayerDelegate {
    // 单例模式，便于全局访问
    static let shared = AudioFileManager()
    
    // 音频播放器
    var audioPlayer: AVAudioPlayer?
    
    // 回调处理
    private var completionHandler: (() -> Void)?
    
    // 标记播放状态
    private(set) var isPlaying = false
    
    // 音频文件目录
    private let audioDirectory: URL
    
    // 添加音频生成进度
    @Published var generationProgress: Float = 0.0
    
    // 初始化
    private override init() {
        // 获取应用程序的文档目录，确保文件可持久保存
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        // 创建一个子目录用于存储音频文件
        audioDirectory = documentsDirectory.appendingPathComponent("ReadAloudAudio", isDirectory: true)
        
        super.init()
        
        // 确保音频目录存在
        createAudioDirectoryIfNeeded()
        
        // 设置音频会话
        setupAudioSession()
    }
    
    // 创建音频目录
    private func createAudioDirectoryIfNeeded() {
        do {
            if !FileManager.default.fileExists(atPath: audioDirectory.path) {
                try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
                print("创建音频目录：\(audioDirectory.path)")
            }
        } catch {
            print("创建音频目录失败：\(error.localizedDescription)")
        }
    }
    
    // 设置音频会话
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("设置音频会话失败：\(error.localizedDescription)")
        }
    }
    
    // 生成音频文件
    func generateAudioFile(from text: String, 
                           voice: AVSpeechSynthesisVoice?, 
                           rate: Float, 
                           uniqueID: String, 
                           completion: @escaping (URL?) -> Void) {
        
        print("开始生成音频文件...")
        
        // 重置进度
        generationProgress = 0.0
        
        // 清理旧文件
        cleanupOldAudioFiles()
        
        // 创建文件URL - 使用WAV格式
        let fileName = "readaloud_\(uniqueID).wav"
        let fileURL = audioDirectory.appendingPathComponent(fileName)
        
        // 检查文件是否已存在
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("音频文件已存在，直接返回：\(fileURL.path)")
            completion(fileURL)
            return
        }
        
        // 使用AVAudioEngine方法生成音频文件
        generateWithAVAudioEngine(text: text, voice: voice, rate: rate, outputURL: fileURL, completion)
    }
    
    // 清理旧音频文件
    private func cleanupOldAudioFiles() {
        do {
            let fileManager = FileManager.default
            let fileURLs = try fileManager.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)
            
            // 获取当前日期
            let currentDate = Date()
            
            for fileURL in fileURLs {
                // 获取文件属性
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let creationDate = attributes[.creationDate] as? Date {
                    // 如果文件创建时间超过一天，则删除
                    if currentDate.timeIntervalSince(creationDate) > (24 * 60 * 60) {
                        try fileManager.removeItem(at: fileURL)
                        print("删除过期音频文件：\(fileURL.lastPathComponent)")
                    }
                }
            }
        } catch {
            print("清理音频文件失败：\(error.localizedDescription)")
        }
    }
    
    // 使用AVAudioEngine方法生成音频文件
    private func generateWithAVAudioEngine(text: String, voice: AVSpeechSynthesisVoice?, rate: Float, outputURL: URL, _ completion: @escaping (URL?) -> Void) {
        print("使用AVAudioEngine方法生成音频文件")
        
        // 设置音频会话为录制模式
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
            try audioSession.setActive(true)
        } catch {
            print("设置音频会话失败：\(error)")
            completion(nil)
            return
        }
        
        // 设置音频引擎和音频节点
        let engine = AVAudioEngine()
        let mixer = engine.mainMixerNode
        
        // 创建一个标准的PCM音频格式
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        
        guard let format = outputFormat else {
            print("创建音频格式失败")
            completion(nil)
            return
        }
        
        // 为输出文件设置格式（使用PCM编码，比AAC更简单且兼容性更好）
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        // 创建输出文件
        var audioFile: AVAudioFile?
        do {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
            print("成功创建音频文件写入对象")
        } catch {
            print("创建音频文件失败：\(error)")
            completion(nil)
            return
        }
        
        // 安装tap以捕获音频数据
        mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { (buffer, time) in
            do {
                try audioFile?.write(from: buffer)
            } catch {
                print("写入音频数据失败：\(error)")
            }
        }
        
        // 启动引擎
        do {
            try engine.start()
            print("音频引擎启动成功")
        } catch {
            print("启动音频引擎失败：\(error)")
            completion(nil)
            return
        }
        
        // 创建语音合成器
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        
        // 设置语音参数
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate
        utterance.volume = 1.0
        
        print("准备使用语音合成器将语音写入音频文件")
        
        // 监听语音合成进度
        var totalChunks = max(1, text.count / 100) // 估计的总块数
        var processedChunks = 0
        
        // 定期更新进度的定时器
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            processedChunks += 1
            let progress = min(Float(processedChunks) / Float(totalChunks), 0.95)
            self.generationProgress = progress
            
            // 如果进度达到95%，停止定时器
            if progress >= 0.95 {
                timer.invalidate()
            }
        }
        
        // 使用完成处理程序而不是通知
        synthesizer.delegate = nil
        
        // 开始语音合成
        print("开始语音合成写入音频文件")
        synthesizer.speak(utterance)
        
        // 检查语音合成进度，并在完成时处理结果
        let checkInterval: TimeInterval = 0.5
        var checkTimer: Timer?
        
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { timer in
            // 检查语音合成器是否已完成
            if !synthesizer.isSpeaking {
                // 停止定时器
                timer.invalidate()
                checkTimer = nil
                progressTimer.invalidate()
                
                // 停止录制
                mixer.removeTap(onBus: 0)
                engine.stop()
                
                // 重置音频会话
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("重置音频会话失败：\(error)")
                }
                
                // 检查文件是否成功生成
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                        if let fileSize = attributes[.size] as? NSNumber, fileSize.intValue > 1000 {
                            print("音频文件成功生成，大小：\(fileSize)字节")
                            self.generationProgress = 1.0
                            
                            // 验证文件是否可以播放
                            do {
                                let testPlayer = try AVAudioPlayer(contentsOf: outputURL)
                                print("验证生成的文件可播放，时长：\(testPlayer.duration)秒")
                                
                                if testPlayer.duration > 0.1 {
                                    completion(outputURL)
                                } else {
                                    print("生成的文件时长异常（\(testPlayer.duration)秒），可能无法播放")
                                    completion(nil)
                                }
                            } catch {
                                print("生成的文件无法播放：\(error.localizedDescription)")
                                completion(nil)
                            }
                        } else {
                            print("音频文件生成但大小异常：\(attributes[.size] ?? 0)字节")
                            completion(nil)
                        }
                    } catch {
                        print("获取文件属性失败：\(error)")
                        completion(nil)
                    }
                } else {
                    print("音频文件未能成功创建")
                    completion(nil)
                }
            }
        }
    }
    
    // 播放音频文件
    func playAudioFile(url: URL, completion: (() -> Void)? = nil) {
        print("准备播放音频文件：\(url.path)")
        
        // 停止当前播放
        stopPlayback()
        
        do {
            // 确认文件存在
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("文件不存在: \(url.path)")
                if let handler = completion {
                    handler()
                }
                return
            }
            
            // 检查文件大小
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int ?? 0
            print("音频文件大小: \(fileSize)字节")
            
            if fileSize < 1000 {
                print("警告：音频文件过小，可能无法正常播放")
            }
            
            // 设置音频会话
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
                try audioSession.setActive(true)
            } catch {
                print("设置音频会话失败: \(error)")
            }
            
            // 创建音频播放器
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            // 保存完成回调
            completionHandler = completion
            
            // 更新播放状态
            isPlaying = true
            
        } catch {
            print("播放音频文件失败：\(error.localizedDescription)")
            if let handler = completion {
                handler()
            }
        }
    }
    
    // 暂停播放
    func pausePlayback() {
        guard isPlaying, let player = audioPlayer else { return }
        
        player.pause()
        isPlaying = false
    }
    
    // 恢复播放
    func resumePlayback() {
        guard !isPlaying, let player = audioPlayer else { return }
        
        player.play()
        isPlaying = true
    }
    
    // 停止播放
    func stopPlayback() {
        guard let player = audioPlayer else { return }
        
        player.stop()
        audioPlayer = nil
        isPlaying = false
    }
    
    // 获取当前播放进度
    func getCurrentTime() -> TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }
    
    // 获取总时长
    func getDuration() -> TimeInterval {
        return audioPlayer?.duration ?? 0
    }
    
    // 获取播放进度比例
    func getProgress() -> Float {
        guard let player = audioPlayer, player.duration > 0 else { return 0 }
        return Float(player.currentTime / player.duration)
    }
    
    // 设置播放位置
    func setPlaybackPosition(_ position: TimeInterval) {
        guard let player = audioPlayer else { return }
        
        player.currentTime = min(max(0, position), player.duration)
        
        // 如果当前暂停状态，不要自动恢复播放
        if !isPlaying {
            player.prepareToPlay()
        }
    }
    
    // AVAudioPlayerDelegate 方法
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("音频播放完成")
        
        // 更新状态
        isPlaying = false
        
        // 调用完成回调
        if let handler = completionHandler {
            handler()
            completionHandler = nil
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("音频播放解码错误：\(error?.localizedDescription ?? "未知错误")")
        
        // 更新状态
        isPlaying = false
        
        // 调用完成回调
        if let handler = completionHandler {
            handler()
            completionHandler = nil
        }
    }
} 