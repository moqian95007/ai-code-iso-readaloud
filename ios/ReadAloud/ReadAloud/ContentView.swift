//
//  ContentView.swift
//  ReadAloud
//
//  Created by moqian on 2025/3/27.
//

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
        // 注意：不要在这里重置高亮范围
        // highlightRange = NSRange(location: startPosition, length: 0)
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
        // 不要在这里重置startPosition
        // startPosition = 0  // 注释掉这行
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

/**
 * ContentView是应用程序的主视图
 * 包含文本展示和语音朗读控制功能
 */
struct ContentView: View {
    // 示例文本 - 500字左右的春天描述
    let sampleText = """
    春天来了，万物复苏，大地披上了绿色的外衣。小草从土里探出头来，嫩绿嫩绿的，可爱极了。树木抽出了新的枝条，长出了嫩叶，整个世界一片生机勃勃的景象。
    
    花儿们也竞相开放，迎春花、桃花、杏花、樱花，五颜六色，争奇斗艳。蜜蜂、蝴蝶从冬眠中醒来，在花丛中飞舞，采集花粉。小鸟们叽叽喳喳地唱着歌，为春天增添了许多欢乐的气息。
    
    春雨淅淅沥沥地下着，滋润着干渴的土地。雨后的空气格外清新，还夹杂着泥土和花草的芳香。阳光透过云层，照在雨后的田野上，发出耀眼的光芒。
    
    孩子们脱下厚重的冬装，换上轻便的春装，在草地上奔跑、嬉戏。他们放风筝、捉迷藏、踢足球，笑声在春风中回荡。
    
    农民伯伯们开始了春耕，他们犁地、播种，为一年的丰收打下基础。田野里到处是忙碌的身影，人们脸上洋溢着希望的笑容。
    
    春天是一个充满生机和希望的季节，它象征着新的开始，新的希望。在这个美好的季节里，我们应该像春天一样，充满活力，勇往直前，创造属于我们自己的美好未来。
    
    让我们一起拥抱春天，感受大自然的魅力，聆听春天的声音，闻一闻春天的气息，尽情享受这美好的季节带给我们的一切！
    """
    
    // 用于控制播放状态的State变量
    @State private var isPlaying = false
    
    // 添加NSAttributedString来实现高亮
    @State private var attributedText = NSAttributedString()
    
    // 用于监听正在朗读的文本范围
    @ObservedObject private var speechDelegate = SpeechDelegate.shared
    
    // 语音合成器实例，用于文本朗读
    private let synthesizer = AVSpeechSynthesizer()
    
    // 添加一个变量跟踪起始朗读位置
    @State private var startReadingPosition: Int = 0
    
    // 添加变量记录当前播放位置
    @State private var currentPlaybackPosition: Int = 0
    
    // 添加变量记录是否是暂停后继续播放
    @State private var isResuming: Bool = false
    
    // 添加进度相关的状态变量
    @State private var currentProgress: Double = 0.0  // 0.0-1.0之间的进度值
    @State private var currentTime: TimeInterval = 0  // 当前已播放时长
    @State private var totalTime: TimeInterval = 0    // 估计总时长
    @State private var isDragging: Bool = false       // 是否正在拖动进度条
    @State private var timer: Timer? = nil            // 更新进度的计时器
    
    /**
     * 初始化函数
     * 在ContentView创建时执行，设置语音合成器和音频会话
     */
    init() {
        // 设置SpeechDelegate作为语音合成器的代理
        synthesizer.delegate = SpeechDelegate.shared
        
        // 初始化富文本
        let attrText = NSMutableAttributedString(string: sampleText)
        _attributedText = State(initialValue: attrText)
        
        // 配置音频会话 - 非常重要，否则可能没有声音输出
        do {
            // 设置音频类别为播放(.playback)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            // 激活音频会话
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话失败: \(error.localizedDescription)")
        }
    }
    
    /**
     * 视图体
     * 定义用户界面的结构和布局
     */
    var body: some View {
        VStack {
            // 标题部分
            Text("文本阅读器")
                .font(.title)
                .padding()
            
            // 文本展示区 - 带滚动功能和高亮效果
            ScrollViewReader { scrollView in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // 将长文本分成段落，每个段落有自己的ID
                        ForEach(sampleText.components(separatedBy: "\n\n").enumerated().map { (index, text) in 
                            (index, "paragraph_\(index)", text)
                        }, id: \.1) { (index, id, paragraph) in
                            // 判断该段落是否包含当前朗读的文本
                            let containsHighlight = speechDelegate.isSpeaking && 
                                                   isInRange(paragraph, range: speechDelegate.highlightRange, fullText: sampleText)
                            
                            Text(paragraph)
                                .padding(5)
                                .background(containsHighlight ? Color.yellow.opacity(0.3) : Color.clear)
                                .id(id)
                                // 使用已经包含在闭包中的index
                                .onTapGesture {
                                    handleTextTap(paragraphIndex: index, paragraph: paragraph)
                                }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(10)
                .padding()
                .onChange(of: speechDelegate.highlightRange) { _ in
                    // 只有在正在朗读状态才进行滚动
                    if speechDelegate.isSpeaking, 
                       let paragraphId = getCurrentParagraphId(range: speechDelegate.highlightRange) {
                        withAnimation {
                            scrollView.scrollTo(paragraphId, anchor: UnitPoint(x: 0, y: 0.25))
                        }
                    }
                }
            }
            
            // 添加进度条和时间显示
            VStack(spacing: 5) {
                // 左侧显示当前时间，右侧显示总时间
                HStack {
                    Text(formatTime(currentTime))
                        .font(.caption)
                    Spacer()
                    Text(formatTime(totalTime))
                        .font(.caption)
                }
                
                // 进度条和快进/快退按钮
                HStack {
                    // 后退15秒按钮
                    Button(action: {
                        skipBackward(seconds: 15)
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 8)
                    
                    // 进度条，支持拖动
                    Slider(
                        value: $currentProgress,
                        in: 0...1,
                        onEditingChanged: { editing in
                            isDragging = editing
                            
                            if !editing {
                                // 计算新位置
                                let newPosition = Int(Double(sampleText.count) * currentProgress)
                                
                                // 根据播放状态决定是立即跳转还是只更新位置
                                if isPlaying {
                                    stopSpeaking()
                                    startSpeakingFromPosition(newPosition)
                                    isPlaying = true
                                } else {
                                    currentPlaybackPosition = newPosition
                                    isResuming = true
                                }
                            }
                        }
                    )
                    .accentColor(.blue)
                    
                    // 前进15秒按钮
                    Button(action: {
                        skipForward(seconds: 15)
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // 播放控制区 - 播放/暂停按钮
            HStack {
                Button(action: {
                    if isPlaying {
                        // 暂停朗读，保存当前位置
                        pauseSpeaking()
                    } else {
                        // 如果是暂停后继续，从暂停位置开始
                        if isResuming {
                            startSpeakingFromPosition(currentPlaybackPosition)
                        } else {
                            // 否则从头开始播放
                            startSpeaking()
                        }
                    }
                    isPlaying.toggle()
                }) {
                    // 根据播放状态显示不同图标
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.blue)
                }
                
                // 按钮文字说明
                Text(isPlaying ? "暂停" : (isResuming ? "继续" : "播放"))
                    .font(.headline)
                    .padding(.leading, 5)
            }
            .padding(.bottom, 30)
            
            // 可选：添加从头开始播放的按钮
            Button(action: {
                if isPlaying {
                    stopSpeaking()
                }
                isResuming = false
                startSpeaking()
                isPlaying = true
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("从头开始")
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .onAppear {
            // 计算总时长估计值 (按照每分钟300个汉字的朗读速度估算)
            let wordsCount = Double(sampleText.count)  // 转换为Double类型
            totalTime = wordsCount / 5.0  // 每秒朗读5个字
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                // 开始播放时启动计时器
                startTimer()
            } else {
                // 停止播放时停止计时器
                stopTimer()
            }
        }
    }
    
    /**
     * 处理文本点击事件
     * 计算点击位置对应的文本索引，并从该位置开始朗读
     */
    private func handleTextTap(paragraphIndex: Int, paragraph: String) {
        var startPosition = 0
        let paragraphs = sampleText.components(separatedBy: "\n\n")
        
        for i in 0..<paragraphIndex {
            startPosition += paragraphs[i].count + 2
        }
        
        print("点击了段落 \(paragraphIndex)，计算起始位置: \(startPosition)")
        
        if isPlaying {
            stopSpeaking()
        }
        
        startReadingPosition = startPosition
        startSpeakingFromPosition(startPosition)
        isPlaying = true
    }
    
    /**
     * 从指定位置开始朗读
     */
    private func startSpeakingFromPosition(_ position: Int) {
        if position < 0 || position >= sampleText.count {
            startSpeaking()
            return
        }
        
        // 更新进度和时间
        currentProgress = Double(position) / Double(sampleText.count)
        currentTime = totalTime * currentProgress
        
        // 获取从指定位置开始的子字符串
        let startIndex = sampleText.index(sampleText.startIndex, offsetBy: position)
        let subText = String(sampleText[startIndex...])
        
        // 创建语音合成器使用的话语对象
        let utterance = AVSpeechUtterance(string: subText)
        
        // 设置语音参数
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN") 
        utterance.rate = 0.4
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 关联utterance和位置
        SpeechDelegate.shared.setPosition(for: utterance, position: position)
        
        // 开始朗读
        synthesizer.speak(utterance)
    }
    
    /**
     * 开始朗读整篇文本
     */
    private func startSpeaking() {
        // 重置进度和时间
        currentProgress = 0.0
        currentTime = 0.0
        
        // 重置起始位置为0
        SpeechDelegate.shared.startPosition = 0
        
        // 创建语音合成器使用的话语对象
        let utterance = AVSpeechUtterance(string: sampleText)
        
        // 设置语音参数
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.4
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 开始朗读
        synthesizer.speak(utterance)
    }
    
    /**
     * 暂停朗读
     * 保存当前朗读位置，以便之后继续
     */
    private func pauseSpeaking() {
        if synthesizer.isSpeaking {
            let currentRange = speechDelegate.highlightRange
            currentPlaybackPosition = currentRange.location + currentRange.length
            isResuming = true
            
            // 停止计时器但保留当前进度
            stopTimer()
            
            // 暂停朗读 - 使用.word参数让它在朗读完当前词后停止
            synthesizer.stopSpeaking(at: .word)
            
            // 手动确保SpeechDelegate状态正确
            speechDelegate.isSpeaking = false
            
            print("暂停朗读，当前位置：\(currentPlaybackPosition)，进度：\(currentProgress)")
        }
    }
    
    /**
     * 停止朗读
     * 完全停止朗读，不保存位置
     */
    private func stopSpeaking() {
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
        }
    }
    
    // 辅助函数：判断段落是否包含高亮范围
    private func isInRange(_ paragraph: String, range: NSRange, fullText: String) -> Bool {
        // 计算段落在全文中的范围
        if let startIndex = fullText.range(of: paragraph)?.lowerBound {
            let paragraphStart = fullText.distance(from: fullText.startIndex, to: startIndex)
            let paragraphEnd = paragraphStart + paragraph.count
            
            // 检查朗读范围是否与段落范围重叠
            return range.location >= paragraphStart && range.location < paragraphEnd
        }
        return false
    }
    
    // 查找当前高亮范围所在的段落ID
    private func getCurrentParagraphId(range: NSRange) -> String? {
        let paragraphs = sampleText.components(separatedBy: "\n\n")
        var currentPosition = 0
        
        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphLength = paragraph.count + 2 // +2 for "\n\n"
            
            if range.location >= currentPosition && range.location < currentPosition + paragraphLength {
                return "paragraph_\(index)"
            }
            
            currentPosition += paragraphLength
        }
        
        return nil
    }
    
    // 启动计时器，定期更新进度
    private func startTimer() {
        stopTimer()  // 确保不会创建多个计时器
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // 只有在朗读状态且不拖动时才更新进度
            if !isDragging && speechDelegate.isSpeaking {
                // 根据朗读位置更新进度和时间
                let currentPosition = speechDelegate.highlightRange.location
                if sampleText.count > 0 && currentPosition > 0 {  // 添加检查确保位置有效
                    currentProgress = Double(currentPosition) / Double(sampleText.count)
                    // 更新当前时间
                    currentTime = totalTime * currentProgress
                }
            }
        }
    }
    
    // 停止计时器
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // 格式化时间显示
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    // 后退15秒
    private func skipBackward(seconds: TimeInterval) {
        // 先停止计时器，防止它覆盖我们的值
        stopTimer()
        
        // 计算新的时间点，确保不小于0
        let newTime = max(currentTime - seconds, 0)
        // 计算新的进度
        let newProgress = newTime / totalTime
        // 计算对应的文本位置
        let newPosition = Int(Double(sampleText.count) * newProgress)
        
        print("后退\(seconds)秒，新时间：\(newTime)，新位置：\(newPosition)")
        
        // 如果正在播放，则停止当前朗读
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            
            // 手动设置状态标志
            speechDelegate.isSpeaking = false
            isPlaying = false
        }
        
        // 更新UI和状态
        currentTime = newTime
        currentProgress = newProgress
        currentPlaybackPosition = newPosition
        isResuming = true
        
        // 立即从新位置开始播放
        startSpeakingFromPosition(newPosition)
        isPlaying = true
        
        // 启动计时器
        startTimer()
    }
    
    // 前进15秒
    private func skipForward(seconds: TimeInterval) {
        // 先停止计时器，防止它覆盖我们的值
        stopTimer()
        
        // 计算新的时间点
        let newTime = min(currentTime + seconds, totalTime)
        // 计算新的进度
        let newProgress = newTime / totalTime
        // 计算对应的文本位置
        let newPosition = Int(Double(sampleText.count) * newProgress)
        
        print("前进\(seconds)秒，新时间：\(newTime)，新位置：\(newPosition)")
        
        // 如果正在播放，则停止当前朗读
        if isPlaying {
            synthesizer.stopSpeaking(at: .immediate)
            
            // 手动设置状态标志
            speechDelegate.isSpeaking = false
            isPlaying = false
        }
        
        // 更新UI和状态
        currentTime = newTime
        currentProgress = newProgress
        currentPlaybackPosition = newPosition
        isResuming = true
        
        // 立即从新位置开始播放
        startSpeakingFromPosition(newPosition)
        isPlaying = true
        
        // 启动计时器
        startTimer()
    }
}

/**
 * 自定义视图，用于显示带有高亮效果的文本
 */
struct HighlightedText: View {
    let text: String
    let highlightRange: NSRange
    // 添加朗读状态参数
    let isSpeaking: Bool = SpeechDelegate.shared.isSpeaking
    
    var body: some View {
        Text(attributedString)
    }
    
    // 根据高亮范围构建富文本
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)
        
        // 只有在朗读状态下才应用高亮
        if isSpeaking && 
           highlightRange.location != NSNotFound && 
           highlightRange.length > 0 && 
           highlightRange.location + highlightRange.length <= text.utf16.count {
            
            // 创建AttributedString的范围
            if let range = Range(highlightRange, in: text) {
                // 转换为AttributedString的索引
                let startIndex = AttributedString.Index(range.lowerBound, within: attributedString)
                let endIndex = AttributedString.Index(range.upperBound, within: attributedString)
                
                // 确保索引有效
                if let startIndex = startIndex, let endIndex = endIndex {
                    let attrRange = startIndex..<endIndex
                    
                    // 设置高亮属性
                    attributedString[attrRange].backgroundColor = .yellow
                    attributedString[attrRange].foregroundColor = .black
                    attributedString[attrRange].font = .system(.body, weight: .bold)
                }
            }
        }
        
        return attributedString
    }
}

// SwiftUI预览
#Preview {
    ContentView()
}

