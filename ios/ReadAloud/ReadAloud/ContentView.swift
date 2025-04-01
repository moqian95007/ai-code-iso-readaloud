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

// 1. 首先，将 UserDefaultsKeys 移到 ContentView 外部，使其成为全局可访问的结构体
struct UserDefaultsKeys {
    static let fontSize = "fontSize"
    static let fontSizeOption = "fontSizeOption"
    static let isDarkMode = "isDarkMode"
    static let selectedRate = "selectedRate"
    // 新增播放进度相关键
    static let lastPlaybackPosition = "lastPlaybackPosition"
    static let lastProgress = "lastProgress"
    static let lastPlaybackTime = "lastPlaybackTime"
    static let wasPlaying = "wasPlaying"
    static let autoResumePlayback = "autoResumePlayback"
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
    
    // 修改已有的状态变量，从 UserDefaults 读取上次的播放进度
    @State private var currentPlaybackPosition: Int = UserDefaults.standard.integer(forKey: UserDefaultsKeys.lastPlaybackPosition)
    @State private var currentProgress: Double = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastProgress)
    @State private var currentTime: TimeInterval = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastPlaybackTime)
    
    // 添加一个变量记录上次是否正在播放
    @State private var shouldResumePlayback: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.wasPlaying)
    
    // 添加变量记录是否是暂停后继续播放
    @State private var isResuming: Bool = false
    
    // 添加进度相关的状态变量
    @State private var totalTime: TimeInterval = 0    // 估计总时长
    @State private var isDragging: Bool = false       // 是否正在拖动进度条
    @State private var timer: Timer? = nil            // 更新进度的计时器
    
    // 添加这个新的状态变量
    @State private var showSpeedSelector: Bool = false
    @State private var availableRates: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
    
    // 修改已有的状态变量初始化，从 UserDefaults 读取保存的值
    @State private var fontSize: CGFloat = UserDefaults.standard.object(forKey: UserDefaultsKeys.fontSize) as? CGFloat ?? 18.0
    @State private var isDarkMode: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isDarkMode)
    @State private var selectedRate: Double = UserDefaults.standard.object(forKey: UserDefaultsKeys.selectedRate) as? Double ?? 1.0
    
    // 为 fontSizeOption 添加特殊处理，因为它是一个枚举类型
    @State private var fontSizeOption: FontSizeOption = {
        let savedOptionRawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.fontSizeOption) ?? FontSizeOption.medium.rawValue
        return FontSizeOption(rawValue: savedOptionRawValue) ?? .medium
    }()
    
    // 新增：定义字体大小选项枚举
    private enum FontSizeOption: String, CaseIterable {
        case small = "小"
        case medium = "中"
        case large = "大"
        case extraLarge = "特大"
        
        // 返回对应的字体大小
        var size: CGFloat {
            switch self {
            case .small: return 14.0
            case .medium: return 18.0
            case .large: return 22.0
            case .extraLarge: return 26.0
            }
        }
        
        // 返回下一个大小选项
        func next() -> FontSizeOption {
            switch self {
            case .small: return .medium
            case .medium: return .large
            case .large: return .extraLarge
            case .extraLarge: return .small
            }
        }
    }
    
    // 在 ContentView 中添加一个状态变量，并设置默认值为 false
    @State private var autoResumePlayback: Bool = {
        // 检查键是否存在
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.autoResumePlayback) != nil {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoResumePlayback)
        } else {
            // 如果键不存在，返回默认值 false (不自动恢复)
            return false
        }
    }()
    
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
        
        // 读取保存的用户设置
        let savedFontSize = UserDefaults.standard.object(forKey: UserDefaultsKeys.fontSize) as? CGFloat ?? 18.0
        let savedIsDarkMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isDarkMode)
        let savedRate = UserDefaults.standard.object(forKey: UserDefaultsKeys.selectedRate) as? Double ?? 1.0
        let savedFontSizeOptionRawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.fontSizeOption) ?? FontSizeOption.medium.rawValue
        let savedFontSizeOption = FontSizeOption(rawValue: savedFontSizeOptionRawValue) ?? .medium
        
        // 使用 _fontSize 等形式设置状态变量的初始值
        _fontSize = State(initialValue: savedFontSize)
        _isDarkMode = State(initialValue: savedIsDarkMode)
        _selectedRate = State(initialValue: savedRate)
        _fontSizeOption = State(initialValue: savedFontSizeOption)
        
        // 读取自动恢复播放设置，如果不存在则设置默认值为 true
        let savedAutoResumePlayback = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoResumePlayback)
        _autoResumePlayback = State(initialValue: savedAutoResumePlayback)
        
        // 如果 autoResumePlayback 键不存在，设置默认值为 true
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.autoResumePlayback) == nil {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.autoResumePlayback)
        }
        
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
            // 标题部分 - 移除字体大小按钮
            Text("文本阅读器")
                .font(.title)
                .padding()
            
            // 文本展示区 - 将复杂的表达式分解为更简单的部分
            ScrollViewReader { scrollView in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // 将长文本分成段落
                        let paragraphs = sampleText.components(separatedBy: "\n\n")
                        
                        // 遍历段落并分别处理
                        ForEach(0..<paragraphs.count, id: \.self) { index in
                            let paragraph = paragraphs[index]
                            let paragraphId = "paragraph_\(index)"
                            
                            // 判断该段落是否包含当前朗读的文本
                            let containsHighlight = speechDelegate.isSpeaking && 
                                                   isInRange(paragraph, range: speechDelegate.highlightRange, fullText: sampleText)
                            
                            Text(paragraph)
                                .font(.system(size: fontSize))  // 应用字体大小
                                .padding(5)
                                // 设置背景颜色
                                .background(getHighlightBackground(isHighlighted: containsHighlight))
                                .id(paragraphId)
                                // 点击事件
                                .onTapGesture {
                                    handleTextTap(paragraphIndex: index, paragraph: paragraph)
                                }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(getScrollViewBackground())
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
                                    
                                    // 保存更新后的播放进度
                                    savePlaybackProgress()
                                }
                            }
                        }
                    )
                    .accentColor(isDarkMode ? .white : .blue)
                    
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
                // 语速调节按钮
                Button(action: {
                    showSpeedSelector = true
                }) {
                    HStack {
                        Image(systemName: "speedometer")
                            .font(.system(size: 22))
                        Text("\(String(format: "%.1f", selectedRate))x")
                            .font(.system(size: 16))
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding(.trailing, 12)
                
                // 播放/暂停按钮
                Button(action: {
                    if isPlaying {
                        pauseSpeaking()
                        isPlaying = false
                    } else {
                        if isResuming {
                            startSpeakingFromPosition(currentPlaybackPosition)
                        } else {
                            startSpeaking()
                        }
                        isPlaying = true
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(isDarkMode ? .white : .blue)
                }
                
                // 按钮文字说明
                Text(isPlaying ? "暂停" : (isResuming ? "继续" : "播放"))
                    .font(.headline)
                    .padding(.leading, 5)
            }
            .padding(.bottom, 15)
            
            // 在播放按钮下方添加一个新的 HStack 包含主题切换和字体大小按钮
            HStack(spacing: 20) {
                // 日间/夜间模式切换按钮
                Button(action: {
                    // 切换日间/夜间模式
                    isDarkMode.toggle()
                    // 保存设置
                    UserDefaults.standard.set(isDarkMode, forKey: UserDefaultsKeys.isDarkMode)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 18))
                        
                        Text(isDarkMode ? "夜间" : "日间")
                            .font(.system(size: 16))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 字体大小切换按钮
                Button(action: {
                    // 切换到下一个字体大小选项
                    fontSizeOption = fontSizeOption.next()
                    // 应用新的字体大小
                    fontSize = fontSizeOption.size
                    // 保存设置
                    UserDefaults.standard.set(fontSizeOption.rawValue, forKey: UserDefaultsKeys.fontSizeOption)
                    UserDefaults.standard.set(fontSize, forKey: UserDefaultsKeys.fontSize)
                }) {
                    HStack(spacing: 5) {
                        // 显示单个"A"，大小根据当前字体选项动态调整
                        switch fontSizeOption {
                        case .small:
                            Text("A")
                                .font(.system(size: 16))
                        case .medium:
                            Text("A")
                                .font(.system(size: 20))
                        case .large:
                            Text("A")
                                .font(.system(size: 24))
                        case .extraLarge:
                            Text("A")
                                .font(.system(size: 28))
                        }
                        
                        Text(fontSizeOption.rawValue)
                            .font(.system(size: 16))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding(.bottom, 30)
            
            // 在播放按钮下方添加一个新的 HStack 包含自动继续播放开关
            Toggle("自动继续上次播放", isOn: $autoResumePlayback)
                .onChange(of: autoResumePlayback) { newValue in
                    UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.autoResumePlayback)
                }
            
            // 如果有上次播放位置，显示恢复提示或按钮
            if isResuming && !isPlaying {
                HStack {
                    Button(action: {
                        startSpeakingFromPosition(currentPlaybackPosition)
                        isPlaying = true
                    }) {
                        Label("继续上次播放", systemImage: "play.circle")
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    // 可选：添加一个忽略按钮
                    Button(action: {
                        // 重置恢复状态
                        isResuming = false
                        currentPlaybackPosition = 0
                        currentProgress = 0
                        currentTime = 0
                        // 清除保存的播放进度
                        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition)
                        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress)
                        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackTime)
                    }) {
                        Text("从头开始")
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            // 计算总时长估计值 (按照每分钟300个汉字的朗读速度估算)
            let wordsCount = Double(sampleText.count)  // 转换为Double类型
            totalTime = wordsCount / 5.0  // 每秒朗读5个字
            
            // 确保语速设置已加载
            print("当前设置的语速：\(selectedRate)")
            
            // 检查是否有上次的播放进度
            if currentPlaybackPosition > 0 {
                isResuming = true
                
                // 更新进度条和时间显示，但不自动开始播放
                currentProgress = Double(currentPlaybackPosition) / Double(sampleText.count)
                currentTime = totalTime * currentProgress
            }
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
        .onDisappear {
            // 保存当前播放进度
            savePlaybackProgress()
        }
        // 添加语速选择弹窗
        .sheet(isPresented: $showSpeedSelector) {
            SpeedSelectorView(selectedRate: $selectedRate, showSpeedSelector: $showSpeedSelector)
                .onDisappear {
                    // 当弹窗关闭时，应用新的语速
                    applyNewSpeechRate()
                }
        }
        .background(isDarkMode ? Color.black : Color.white)
        .foregroundColor(isDarkMode ? Color.white : Color.black)
        .preferredColorScheme(isDarkMode ? .dark : .light)
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
        startSpeakingFromPositionWithRate(position, rate: Float(selectedRate))
        isPlaying = true
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
        utterance.rate = Float(selectedRate) * 0.4  // 转换为AVSpeechUtterance接受的范围
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 开始朗读
        synthesizer.speak(utterance)
        
        // 确保设置播放状态为true
        isPlaying = true
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
            
            // 保存当前播放进度
            savePlaybackProgress()
            
            // 暂停朗读
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
            
            // 清除保存的播放进度
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackPosition)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastProgress)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastPlaybackTime)
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.wasPlaying)
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
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if !isDragging && speechDelegate.isSpeaking {
                let currentPosition = speechDelegate.highlightRange.location
                if sampleText.count > 0 && currentPosition > 0 {
                    currentProgress = Double(currentPosition) / Double(sampleText.count)
                    currentTime = totalTime * currentProgress
                    
                    // 每隔几秒保存一次播放进度
                    if Int(currentTime) % 5 == 0 { // 每5秒保存一次
                        currentPlaybackPosition = currentPosition
                        savePlaybackProgress()
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
    
    /**
     * 应用新的语速设置
     * 如果正在朗读中，会重新从当前位置开始以新的语速朗读
     */
    private func applyNewSpeechRate() {
        // 如果正在朗读，需要停止并重新开始
        if isPlaying {
            // 保存当前位置
            let currentPosition = speechDelegate.highlightRange.location
            
            // 停止当前朗读
            synthesizer.stopSpeaking(at: .immediate)
            
            // 从保存的位置以新的语速开始朗读
            startSpeakingFromPositionWithRate(currentPosition, rate: Float(selectedRate))
        }
    }
    
    /**
     * 从指定位置以指定语速开始朗读
     */
    private func startSpeakingFromPositionWithRate(_ position: Int, rate: Float) {
        print("开始朗读，位置：\(position)，语速：\(rate)")
        
        if position < 0 || position >= sampleText.count {
            startSpeakingWithRate(rate)
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
        
        // 设置语音参数，应用新的语速
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate * 0.4  // 转换为AVSpeechUtterance接受的范围
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 关联utterance和位置
        SpeechDelegate.shared.setPosition(for: utterance, position: position)
        
        // 开始朗读
        synthesizer.speak(utterance)
        
        // 确保设置播放状态为true
        isPlaying = true
    }
    
    /**
     * 以指定语速开始朗读整篇文本
     */
    private func startSpeakingWithRate(_ rate: Float) {
        print("从头开始朗读，语速：\(rate)")
        
        // 重置进度和时间
        currentProgress = 0.0
        currentTime = 0.0
        
        // 重置起始位置为0
        SpeechDelegate.shared.startPosition = 0
        
        // 创建语音合成器使用的话语对象
        let utterance = AVSpeechUtterance(string: sampleText)
        
        // 设置语音参数，应用新的语速
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate * 0.4  // 转换为AVSpeechUtterance接受的范围
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 开始朗读
        synthesizer.speak(utterance)
        
        // 确保设置播放状态为true
        isPlaying = true
    }
    
    // 辅助函数：获取高亮背景颜色
    private func getHighlightBackground(isHighlighted: Bool) -> Color {
        if isHighlighted {
            return isDarkMode ? Color.yellow.opacity(0.4) : Color.yellow.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    // 辅助函数：获取滚动视图背景颜色
    private func getScrollViewBackground() -> Color {
        return isDarkMode ? Color(uiColor: .darkGray) : Color(uiColor: .secondarySystemBackground)
    }
    
    // 保存所有用户设置到 UserDefaults
    private func saveUserSettings() {
        UserDefaults.standard.set(fontSize, forKey: UserDefaultsKeys.fontSize)
        UserDefaults.standard.set(fontSizeOption.rawValue, forKey: UserDefaultsKeys.fontSizeOption)
        UserDefaults.standard.set(isDarkMode, forKey: UserDefaultsKeys.isDarkMode)
        UserDefaults.standard.set(selectedRate, forKey: UserDefaultsKeys.selectedRate)
    }
    
    // 添加一个方法保存当前播放进度
    private func savePlaybackProgress() {
        UserDefaults.standard.set(currentPlaybackPosition, forKey: UserDefaultsKeys.lastPlaybackPosition)
        UserDefaults.standard.set(currentProgress, forKey: UserDefaultsKeys.lastProgress)
        UserDefaults.standard.set(currentTime, forKey: UserDefaultsKeys.lastPlaybackTime)
        UserDefaults.standard.set(isPlaying, forKey: UserDefaultsKeys.wasPlaying)
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

// 2. 修改 SpeedSelectorView 以使用全局的 UserDefaultsKeys
struct SpeedSelectorView: View {
    @Binding var selectedRate: Double
    @Binding var showSpeedSelector: Bool
    
    // 预设的语速选项
    let availableRates: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
    
    // 临时存储用户选择的语速值，确认后再更新到主视图
    @State private var tempRate: Double
    
    // 修改初始化器，移除 userDefaultsKeys 参数
    init(selectedRate: Binding<Double>, showSpeedSelector: Binding<Bool>) {
        self._selectedRate = selectedRate
        self._showSpeedSelector = showSpeedSelector
        self._tempRate = State(initialValue: selectedRate.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("调语速")
                .font(.headline)
                .padding(.top, 20)
            
            // 显示当前选择的语速值
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 60, height: 60)
                
                Text("\(String(format: "%.1f", tempRate))x")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 10)
            
            // 语速滑块
            HStack {
                ForEach(availableRates, id: \.self) { rate in
                    VStack {
                        Circle()
                            .fill(tempRate == rate ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 15, height: 15)
                        
                        Text("\(String(format: "%.1f", rate))x")
                            .font(.caption)
                            .foregroundColor(tempRate == rate ? .red : .gray)
                    }
                    .onTapGesture {
                        tempRate = rate
                    }
                    
                    if rate != availableRates.last {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 滑块控件
            Slider(value: $tempRate, in: 0.5...4.0, step: 0.1)
                .accentColor(.red)
                .padding(.horizontal, 20)
            
            // 确认按钮
            Button("关闭") {
                // 更新选中的语速值
                selectedRate = tempRate
                // 保存设置 - 现在使用全局的 UserDefaultsKeys
                UserDefaults.standard.set(selectedRate, forKey: UserDefaultsKeys.selectedRate)
                // 关闭弹窗
                showSpeedSelector = false
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 40)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .padding()
    }
}

// SwiftUI预览
#Preview {
    ContentView()
}

