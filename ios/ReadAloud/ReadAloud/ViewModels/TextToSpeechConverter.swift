import Foundation
import AVFoundation
import Combine

class TextToSpeechConverter: NSObject {
    // 单例
    static let shared = TextToSpeechConverter()
    
    // 语音合成器
    private let synthesizer = AVSpeechSynthesizer()
    
    // 音频引擎 - 用于捕获语音合成的输出
    private let audioEngine = AVAudioEngine()
    
    // 当前正在合成状态
    private var isConverting = false
    
    // 生成的音频文件路径
    private var audioFilePath: URL?
    
    // 合成完成回调
    private var completionHandler: ((URL?) -> Void)?
    
    // 缓存文件夹
    private let cacheDirectory: URL
    
    // 进度和状态发布者
    private let progressSubject = PassthroughSubject<Float, Never>()
    var progressPublisher: AnyPublisher<Float, Never> {
        return progressSubject.eraseToAnyPublisher()
    }
    
    // 初始化
    override private init() {
        // 获取缓存目录
        let tempDir = FileManager.default.temporaryDirectory
        self.cacheDirectory = tempDir.appendingPathComponent("AudioCache", isDirectory: true)
        
        super.init()
        
        // 创建缓存目录
        createCacheDirectoryIfNeeded()
        
        // 设置代理
        synthesizer.delegate = self
    }
    
    // 确保缓存目录存在
    private func createCacheDirectoryIfNeeded() {
        do {
            if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                print("创建音频缓存目录：\(cacheDirectory.path)")
            }
        } catch {
            print("创建缓存目录失败：\(error)")
        }
    }
    
    // 清理旧的缓存文件
    func cleanupOldCacheFiles() {
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.creationDateKey])
            
            // 保留最近24小时内的文件
            let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)
            
            for file in files {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let creationDate = attributes[.creationDate] as? Date,
                   creationDate < cutoffDate {
                    try fileManager.removeItem(at: file)
                    print("删除过期音频缓存：\(file.lastPathComponent)")
                }
            }
        } catch {
            print("清理缓存失败：\(error)")
        }
    }
    
    // 将文本转换为音频文件
    func convertTextToSpeech(text: String, voice: AVSpeechSynthesisVoice? = nil, rate: Float = 0.5, completion: @escaping (URL?) -> Void) {
        // 如果正在合成，取消
        if isConverting {
            stopConversion()
        }
        
        // 设置合成状态和回调
        isConverting = true
        completionHandler = completion
        
        // 生成唯一的文件名
        let fileName = "speech_\(UUID().uuidString).m4a"
        audioFilePath = cacheDirectory.appendingPathComponent(fileName)
        
        guard let audioFilePath = audioFilePath else {
            print("无法创建音频文件路径")
            completion(nil)
            return
        }
        
        // 检查文件是否已存在
        if FileManager.default.fileExists(atPath: audioFilePath.path) {
            print("音频文件已存在，直接返回：\(audioFilePath.path)")
            completion(audioFilePath)
            return
        }
        
        // 设置音频会话
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers, .allowAirPlay])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("设置音频会话失败：\(error)")
            completion(nil)
            return
        }
        
        // 配置音频引擎
        configureAudioEngine(outputFile: audioFilePath)
        
        // 创建语音合成请求
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 开始音频引擎
        do {
            try audioEngine.start()
            
            // 开始合成
            synthesizer.speak(utterance)
            print("开始合成音频，文本长度：\(text.count)字符")
            
            // 发送初始进度
            progressSubject.send(0.0)
        } catch {
            print("启动音频引擎失败：\(error)")
            audioEngine.reset()
            completion(nil)
            isConverting = false
        }
    }
    
    // 配置音频引擎
    private func configureAudioEngine(outputFile: URL) {
        // 重置引擎
        audioEngine.reset()
        
        // 设置音频格式
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        
        // 创建音频文件
        let audioFile = try! AVAudioFile(forWriting: outputFile, settings: recordingFormat.settings)
        
        // 获取主混音器节点
        let mainMixer = audioEngine.mainMixerNode
        
        // 创建一个格式转换器节点用于语音合成
        let formatConverter = AVAudioMixerNode()
        audioEngine.attach(formatConverter)
        
        // 将节点连接到音频引擎中
        audioEngine.connect(formatConverter, to: mainMixer, format: recordingFormat)
        
        // 安装录音回调
        mainMixer.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, time in
            try? audioFile.write(from: buffer)
        }
    }
    
    // 停止转换
    func stopConversion() {
        if isConverting {
            // 停止合成
            synthesizer.stopSpeaking(at: .immediate)
            
            // 停止音频引擎
            audioEngine.stop()
            audioEngine.reset()
            
            // 重置状态
            isConverting = false
            audioFilePath = nil
            completionHandler = nil
            
            print("已停止音频合成")
        }
    }
    
    // 获取文本对应的音频文件，如果没有则创建
    func getAudioFileForText(text: String, voice: AVSpeechSynthesisVoice? = nil, rate: Float = 0.5, completion: @escaping (URL?) -> Void) {
        // 生成文本的哈希值作为文件名
        let textHash = String(text.hash)
        let voiceId = voice?.identifier ?? "default"
        let rateStr = String(format: "%.1f", rate)
        let fileName = "speech_\(textHash)_\(voiceId)_\(rateStr).m4a"
        
        let filePath = cacheDirectory.appendingPathComponent(fileName)
        
        // 检查缓存中是否已存在
        if FileManager.default.fileExists(atPath: filePath.path) {
            print("使用缓存音频文件：\(fileName)")
            completion(filePath)
            return
        }
        
        // 如果不存在，转换并创建
        print("缓存中没有找到音频文件，开始合成：\(fileName)")
        convertTextToSpeech(text: text, voice: voice, rate: rate, completion: completion)
    }
}

// 扩展为AVSpeechSynthesizerDelegate
extension TextToSpeechConverter: AVSpeechSynthesizerDelegate {
    // 开始朗读
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("开始合成语音")
    }
    
    // 朗读完成一个单词
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // 计算进度
        let progress = Float(characterRange.location + characterRange.length) / Float(utterance.speechString.count)
        progressSubject.send(progress)
    }
    
    // 朗读结束
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("语音合成完成")
        
        // 停止音频引擎
        audioEngine.stop()
        audioEngine.reset()
        
        // 发送完成进度
        progressSubject.send(1.0)
        
        // 调用完成回调
        DispatchQueue.main.async {
            self.isConverting = false
            self.completionHandler?(self.audioFilePath)
            self.completionHandler = nil
        }
    }
    
    // 朗读取消
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("语音合成取消")
        
        // 停止音频引擎
        audioEngine.stop()
        audioEngine.reset()
        
        // 重置状态
        isConverting = false
        
        // 调用完成回调，返回nil表示失败
        DispatchQueue.main.async {
            self.completionHandler?(nil)
            self.completionHandler = nil
        }
    }
} 