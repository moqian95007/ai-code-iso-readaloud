import SwiftUI
import AVFoundation

/**
 * SpeechDelegate类负责监控语音合成过程
 * 通过实现AVSpeechSynthesizerDelegate协议，可以接收语音合成器的各种事件通知
 */
class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    // 单例模式，便于全局访问
    static let shared = SpeechDelegate()
    
    // 发布当前朗读范围，供UI更新使用
    @Published var highlightRange: NSRange = NSRange(location: 0, length: 0)
    
    // 添加一个标志变量，表示是否正在朗读
    @Published var isSpeaking: Bool = false
    
    // 添加起始位置偏移量
    var startPosition: Int = 0
    
    // 添加一个字典，用于存储utterance与起始位置的对应关系
    private var utterancePositions: [AVSpeechUtterance: Int] = [:]
    
    // 设置utterance的起始位置
    func setPosition(for utterance: AVSpeechUtterance, position: Int) {
        utterancePositions[utterance] = position
    }
    
    // 语音开始朗读时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("开始朗读，起始位置: \(startPosition)")
        // 设置正在朗读标志
        isSpeaking = true
    }
    
    // 语音朗读完成时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("完成朗读")
        // 重置正在朗读标志
        isSpeaking = false
        // 重置高亮范围
        highlightRange = NSRange(location: 0, length: 0)
        // 重置起始位置
        startPosition = 0
    }
    
    // 语音朗读被取消时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("取消朗读")
        isSpeaking = false
        highlightRange = NSRange(location: 0, length: 0)
        // 不重置startPosition以便恢复播放
    }
    
    // 朗读到文本的特定部分时调用，用于文本高亮显示
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let position = utterancePositions[utterance] ?? 0
        print("正在朗读部分文本: \(characterRange), 起始位置: \(position)")
        
        let adjustedRange = NSRange(
            location: characterRange.location + position,
            length: characterRange.length
        )
        
        highlightRange = adjustedRange
    }
} 