import Foundation
import AVFoundation
import Combine

class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isPlaying = false
    @Published var currentPosition: Double = 0.0
    @Published var currentText: String = ""
    
    private var synthesizer = AVSpeechSynthesizer()
    public var fullText: String = ""
    private var utterance: AVSpeechUtterance?
    private var document: Document?
    private var documentViewModel: DocumentsViewModel?
    
    // 语音选项
    var voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "zh-CN")
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var volume: Float = 1.0
    var pitchMultiplier: Float = 1.0
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            // 配置音频会话
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("音频会话配置成功")
        } catch {
            print("音频会话配置失败: \(error.localizedDescription)")
        }
    }
    
    func loadDocument(_ document: Document, viewModel: DocumentsViewModel) {
        self.document = document
        self.documentViewModel = viewModel
        
        // 使用异步处理避免阻塞UI线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let extractedText = try TextExtractor.extractText(from: document)
                
                DispatchQueue.main.async {
                    self.fullText = extractedText
                    
                    // 重置朗读进度
                    self.currentPosition = document.progress
                    
                    // 更新当前显示的文本段落
                    self.updateCurrentTextDisplay()
                }
            } catch let extractionError as TextExtractor.ExtractionError {
                DispatchQueue.main.async {
                    self.currentText = "文本提取失败: \(extractionError.localizedDescription)"
                    print("文本提取失败: \(extractionError)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.currentText = "文本提取失败: \(error.localizedDescription)"
                    print("文本提取失败: \(error)")
                }
            }
        }
    }
    
    public func updateCurrentTextDisplay() {
        // 根据当前进度定位到文本相应位置
        if !fullText.isEmpty {
            let startIndex = fullText.index(fullText.startIndex, offsetBy: min(Int(Double(fullText.count) * currentPosition), fullText.count - 1))
            let previewLength = min(500, fullText.count - fullText.distance(from: fullText.startIndex, to: startIndex))
            let endIndex = fullText.index(startIndex, offsetBy: previewLength)
            
            currentText = String(fullText[startIndex..<endIndex])
        }
    }
    
    func startSpeaking(from position: Double? = nil) {
        // 停止当前朗读
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // 设置朗读位置
        if let pos = position {
            currentPosition = pos
        }
        
        // 检查文本是否为空
        if fullText.isEmpty {
            print("⚠️ 无法朗读：文本为空")
            return
        }
        
        // 根据位置获取开始朗读的文本
        let startOffset = Int(Double(fullText.count) * currentPosition)
        let textToSpeak = fullText.count > startOffset ? String(fullText[fullText.index(fullText.startIndex, offsetBy: startOffset)...]) : ""
        
        if textToSpeak.isEmpty {
            print("⚠️ 无法朗读：截取的文本为空")
            return
        }
        
        print("🔊 开始朗读，文本长度: \(textToSpeak.count)，起始位置: \(currentPosition)")
        
        // 创建朗读对象
        utterance = AVSpeechUtterance(string: textToSpeak)
        
        // 设置语音和参数
        if let voice = AVSpeechSynthesisVoice(language: "zh-CN") {
            utterance?.voice = voice
            print("✓ 设置语音: \(voice.language)")
        } else {
            print("⚠️ 无法设置中文语音，使用默认语音")
        }
        
        // 调整参数，使声音更明显
        utterance?.rate = min(max(0.4, rate), 0.6) // 调整速率到0.4-0.6之间
        utterance?.volume = 1.0 // 设置最大音量
        utterance?.pitchMultiplier = 1.0 // 默认音调
        
        print("✓ 语音参数: 速率=\(utterance?.rate ?? 0), 音量=\(utterance?.volume ?? 0), 音调=\(utterance?.pitchMultiplier ?? 0)")
        
        // 开始朗读
        if let utterance = utterance {
            synthesizer.speak(utterance)
            isPlaying = true
            print("✓ 已发送朗读命令")
        } else {
            print("⚠️ 创建朗读utterance失败")
        }
        
        updateCurrentTextDisplay()
    }
    
    func pauseSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPlaying = false
        }
    }
    
    func resumeSpeaking() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPlaying = true
        } else if !isPlaying && !fullText.isEmpty {
            // 如果没有暂停但也没有在播放，而且有内容，则开始播放
            startSpeaking(from: currentPosition)
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        
        // 保存阅读进度
        saveProgress()
    }
    
    func setPlaybackRate(_ rate: Float) {
        self.rate = rate
        // 应用到当前朗读
        if let currentUtterance = utterance {
            currentUtterance.rate = rate
        }
    }
    
    func skipForward() {
        // 向前跳过一小段
        currentPosition = min(1.0, currentPosition + 0.01)
        if isPlaying {
            startSpeaking(from: currentPosition)
        } else {
            updateCurrentTextDisplay()
        }
    }
    
    func skipBackward() {
        // 向后跳过一小段
        currentPosition = max(0.0, currentPosition - 0.01)
        if isPlaying {
            startSpeaking(from: currentPosition)
        } else {
            updateCurrentTextDisplay()
        }
    }
    
    func seekTo(position: Double) {
        currentPosition = max(0.0, min(1.0, position))
        if isPlaying {
            startSpeaking(from: currentPosition)
        } else {
            updateCurrentTextDisplay()
        }
    }
    
    private func saveProgress() {
        if let doc = document, let viewModel = documentViewModel {
            viewModel.updateDocumentProgress(id: doc.id, progress: currentPosition)
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            print("�� 开始朗读文本")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            print("✓ 朗读完成")
            
            // 标记为已完成
            if utterance.speechString == self.fullText {
                self.currentPosition = 1.0
            }
            
            // 保存阅读进度
            self.saveProgress()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            print("⏸ 朗读暂停")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            print("▶️ 朗读继续")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // 更新朗读进度
            let progress = Double(characterRange.location) / Double(utterance.speechString.count)
            let overallProgress = self.currentPosition + progress * (1.0 - self.currentPosition)
            
            self.currentPosition = overallProgress
            
            // 更新当前显示的文本
            self.updateCurrentTextDisplay()
        }
    }
} 