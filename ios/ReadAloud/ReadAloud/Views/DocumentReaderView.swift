import SwiftUI

struct DocumentReaderView: View {
    let documentTitle: String
    let document: Document
    let viewModel: DocumentsViewModel
    
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    @State private var selectedVoice: String = "默认"
    @State private var playbackSpeed: Double = 1.0
    @State private var playMode: PlayMode = .sequential
    @State private var showSpeedOptions = false
    @State private var showChapterList = false
    @State private var showFontSizeOptions = false
    @State private var fontSize: FontSize = .medium
    @State private var isDocumentLoaded = false
    @Environment(\.dismiss) var dismiss
    @State private var showTimerOptions = false
    @State private var selectedTimer: TimerOption = .off
    @State private var isDarkMode: Bool = false
    
    // 使用懒加载获取synthesizer，避免在视图初始化时创建
    private var synthesizer: SpeechSynthesizer {
        if playbackManager.currentDocument?.id == document.id,
           let existingSynthesizer = playbackManager.synthesizer {
            return existingSynthesizer
        } else {
            let newSynthesizer = SpeechSynthesizer()
            // 推迟更新playbackManager到onAppear中
            return newSynthesizer
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏 - 显示文档标题
            HStack {
                Spacer()
                
                // 突出显示文档标题
                Text(documentTitle)
                    .font(.system(size: 18, weight: .bold))  // 更大更粗的字体
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.vertical, 10)  // 增加上下内边距
                
                Spacer()
            }
            .padding(.horizontal)
            .background(Color.white)  // 确保背景是白色
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1) // 添加轻微阴影
            
            // 选择语音包区域
            VoiceSelectionView(selectedVoice: $selectedVoice)
                .padding(.vertical, 10)
                .background(Color.white)
            
            // 朗读内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 显示当前朗读的文本
                    if !isDocumentLoaded {
                        // 加载状态
                        ProgressView("正在加载文档...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(50)
                    } else if let synth = playbackManager.synthesizer, synth.currentText.starts(with: "文本提取失败") {
                        // 文本提取失败的提示
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                                .padding(.bottom, 5)
                            
                            Text(synth.currentText)
                                .font(.system(size: 16))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.red)
                            
                            // 解决方案建议
                            VStack(alignment: .leading, spacing: 10) {
                                Text("可能的解决方案:")
                                    .font(.headline)
                                    .padding(.top, 5)
                                
                                ForEach(["确保文件格式正确", "尝试转换为TXT或PDF格式", "重新导入文档"], id: \.self) { suggestion in
                                    HStack(alignment: .top) {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                        Text(suggestion)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(10)
                    } else if let synth = playbackManager.synthesizer {
                        VStack(alignment: .leading) {
                            // 添加调试标记
                            Text("文本已加载-长度: \(synth.currentText.count)字符")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.bottom, 5)
                            
                            if synth.currentText.isEmpty && !synth.fullText.isEmpty {
                                // 有内容但currentText为空的情况，手动显示文本开头
                                let startText = String(synth.fullText.prefix(500))
                                Text(startText)
                                    .font(.system(size: fontSize.size))
                                    .foregroundColor(.black) // 强制黑色文本
                                    .lineSpacing(5)
                                    .background(Color(.systemYellow).opacity(0.1)) // 添加背景色以确认文本框位置
                                    .border(Color.orange, width: 1) // 添加边框以确认文本框大小
                            } else if !synth.currentText.isEmpty {
                                Text(synth.currentText)
                                    .font(.system(size: fontSize.size))
                                    .foregroundColor(.black) // 强制黑色文本
                                    .lineSpacing(5)
                                    .background(Color(.systemYellow).opacity(0.1)) // 添加背景色以确认文本框位置
                                    .border(Color.orange, width: 1) // 添加边框以确认文本框大小
                            } else {
                                Text("请点击播放按钮开始阅读")
                                    .foregroundColor(.gray)
                                    .italic()
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay( // 添加边框以确认整个容器的位置和大小
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    } else {
                        Text("无法加载文档内容")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .background(Color(.systemGray6))
            
            // 底部控制区域
            VStack(spacing: 15) {
                // 进度条和前进/后退按钮
                HStack(alignment: .center) {
                    // 后退15秒按钮
                    Button(action: {
                        playbackManager.synthesizer?.skipBackward()
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 5)
                    
                    // 进度条
                    ProgressSlider(value: Binding(
                        get: { playbackManager.synthesizer?.currentPosition ?? 0 },
                        set: { position in
                            playbackManager.synthesizer?.seekTo(position: position)
                        }
                    ))
                    
                    // 前进15秒按钮
                    Button(action: {
                        playbackManager.synthesizer?.skipForward()
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 5)
                }
                .padding(.horizontal)
                
                // 播放控制按钮行 - 平衡调整按钮间距
                HStack {
                    // 水平方向留出适当空间
                    Spacer()
                        .frame(width: 5)
                    
                    // 倍速控制 - 位于左侧边缘和上一首按钮中间
                    Button(action: {
                        showSpeedOptions.toggle()
                    }) {
                        VStack(spacing: 5) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 22))
                            Text("\(String(format: "%.1f", playbackSpeed))x")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showSpeedOptions) {
                        SpeedOptionsView(playbackSpeed: $playbackSpeed, synthesizer: playbackManager.synthesizer)
                    }
                    
                    // 弹性空间，但不是完全弹性
                    Spacer()
                        .frame(minWidth: 10, maxWidth: 30)
                    
                    // 上一首按钮
                    Button(action: {
                        playPreviousDocument()
                    }) {
                        Image(systemName: "backward.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    
                    // 播放/暂停按钮
                    Button(action: {
                        if playbackManager.isPlaying {
                            playbackManager.synthesizer?.pauseSpeaking()
                            playbackManager.isPlaying = false
                        } else {
                            if let synth = playbackManager.synthesizer {
                                if synth.fullText.isEmpty {
                                    print("无法播放：文本为空")
                                } else {
                                    synth.resumeSpeaking()
                                    if !synth.isPlaying {
                                        synth.startSpeaking(from: synth.currentPosition)
                                    }
                                    playbackManager.isPlaying = true
                                    
                                    if synth.currentText.isEmpty {
                                        synth.updateCurrentTextDisplay()
                                    }
                                }
                            }
                        }
                    }) {
                        Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.blue)
                    }
                    
                    // 下一首按钮
                    Button(action: {
                        playNextDocument()
                    }) {
                        Image(systemName: "forward.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    
                    // 弹性空间，但不是完全弹性
                    Spacer()
                        .frame(minWidth: 10, maxWidth: 30)
                    
                    // 播放模式 - 位于右侧边缘和下一首按钮中间
                    Button(action: {
                        let allModes = PlayMode.allCases
                        if let currentIndex = allModes.firstIndex(of: playMode),
                           let nextMode = allModes[safe: (currentIndex + 1) % allModes.count] {
                            playMode = nextMode
                        }
                    }) {
                        VStack(spacing: 5) {
                            Image(systemName: playMode == .sequential ? "repeat" : (playMode == .loop ? "repeat.1" : "1.circle"))
                                .font(.system(size: 22))
                            Text(playMode == .sequential ? "顺序" : (playMode == .loop ? "循环" : "单章"))
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.gray)
                    }
                    
                    // 水平方向留出适当空间
                    Spacer()
                        .frame(width: 5)
                }
                .padding(.horizontal, 5)  // 整体水平内边距较小
                .padding(.vertical, 5)
                
                // 其他控制按钮 - 完全重写
                HStack(spacing: 30) {
                    Button(action: {
                        showChapterList.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet")
                            Text("章节")
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showChapterList) {
                        ChapterListView()
                    }
                    
                    // 定时关闭按钮
                    Button(action: {
                        showTimerOptions.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "timer")
                            Text(selectedTimer == .off ? "定时" : selectedTimer.displayText)
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showTimerOptions) {
                        TimerOptionsView(selectedOption: $selectedTimer)
                    }
                    
                    // 日间/夜间模式切换按钮
                    Button(action: {
                        isDarkMode.toggle()
                        // 在这里添加切换显示模式的实际逻辑
                        applyColorScheme(isDarkMode)
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            Text(isDarkMode ? "夜间" : "日间")
                        }
                        .foregroundColor(.gray)
                    }
                    
                    // 字体大小按钮
                    Button(action: {
                        // 循环切换字体大小
                        let allSizes = FontSize.allCases
                        if let currentIndex = allSizes.firstIndex(of: fontSize),
                           let nextSize = allSizes[safe: (currentIndex + 1) % allSizes.count] {
                            fontSize = nextSize
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "textformat.size")
                            Text(fontSize.rawValue)
                        }
                        .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 5)
            }
            .padding()
            .background(Color.white)
        }
        .onAppear {
            print("DocumentReaderView appeared - setting isInReaderView to true")
            NavigationState.shared.isInReaderView = true
            
            // 先标记为未加载状态，显示加载指示器
            isDocumentLoaded = false
            
            // 使用DispatchQueue确保视图已完全渲染后再执行这些操作
            DispatchQueue.main.async {
                // 设置当前文档
                playbackManager.currentDocument = document
                playbackManager.synthesizer = synthesizer
                
                // 加载文档
                print("开始加载文档: \(document.title)")
                synthesizer.loadDocument(document, viewModel: viewModel)
                
                // 延迟标记已加载，给予文档内容加载的时间
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // 强制更新UI
                    DispatchQueue.main.async {
                        // 确保文本显示更新
                        synthesizer.updateCurrentTextDisplay()
                        // 标记文档已加载
                        isDocumentLoaded = true
                        
                        // 打印调试信息
                        print("文档加载状态: isDocumentLoaded=\(isDocumentLoaded)")
                        print("文本内容状态: fullText长度=\(synthesizer.fullText.count)")
                        print("文本内容状态: currentText长度=\(synthesizer.currentText.count)")
                        
                        // 显示文本内容的前20个字符用于调试
                        if !synthesizer.currentText.isEmpty {
                            let previewText = String(synthesizer.currentText.prefix(20))
                            print("文本前20个字符: \"\(previewText)\"")
                        }
                    }
                }
            }
        }
        .onDisappear {
            print("DocumentReaderView disappeared - setting isInReaderView to false")
            NavigationState.shared.isInReaderView = false
            
            // 取消定时关闭功能
            if selectedTimer != .off {
                // 取消定时器的代码
                selectedTimer = .off
            }
            
            // 只有在当前文档不在播放时才停止朗读
            if !playbackManager.isPlaying {
                DispatchQueue.main.async {
                    playbackManager.synthesizer?.stopSpeaking()
                    playbackManager.synthesizer = nil
                    playbackManager.currentDocument = nil
                }
            }
        }
    }
    
    private func playPreviousDocument() {
        // 获取当前文档索引
        if let currentDocument = playbackManager.currentDocument,
           let currentIndex = viewModel.documents.firstIndex(where: { $0.id == currentDocument.id }),
           currentIndex > 0 {
            // 播放前一个文档
            let previousDocument = viewModel.documents[currentIndex - 1]
            playbackManager.startPlayback(document: previousDocument, viewModel: viewModel)
        }
    }
    
    private func playNextDocument() {
        // 获取当前文档索引
        if let currentDocument = playbackManager.currentDocument,
           let currentIndex = viewModel.documents.firstIndex(where: { $0.id == currentDocument.id }),
           currentIndex < viewModel.documents.count - 1 {
            // 播放下一个文档
            let nextDocument = viewModel.documents[currentIndex + 1]
            playbackManager.startPlayback(document: nextDocument, viewModel: viewModel)
        }
    }
    
    private func applyColorScheme(_ isDark: Bool) {
        // 在实际应用中，这里应该更新全局的颜色方案或特定视图的颜色
        // 由于SwiftUI中直接手动控制ColorScheme有一定限制，这里提供一种可能的实现方式
        
        print("切换到\(isDark ? "夜间" : "日间")模式")
        
        // 一种方法是使用NotificationCenter发送通知，让全局的AppDelegate或SceneDelegate处理
        // NotificationCenter.default.post(name: Notification.Name("ToggleColorScheme"), object: nil)
        
        // 另一种方法是通过环境对象更新全局的主题设置
        // 这需要一个专门的主题管理器
        // ThemeManager.shared.isDarkMode = isDark
    }
}

// 进度滑块
struct ProgressSlider: View {
    @Binding var value: Double
    
    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center) {
                // 左侧显示已播放时间
                Text(formatPlayedTime(percent: value))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 40, alignment: .leading)
                
                // 进度条
                Slider(value: $value, in: 0...1) { editing in
                    // 完成拖动后触发朗读定位
                }
                .accentColor(.blue)
                
                // 右侧显示总时长
                Text(formatTotalTime())
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
    
    private func formatPlayedTime(percent: Double) -> String {
        // 假设一篇文章平均阅读时间为1小时
        let estimatedTotalSeconds = 3600.0
        let playedSeconds = percent * estimatedTotalSeconds
        
        let minutes = Int(playedSeconds / 60)
        let seconds = Int(playedSeconds) % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func formatTotalTime() -> String {
        // 假设固定总时长为1小时
        return "60:00"
    }
}

// 语音选择视图
struct VoiceSelectionView: View {
    @Binding var selectedVoice: String
    
    private let voices = ["默认", "聆小琪", "聆小美", "聆小龙"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(voices, id: \.self) { voice in
                    VoiceOption(
                        voiceName: voice,
                        isSelected: voice == selectedVoice
                    ) {
                        selectedVoice = voice
                    }
                }
                
                Button(action: {
                    // 添加更多语音包的操作
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                        
                        Text("添加")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(width: 70, height: 70)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
        }
    }
}

// 单个语音选项
struct VoiceOption: View {
    let voiceName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                
                Text(voiceName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .black)
            }
            .frame(width: 70, height: 70)
            .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
            .cornerRadius(10)
        }
    }
}

// 更新速度选项视图为滑动条风格，修复数字显示和关闭按钮问题
struct SpeedOptionsView: View {
    @Binding var playbackSpeed: Double
    let synthesizer: SpeechSynthesizer?
    @Environment(\.dismiss) var dismiss
    
    // 定义可用的速度选项供标记使用
    private let speedOptions: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("调语速")
                .font(.headline)
                .padding(.top)
            
            // 显示当前速度 - 使用简单格式显示，确保数字完整显示
            Text("\(String(format: "%.1f", playbackSpeed))")
                .font(.system(size: 30, weight: .bold))
                .padding()
                .foregroundColor(.red)
                .frame(width: 100, height: 100) // 增大圆圈确保数字完整显示
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.1))
                )
            
            // 滑动条指示点
            HStack {
                ForEach(speedOptions, id: \.self) { speed in
                    Spacer()
                    Circle()
                        .fill(abs(playbackSpeed - speed) < 0.05 ? Color.red : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                    Spacer()
                }
            }
            
            // 滑动条
            Slider(value: $playbackSpeed, in: 0.5...4.0, step: 0.1)
                .accentColor(.red)
                .onChange(of: playbackSpeed) { newValue in
                    // 设置朗读速度
                    synthesizer?.setPlaybackRate(Float(newValue))
                }
                .padding(.horizontal)
            
            // 速度标签 - 确保数字完整显示
            HStack {
                ForEach(speedOptions, id: \.self) { speed in
                    Text("\(speed, specifier: "%.1f")")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // 关闭按钮 - 修复关闭功能
            Button(action: {
                dismiss() // 显式调用dismiss关闭弹窗
            }) {
                Text("关闭")
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle()) // 使用简单按钮样式避免默认样式冲突
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 350)
        .background(Color.white)
        .cornerRadius(16)
    }
}

// 章节列表视图（简化版）
struct ChapterListView: View {
    var body: some View {
        VStack {
            Text("章节列表")
                .font(.headline)
                .padding()
            
            // 实际应用中，应从文档中提取章节列表
            Text("该文档未提供章节信息")
                .foregroundColor(.gray)
                .padding()
            
            Button("取消") {}
                .padding()
        }
        .frame(width: 250, height: 300)
    }
}

// 字体大小选项视图
struct FontSizeOptionsView: View {
    @Binding var fontSize: FontSize
    
    var body: some View {
        VStack(spacing: 10) {
            Text("字体大小")
                .font(.headline)
                .padding(.top)
            
            ForEach(FontSize.allCases) { size in
                Button(action: {
                    fontSize = size
                }) {
                    HStack {
                        Text(size.rawValue)
                            .font(.system(size: size.size))
                        
                        Spacer()
                        
                        if size == fontSize {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(size == fontSize ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button("取消") {}
                .padding()
        }
        .padding()
        .frame(width: 200)
    }
}

// 辅助扩展
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// 播放模式枚举
enum PlayMode: String, CaseIterable, Identifiable {
    case sequential = "顺序播放"
    case loop = "循环播放"
    case singleChapter = "单章播放"
    
    var id: String { self.rawValue }
}

// 字体大小枚举
enum FontSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"
    case extraLarge = "特大"
    
    var id: String { self.rawValue }
    
    var size: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 18
        case .large: return 22
        case .extraLarge: return 26
        }
    }
}

// 定时选项枚举
enum TimerOption: Int, CaseIterable, Identifiable {
    case off = 0
    case chapterEnd = 1
    case min10 = 10
    case min20 = 20
    case min30 = 30
    case min60 = 60
    case min90 = 90
    case custom = -1
    
    var id: Int { self.rawValue }
    
    var displayText: String {
        switch self {
        case .off: return "不开启"
        case .chapterEnd: return "播完本章"
        case .min10: return "10分钟后"
        case .min20: return "20分钟后"
        case .min30: return "30分钟后"
        case .min60: return "60分钟后"
        case .min90: return "90分钟后"
        case .custom: return "自定义"
        }
    }
}

// 定时选项视图 - 修改为与其他弹窗一致的风格
struct TimerOptionsView: View {
    @Binding var selectedOption: TimerOption
    
    var body: some View {
        VStack(spacing: 10) {
            Text("定时关闭")
                .font(.headline)
                .padding(.top)
            
            ForEach(TimerOption.allCases) { option in
                Button(action: {
                    selectedOption = option
                    // 在实际应用中这里应该设置定时器
                }) {
                    HStack {
                        Text(option.displayText)
                        
                        Spacer()
                        
                        if option == selectedOption {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(option == selectedOption ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button("取消") {}
                .padding()
        }
        .padding()
        .frame(width: 200)
    }
}

// 预览
struct DocumentReaderView_Previews: PreviewProvider {
    static var previews: some View {
        DocumentReaderView(
            documentTitle: "《极品家丁》", 
            document: Document(
                title: "极品家丁", 
                fileName: "极品家丁.txt", 
                fileURL: URL(fileURLWithPath: ""), 
                fileType: .txt,
                fileHash: "dummyHashForPreview"
            ), 
            viewModel: DocumentsViewModel()
        )
    }
} 
