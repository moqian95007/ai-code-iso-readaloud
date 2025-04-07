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
    
    // 添加结束原因标志，区分自然结束和用户暂停
    @Published var wasManuallyPaused: Bool = false
    
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
        
        // 重置手动暂停标志
        wasManuallyPaused = false
        
        // 确保SpeechManager知道我们已经开始朗读
        let manager = SpeechManager.shared
        let playbackManager = PlaybackManager.shared
        
        // 同步更新本地和全局状态
        if !manager.isPlaying {
            print("检测到AVSpeechSynthesizer开始播放，同步更新SpeechManager状态")
            manager.isPlaying = true
            manager.objectWillChange.send()
        }
        
        // 同步全局播放状态 - 确保与本地状态一致
        if !playbackManager.isPlaying && manager.isPlaying {
            if let article = manager.getCurrentArticle() {
                print("检测到AVSpeechSynthesizer开始播放，同步更新PlaybackManager状态")
                let contentType: PlaybackContentType = article.id.description.hasPrefix("doc-") ? .document : .article
                playbackManager.startPlayback(contentId: article.id, title: article.title, type: contentType)
            }
        }
    }
    
    // 语音朗读完成时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("语音合成器完成朗读")
        print("是否为手动暂停: \(wasManuallyPaused)")
        print("起始位置: \(startPosition)")
        
        // 获取SpeechManager以更新进度
        let manager = SpeechManager.shared
        let playbackManager = PlaybackManager.shared
        
        // 重置正在朗读标志
        isSpeaking = false
        
        // 同步更新UI状态
        if manager.isPlaying {
            print("检测到合成器完成播放，但SpeechManager状态未更新，正在同步...")
            manager.isPlaying = false
            manager.objectWillChange.send()
        }
        
        // 同步全局播放状态
        if playbackManager.isPlaying {
            print("检测到合成器完成播放，但PlaybackManager状态未更新，正在同步...")
            playbackManager.stopPlayback()
        }
        
        // 检查是否是从中间位置开始的播放
        let isStartedFromMiddle = startPosition > 0
        
        // 检查是否朗读的文本过短（增加阈值，解决短文本导致的问题）
        let utteranceText = utterance.speechString
        let isShortUtterance = utteranceText.count < 50 // 增加阈值从10到50
        
        // 获取文本总长度
        let textLength = manager.currentTextCount
        
        // 检查是否从接近文章末尾开始播放
        let isNearEnd = startPosition > (textLength * 9 / 10) // 如果位于文章最后10%位置
        
        // 如果是自然播放结束（非手动暂停）
        if !wasManuallyPaused {
            // 将高亮范围设置到末尾
            highlightRange = NSRange(location: textLength, length: 0)
            
            // 改进的检测逻辑 - 处理接近末尾和短文本情况
            if (isShortUtterance && isStartedFromMiddle) || isNearEnd {
                print("检测到特殊情况：短文本播放或接近文章末尾")
                print("短文本: \(isShortUtterance), 接近末尾: \(isNearEnd)")
                
                // 防止无限循环，设置为手动暂停模式
                wasManuallyPaused = true
                
                // 如果是循环模式，立即把位置重置到文章开头，避免从末尾短文本连续播放
                if manager.playbackMode == .singleRepeat || manager.playbackMode == .listRepeat {
                    print("是循环模式，重置到文章开头")
                    startPosition = 0
                }
                
                // 延迟发送完成通知，让UI有时间更新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("延迟触发完成事件，防止无限循环问题")
                    NotificationCenter.default.post(name: Notification.Name("SpeechFinished"), object: nil)
                }
            } else {
                // 正常情况下，直接发送朗读完成通知
                NotificationCenter.default.post(name: Notification.Name("SpeechFinished"), object: nil)
            }
        } else {
            // 如果是手动暂停，则不发送完成通知，以避免触发循环播放
            // 但不要重置wasManuallyPaused，让SpeechManager来决定何时重置它
            print("手动暂停，不触发SpeechFinished事件")
        }
    }
    
    // 语音朗读被取消时调用
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("取消朗读")
        isSpeaking = false
        
        // 表示这是由用户主动取消的
        wasManuallyPaused = true
        
        // 同步SpeechManager和PlaybackManager状态
        let manager = SpeechManager.shared
        let playbackManager = PlaybackManager.shared
        
        // 同步更新SpeechManager状态
        if manager.isPlaying {
            print("检测到合成器取消播放，同步更新SpeechManager状态")
            manager.isPlaying = false
            manager.objectWillChange.send()
        }
        
        // 同步全局播放状态
        if playbackManager.isPlaying {
            print("检测到合成器取消播放，同步更新PlaybackManager状态")
            playbackManager.stopPlayback()
        }
        
        // 不要重置高亮范围和起始位置，以便能够在单篇循环模式下正确恢复
        // highlightRange = NSRange(location: 0, length: 0)
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