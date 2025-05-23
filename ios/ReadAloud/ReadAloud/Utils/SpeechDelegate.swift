import SwiftUI
import AVFoundation
import Foundation
import UIKit

/**
 * SpeechDelegate类负责管理朗读状态
 */
class SpeechDelegate: NSObject, ObservableObject {
    // 单例模式，便于全局访问
    static let shared = SpeechDelegate()
    
    // 发布当前朗读范围，供UI更新使用
    @Published var highlightRange: NSRange = NSRange(location: 0, length: 0)
    
    // 添加一个标志变量，表示是否正在朗读
    @Published var isSpeaking: Bool = false
    
    // 添加结束原因标志，区分自然结束和用户暂停
    @Published var wasManuallyPaused: Bool = false
    
    // 添加一个新的标志，专门标记是否是接近文章末尾自动结束的特殊情况
    @Published var isNearArticleEnd: Bool = false
    
    // 添加一个新的标志，专门标记是否是因为切换文章导致的停止
    @Published var isArticleSwitching: Bool = false
    
    // 添加起始位置偏移量
    var startPosition: Int = 0
    
    private override init() {
        super.init()
    }
    
    // 更新当前高亮范围
    func updateHighlightRange(location: Int, length: Int) {
        highlightRange = NSRange(location: location, length: length)
    }
    
    // 重置状态
    func resetState() {
        isSpeaking = false
        wasManuallyPaused = false
        isNearArticleEnd = false
        isArticleSwitching = false
        startPosition = 0
        highlightRange = NSRange(location: 0, length: 0)
    }
    
    // 标记开始播放
    func markPlaybackStarted() {
        isSpeaking = true
        wasManuallyPaused = false
        isNearArticleEnd = false
    }
    
    // 标记播放暂停
    func markPlaybackPaused() {
        isSpeaking = false
        wasManuallyPaused = true
    }
    
    // 标记播放完成
    func markPlaybackFinished() {
        isSpeaking = false
        
        // 发送播放完成通知
        NotificationCenter.default.post(name: Notification.Name("SpeechFinished"), object: nil)
    }
} 