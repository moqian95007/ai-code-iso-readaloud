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
    @State private var loadingStatusText: String = ""
    @State private var loadingProgress: Double = 0.0
    @State private var currentChapterIndex: Int = 0
    @State private var scrollToTop: Bool = false
    @State private var activeChapterIndex: Int = 0
    @State private var currentScrollViewProxy: ScrollViewProxy?
    @State private var lastScrollPosition: Int = 0
    @State private var scrollDebounceTimer: Timer?
    
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
    
    var synth: SpeechSynthesizer {
        return synthesizer
    }
    
    private var currentChapterDisplayText: String {
        // 添加静态缓存
        struct Cache {
            static var lastText: String = "无章节信息"
            static var lastChapterIndex: Int = -1
            static var lastChapterCount: Int = 0
        }
        
        if let synthesizer = playbackManager.synthesizer {
            let index = synthesizer.getCurrentChapterIndex()
            
            // 只在章节索引变化时才调用 getChapters
            if Cache.lastChapterIndex != index {
                let chapters = synthesizer.getChapters()
                
                if !chapters.isEmpty && index >= 0 && index < chapters.count {
                    // 更新缓存
                    Cache.lastChapterIndex = index
                    Cache.lastChapterCount = chapters.count
                    Cache.lastText = "\(index+1)/\(chapters.count): \(chapters[index].title)"
                    
                    // 更新当前章节索引
                    DispatchQueue.main.async {
                        if currentChapterIndex != index {
                            currentChapterIndex = index
                        }
                    }
                }
            }
            
            return Cache.lastText
        }
        
        return "无章节信息"
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
            ScrollViewReader { proxy in
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
                                // 添加章节标题显示
                                if !synth.getChapters().isEmpty {
                                    // 只获取一次章节索引
                                    let chapterIndex = synth.getCurrentChapterIndex()
                                    // 缓存当前章节列表
                                    let currentChapters = synth.getChapters()
                                    
                                    if chapterIndex >= 0 && chapterIndex < currentChapters.count {
                                        Text(currentChapters[chapterIndex].title)
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                            .padding(.bottom, 5)
                                            .id("chapter_title_\(chapterIndex)")
                                    }
                                }
                                
                                if synth.fullText.isEmpty {
                                    // 文本为空的情况
                                    Text("正在加载文档内容...")
                                        .foregroundColor(.gray)
                                        .italic()
                                } else if !synth.getChapters().isEmpty {
                                    let chapterIndex = synth.getCurrentChapterIndex()
                                    if chapterIndex >= 0 && chapterIndex < synth.getChapters().count {
                                        let chapter = synth.getChapters()[chapterIndex]
                                        let chapterContent = chapter.extractContent(from: synth.fullText)
                                        
                                        // 检查章节内容是否为空
                                        let trimmedContent = chapterContent.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmedContent.isEmpty {
                                            // 创建高亮文本
                                            VStack(alignment: .leading, spacing: 0) {
                                                // 显示章节内容
                                                if synth.getCurrentChapterContent().isEmpty && !synth.fullText.isEmpty {
                                                    // 备用显示方式，避免无文本情况
                                                    Text("正在加载章节内容...")
                                                        .font(.system(size: fontSize.size))
                                                        .foregroundColor(.gray)
                                                        .padding()
                                                    
                                                    // 尝试直接显示当前章节
                                                    let chapterIndex = synth.getCurrentChapterIndex()
                                                    if chapterIndex >= 0 && chapterIndex < synth.getChapters().count {
                                                        let chapter = synth.getChapters()[chapterIndex]
                                                        if chapter.startIndex < synth.fullText.count && chapter.endIndex <= synth.fullText.count {
                                                            let startIdx = synth.fullText.index(synth.fullText.startIndex, offsetBy: chapter.startIndex)
                                                            let endIdx = synth.fullText.index(synth.fullText.startIndex, offsetBy: chapter.endIndex)
                                                            let chapterText = String(synth.fullText[startIdx..<endIdx])
                                                            
                                                            if !chapterText.isEmpty {
                                                                Text(chapterText)
                                                                    .font(.system(size: fontSize.size))
                                                                    .padding()
                                                                    .id("direct_chapter_text_\(chapterIndex)")
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    // 标准的高亮文本显示
                                                    HighlightedTextView(
                                                        text: chapterContent,
                                                        highlightStart: synth.currentReadingCharacterIndex,
                                                        highlightLength: synth.currentReadingCharacterCount,
                                                        isPlaying: synth.isPlaying,
                                                        fontSize: fontSize.size,
                                                        onTapToSpeak: { tapRatio in
                                                            // 处理点击事件
                                                            handleTextTapByRatio(chapter: chapter, tapRatio: tapRatio)
                                                        }
                                                    )
                                                    .id("chapter_content_\(chapterIndex)_highlight_\(synth.currentReadingCharacterIndex)")
                                                    .onReceive(synth.objectWillChange) { _ in
                                                        // 强制视图刷新
                                                        print("【HighlightedTextView】接收到更新通知")
                                                    }
                                                }
                                            }
                                            .frame(minHeight: 400) // 确保有足够的垂直空间
                                            .background(Color.white.opacity(0.01)) // 添加微小背景以确保整个区域可见
                                        } else {
                                            // 章节内容为空时显示友好提示
                                            VStack(spacing: 10) {
                                                Image(systemName: "doc.text.magnifyingglass")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(.orange)
                                                
                                                Text("章节 \(chapter.title) 内容为空")
                                                    .font(.headline)
                                                    .foregroundColor(.orange)
                                                
                                                Text("此章节可能是目录或分隔符，您可以跳转到下一章继续阅读。")
                                                    .font(.subheadline)
                                                    .foregroundColor(.gray)
                                                    .multilineTextAlignment(.center)
                                                    .padding(.horizontal)
                                                
                                                // 添加快速跳转按钮
                                                if chapterIndex < synth.getChapters().count - 1 {
                                                    Button(action: {
                                                        synth.nextChapter()
                                                    }) {
                                                        HStack {
                                                            Text("跳转到下一章")
                                                            Image(systemName: "arrow.right.circle.fill")
                                                        }
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 10)
                                                        .background(Color.blue)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(20)
                                                    }
                                                    .padding(.top)
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(30)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(10)
                                        }
                                    } else {
                                        // 章节索引无效的情况
                                        Text("章节信息错误，无法显示内容")
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    // 没有章节但有文本内容时，显示当前位置附近的一大段文本
                                    // 显示更多内容而不仅仅是500字符
                                    let currentPosition = synth.currentPosition
                                    let startIndex = max(0, Int(currentPosition * Double(synth.fullText.count)) - 1000)
                                    let endIndex = min(synth.fullText.count, startIndex + 3000) // 显示3000字符而不是500
                                    
                                    let textStartIndex = synth.fullText.index(synth.fullText.startIndex, offsetBy: startIndex)
                                    let textEndIndex = synth.fullText.index(synth.fullText.startIndex, offsetBy: endIndex)
                                    let displayText = String(synth.fullText[textStartIndex..<textEndIndex])
                                    
                                    Text(displayText)
                                        .font(.system(size: fontSize.size))
                                        .foregroundColor(.black)
                                        .lineSpacing(5)
                                        .background(Color(.systemYellow).opacity(0.1))
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
                            .cornerRadius(10)
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
                    .onChange(of: currentChapterIndex) { newChapterIndex in
                        // 检测章节变化，自动滚动到章节开头
                        if activeChapterIndex != newChapterIndex {
                            activeChapterIndex = newChapterIndex
                            
                            // 滚动到章节标题位置
                            withAnimation {
                                proxy.scrollTo("chapter_title_\(newChapterIndex)", anchor: .top)
                            }
                            
                            print("【滚动控制】检测到章节变化，滚动到章节\(newChapterIndex + 1)开头")
                        }
                    }
                }
                .padding()
                .onAppear {
                    // 在这里保存滚动视图代理
                    self.currentScrollViewProxy = proxy
                    
                    // 延迟一点执行，确保文档加载完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("【视图刷新】文档阅读视图已出现，强制刷新显示")
                        
                        // 确保章节内容已正确加载
                        if self.synthesizer.currentText.isEmpty && !self.synthesizer.fullText.isEmpty {
                            print("【视图刷新】检测到内容未显示，尝试强制更新显示")
                            self.synthesizer.updateCurrentTextDisplay()
                            
                            // 再次延迟更新，确保内容显示
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                // 尝试重新获取当前章节并显示
                                let currentIndex = self.synthesizer.getCurrentChapterIndex()
                                if currentIndex >= 0 && currentIndex < self.synthesizer.getChapters().count {
                                    // 重新跳转到当前章节以触发显示
                                    self.synthesizer.jumpToChapter(currentIndex)
                                    print("【视图刷新】强制跳转到当前章节: \(currentIndex + 1)")
                                }
                                
                                // 强制更新UI
                                self.synthesizer.objectWillChange.send()
                            }
                        }
                    }
                }
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
                    
                    // 进度条 - 使用章节内部进度
                    if let synth = playbackManager.synthesizer, !synth.getChapters().isEmpty {
                        VStack(spacing: 2) {
                            // 添加章节指示
                            let chapterIndex = synth.getCurrentChapterIndex()
                            if chapterIndex >= 0 && chapterIndex < synth.getChapters().count {
                                Text("当前章：\(synth.getChapters()[chapterIndex].title)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            
                            // 章节内进度条 - 增强保护
                            ProgressSlider(value: Binding(
                                get: { synth.getCurrentChapterInternalProgress() },
                                set: { position in
                                    // 锁定当前章节索引
                                    let currentIndex = synth.getCurrentChapterIndex()
                                    
                                    // 如果位置接近1.0，限制最大值
                                    let safePosition = position >= 0.98 ? 0.95 : position
                                    
                                    // 设置进度
                                    synth.seekTo(position: safePosition)
                                    
                                    // 强制确保章节不会改变
                                    DispatchQueue.main.async {
                                        // 再次检查章节是否变化
                                        if currentIndex != synth.getCurrentChapterIndex() {
                                            print("【UI保护】检测到章节变化，强制恢复到原章节")
                                            synth.jumpToChapter(currentIndex)
                                            
                                            // 强制更新UI
                                            synth.objectWillChange.send()
                                        }
                                    }
                                }
                            )).id("progress_\(chapterIndex)")
                        }
                    } else {
                        // 无章节时使用全局进度
                        ProgressSlider(value: Binding(
                            get: { playbackManager.synthesizer?.currentPosition ?? 0 },
                            set: { position in
                                playbackManager.synthesizer?.seekTo(position: position)
                            }
                        ))
                    }
                    
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
                    
                    // 上一首按钮 - 修改为上一章
                    Button(action: {
                        if let synthesizer = playbackManager.synthesizer {
                            synthesizer.previousChapter()
                            // 记录跳转动作
                            print("【UI交互】上一章按钮被点击")
                        } else {
                            playPreviousDocument()
                        }
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
                    
                    // 下一首按钮 - 修改为下一章
                    Button(action: {
                        if let synthesizer = playbackManager.synthesizer {
                            synthesizer.nextChapter()
                            // 记录跳转动作
                            print("【UI交互】下一章按钮被点击")
                        } else {
                            playNextDocument()
                        }
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
                
                // 显示当前章节信息（无按钮，仅显示）
                HStack {
                    if let synthesizer = playbackManager.synthesizer, !synthesizer.getChapters().isEmpty {
                        ChapterIndicator()
                            .padding(.trailing, 4)
                        
                        Text(currentChapterDisplayText)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .id(currentChapterIndex) // 强制在章节索引变化时刷新视图
                .padding(.top, 5)
                
                // 其他控制按钮 - 完全重写
                HStack(spacing: 30) {
                    // 章节列表按钮
                    Button(action: {
                        print("【UI交互】章节按钮被点击")
                        
                        // 强制刷新章节列表
                        if let synthesizer = playbackManager.synthesizer {
                            print("【UI交互】检查章节状态: 共\(synthesizer.getChapters().count)章")
                            
                            // 确保章节数据已正确加载
                            if synthesizer.getChapters().isEmpty && !synthesizer.fullText.isEmpty {
                                print("【UI交互】章节为空但文本不为空，尝试重新分析")
                                // 对于大文本，异步处理以避免UI卡顿
                                DispatchQueue.global(qos: .userInitiated).async {
                                    let result = ChapterSegmenter.splitTextIntoParagraphs(synthesizer.fullText)
                                    
                                    // 过滤掉无效章节
                                    let filteredChapters = result.chapters.filter { chapter in
                                        let contentLength = chapter.endIndex - chapter.startIndex
                                        let isValidContent = contentLength > 100
                                        let isFormatPrefix = chapter.title.hasPrefix("Chapter_") && contentLength < 100
                                        
                                        return isValidContent && !isFormatPrefix
                                    }
                                    
                                    DispatchQueue.main.async {
                                        synthesizer.setChapters(filteredChapters)
                                        synthesizer.setParagraphs(result.paragraphs)
                                        print("【UI交互】重新分析完成，识别到\(filteredChapters.count)个章节")
                                        
                                        // 确保UI刷新后再显示章节列表
                                        synthesizer.objectWillChange.send()
                                        showChapterList = true
                                    }
                                }
                            } else {
                                // 章节数据已存在，直接显示
                                showChapterList = true
                            }
                        } else {
                            print("【UI交互】警告：synthesizer未初始化")
                            showChapterList = true
                        }
                    }) {
                        VStack {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 22))
                            Text("章节")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showChapterList, arrowEdge: .bottom) {
                        if let synthesizer = playbackManager.synthesizer {
                            VStack {
                                Text("章节列表 (\(synthesizer.getChapters().count)章)")
                                    .font(.headline)
                                    .padding()
                                
                                ChapterListView(synthesizer: synthesizer, showChapterList: $showChapterList)
                                    .onAppear {
                                        print("【UI交互】章节列表弹窗正在展示，章节数：\(synthesizer.getChapters().count)")
                                    }
                            }
                            .frame(minWidth: 300, minHeight: 400)
                        } else {
                            Text("无法加载章节信息")
                                .frame(minWidth: 300, minHeight: 100)
                                .padding()
                        }
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
                
                // 显示初步加载和章节分析提示
                DispatchQueue.main.async {
                    // 更新UI提示，显示正在处理
                    self.loadingStatusText = "正在提取文本..."
                }
                
                // 使用更高优先级的队列加载文档
                synthesizer.loadDocument(document, viewModel: viewModel, onProgress: { progress, message in
                    // 更新加载进度UI
                    DispatchQueue.main.async {
                        self.loadingProgress = progress
                        self.loadingStatusText = message
                    }
                })
                
                // 定期检查加载状态，而不是固定延迟
                var checkCount = 0
                Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    checkCount += 1
                    
                    // 检查文本是否已加载或者超时
                    if !synthesizer.fullText.isEmpty || checkCount > 20 {
                        timer.invalidate()
                        
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
            
            // 添加定时器定期更新当前章节索引
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if let synthesizer = playbackManager.synthesizer {
                    let newIndex = synthesizer.getCurrentChapterIndex()
                    if currentChapterIndex != newIndex {
                        currentChapterIndex = newIndex
                        print("【章节状态】章节已更新: \(newIndex+1)")
                    }
                } else {
                    // 如果synthesizer已不存在，停止定时器
                    timer.invalidate()
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
        .onChange(of: playbackManager.synthesizer?.currentReadingCharacterIndex) { _ in
            if let synth = playbackManager.synthesizer, synth.isPlaying {
                print("---高亮更新通知---")
                print("高亮位置: \(synth.currentReadingCharacterIndex)")
                print("高亮长度: \(synth.currentReadingCharacterCount)")
                print("是否正在播放: \(synth.isPlaying)")
                
                // 获取高亮的具体文本
                let chapterContent = synth.getCurrentChapterContent()
                if !chapterContent.isEmpty && 
                   synth.currentReadingCharacterIndex < chapterContent.count &&
                   synth.currentReadingCharacterIndex + synth.currentReadingCharacterCount <= chapterContent.count {
                    
                    let start = chapterContent.index(chapterContent.startIndex, 
                                                   offsetBy: synth.currentReadingCharacterIndex)
                    let end = chapterContent.index(start, 
                                                 offsetBy: synth.currentReadingCharacterCount)
                    if start < end {
                        let highlightedText = chapterContent[start..<end]
                        print("正在朗读: \"\(highlightedText)\"")
                    }
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
    
    private func getDisplayText() -> String {
        guard let synth = playbackManager.synthesizer else {
            return "合成器未初始化"
        }
        
        if synth.fullText.isEmpty {
            return "文档内容为空"
        }
        
        // 有章节信息时，显示当前章节的完整内容
        if !synth.getChapters().isEmpty {
            let chapterIndex = synth.getCurrentChapterIndex()
            if chapterIndex >= 0 && chapterIndex < synth.getChapters().count {
                let chapter = synth.getChapters()[chapterIndex]
                return chapter.extractContent(from: synth.fullText)
            }
        }
        
        // 没有章节信息时，显示当前位置周围的内容
        let currentPosition = synth.currentPosition
        let startPos = max(0, Int(currentPosition * Double(synth.fullText.count)) - 1000)
        let endPos = min(synth.fullText.count, startPos + 3000)
        
        let startIndex = synth.fullText.index(synth.fullText.startIndex, offsetBy: startPos)
        let endIndex = synth.fullText.index(synth.fullText.startIndex, offsetBy: endPos)
        
        return String(synth.fullText[startIndex..<endIndex])
    }
    
    // 添加平滑滚动方法
    private func smoothScrollToHighlight(scrollViewProxy: ScrollViewProxy, characterIndex: Int) {
        // 防抖动：取消先前的定时器
        scrollDebounceTimer?.invalidate()
        
        // 只有当滚动位置变化足够大时才滚动，减小阈值提高响应性
        if abs(characterIndex - lastScrollPosition) > 20 {
            // 使用定时器延迟滚动，避免频繁更新
            scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    // 确保滚动到一个存在的ID，并调整锚点位置确保高亮区域居中
                    let positionID = "chapter_content_\(currentChapterIndex)_highlight_\(characterIndex)"
                    scrollViewProxy.scrollTo(positionID, anchor: .center)
                    
                    print("【滚动控制】滚动到位置: \(characterIndex)")
                }
                lastScrollPosition = characterIndex
            }
        }
    }
    
    private func handleTextTap(chapter: Chapter, characterIndex: Int) {
        guard let synth = playbackManager.synthesizer else { return }
        
        // 计算点击位置在章节内的相对位置
        let chapterLength = chapter.endIndex - chapter.startIndex
        let relativePosition = Double(characterIndex) / Double(chapterLength)
        
        // 确保相对位置在0-1范围内
        let safeRelativePosition = max(0.0, min(1.0, relativePosition))
        
        print("【文本点击】点击章节: \(chapter.title), 字符索引: \(characterIndex), 相对位置: \(safeRelativePosition)")
        
        // 计算在全文中的绝对位置
        let chapterRange = chapter.endPosition - chapter.startPosition
        let absolutePosition = chapter.startPosition + (chapterRange * safeRelativePosition)
        
        // 设置当前位置
        synth.seekTo(position: safeRelativePosition)
        
        // 如果当前没有播放，则开始播放
        if !synth.isPlaying {
            synth.startSpeaking(from: absolutePosition)
            playbackManager.isPlaying = true
        }
    }
    
    private func handleTextTapByRatio(chapter: Chapter, tapRatio: Double) {
        guard let synth = playbackManager.synthesizer else { return }
        
        // 确保比例在0-1范围内，并增加额外保护避免触及章节边界
        // 将比例约束在0.01到0.90之间，防止意外触发章节跳转
        let safeRatio = max(0.01, min(0.90, tapRatio))
        
        print("【文本点击】点击章节: \(chapter.title), 原始比例: \(tapRatio), 安全比例: \(safeRatio)")
        
        // 计算在章节内的绝对位置 - 更加严格地限制范围
        let chapterRange = chapter.endPosition - chapter.startPosition
        // 确保位置在章节内部的安全范围内，远离边界
        let absolutePosition = chapter.startPosition + (chapterRange * safeRatio)
        
        // 进一步防范边界情况
        let minPosition = chapter.startPosition + 0.005  // 确保远离章节开始边界
        let maxPosition = chapter.endPosition - 0.005    // 确保远离章节结束边界
        let safeAbsolutePosition = max(minPosition, min(maxPosition, absolutePosition))
        
        print("【文本点击】计算位置 - 章节范围: \(chapter.startPosition) 到 \(chapter.endPosition), 计算位置: \(safeAbsolutePosition)")
        
        // 直接使用章节索引和相对位置，而不是全局位置
        let currentIndex = synth.getCurrentChapterIndex()
        if currentIndex != -1 {
            // 设置全局位置
            synth.currentPosition = safeAbsolutePosition
            
            // 强制设置确保当前章节匹配
            synth.forceSetCurrentChapterIndex(currentIndex)
            
            // 开始从新位置播放
            if synth.isPlaying {
                // 如果正在播放，先暂停
                synth.pauseSpeaking()
                
                // 短暂延迟后重新开始播放
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    synth.startSpeaking(from: safeAbsolutePosition)
                    self.playbackManager.isPlaying = true
                }
            } else {
                // 如果未播放，直接开始
                synth.startSpeaking(from: safeAbsolutePosition)
                self.playbackManager.isPlaying = true
            }
            
            // 强制发送通知确保UI更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                synth.objectWillChange.send()
            }
        }
    }
}

// 进度滑块
struct ProgressSlider: View {
    @Binding var value: Double
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    // 添加一个状态来跟踪当前章节
    @State private var currentChapterIndex: Int = -1
    
    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center) {
                // 左侧显示已播放时间
                Text(formatPlayedTime())
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
        .onAppear {
            // 初始检查章节
            updateChapterInfo()
        }
        // 使用条件视图而不是条件发布者
        .onChange(of: playbackManager.synthesizer?.currentPosition) { _ in
            // 当位置变化时检查章节
            updateChapterInfo()
        }
        // 添加另一个监听器用于章节变化
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // 定期检查章节变化
            updateChapterInfo()
        }
    }
    
    // 提取更新章节信息的逻辑到一个单独的方法
    private func updateChapterInfo() {
        if let synth = playbackManager.synthesizer {
            let newChapterIndex = synth.getCurrentChapterIndex()
            if currentChapterIndex != newChapterIndex {
                // 章节变化时强制更新进度值
                DispatchQueue.main.async {
                    // 章节变化时，先将进度条重置为0，然后再获取实际值
                    // 这确保了用户会看到进度条被重置
                    value = 0.0
                    
                    // 记录章节变化日志
                    print("【进度条】章节已变化: 从章节\(currentChapterIndex+1)到章节\(newChapterIndex+1)，重置进度")
                    
                    // 更新当前章节索引
                    currentChapterIndex = newChapterIndex
                    
                    // 短暂延迟后再获取实际章节内部进度
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // 使用章节内部进度
                        let internalProgress = synth.getCurrentChapterInternalProgress()
                        // 避免进度条跳到最后
                        let safeProgress = min(internalProgress, 0.02) // 确保新章节开始时进度最大只有2%
                        value = safeProgress
                        
                        print("【进度条】章节\(newChapterIndex+1)的实际内部进度: \(internalProgress)，调整后: \(safeProgress)")
                    }
                }
            }
        }
    }
    
    private func formatPlayedTime() -> String {
        guard let synth = playbackManager.synthesizer else {
            return "00:00"
        }
        
        // 获取当前章节
            let chapterIndex = synth.getCurrentChapterIndex()
        if !synth.getChapters().isEmpty && chapterIndex >= 0 && chapterIndex < synth.getChapters().count {
                let chapter = synth.getChapters()[chapterIndex]
            
            // 计算章节的估计总时长（假设阅读速度是每分钟500字）
            let chapterTextLength = chapter.endIndex - chapter.startIndex
            let totalSeconds = Double(chapterTextLength) / 500.0 * 60.0
            
            // 计算当前播放位置
            let playedSeconds = value * totalSeconds
            
            let minutes = Int(playedSeconds / 60)
                let seconds = Int(playedSeconds) % 60
                
                return String(format: "%02d:%02d", minutes, seconds)
        } else {
            // 默认显示
            return "00:00"
            }
        }
        
    private func formatTotalTime() -> String {
        guard let synth = playbackManager.synthesizer else {
        return "00:00"
    }
    
        // 获取当前章节
            let chapterIndex = synth.getCurrentChapterIndex()
        if !synth.getChapters().isEmpty && chapterIndex >= 0 && chapterIndex < synth.getChapters().count {
                let chapter = synth.getChapters()[chapterIndex]
                
            // 计算章节的估计总时长（假设阅读速度是每分钟500字）
            let chapterTextLength = chapter.endIndex - chapter.startIndex
            let totalSeconds = Double(chapterTextLength) / 500.0 * 60.0
                
            let minutes = Int(totalSeconds / 60)
                let seconds = Int(totalSeconds) % 60
                
                return String(format: "%02d:%02d", minutes, seconds)
        } else {
            // 默认显示
            return "00:00"
        }
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

// 添加章节跳转指示器
struct ChapterIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}

// 高亮文本视图
struct HighlightedTextView: View {
    let text: String
    let highlightStart: Int
    let highlightLength: Int
    let isPlaying: Bool
    let fontSize: CGFloat
    
    // 添加朗读控制回调
    var onTapToSpeak: ((Double) -> Void)? = nil
    
    var body: some View {
        // 移除GeometryReader，直接使用ScrollView
        ScrollView {
            Text(makeAttributedString())
                .font(.system(size: fontSize))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("highlight_\(highlightStart / 5)_\(highlightLength)")
                .contentShape(Rectangle()) // 确保整个区域可点击
                .onTapGesture { location in
                    // 使用更加安全的点击位置计算方法
                    // 避免基于总文本长度的估算，而是使用固定的相对视图高度计算
                    
                    // 计算点击在视图中的垂直比例，考虑点击位置的垂直位置
                    let viewHeight: CGFloat = 1000  // 使用一个适合的视图高度估算值
                    
                    // 点击比例计算 - 安全范围0.1-0.9
                    var ratio = Double(location.y / viewHeight)
                    
                    // 约束比例在安全范围内，避免触发章节边界
                    ratio = max(0.1, min(0.9, ratio))
                    
                    print("【点击事件】文本点击位置: \(location.y)，计算比例: \(ratio)")
                    
                    // 调用回调函数
                    onTapToSpeak?(ratio)
                }
                .padding(.bottom, 30) // 底部添加额外间距
        }
        .frame(minHeight: 300) // 设置最小高度确保有足够空间显示内容
    }
    
    private func makeAttributedString() -> AttributedString {
        var attributedString = AttributedString(text)
        
        // 设置基本文本属性
        attributedString.foregroundColor = .black
        
        // 如果正在播放且高亮位置有效，则设置高亮
        if isPlaying && highlightStart >= 0 && highlightStart < text.count {
            // 确保高亮范围不超出文本长度
            let safeHighlightStart = min(highlightStart, text.count - 1)
            // 增加高亮长度，确保用户能看到
            let safeHighlightLength = min(max(highlightLength, 10), text.count - safeHighlightStart)
            
            // 安全地创建索引范围
            if safeHighlightStart + safeHighlightLength <= text.count {
                let startIndex = text.index(text.startIndex, offsetBy: safeHighlightStart)
                let endIndex = text.index(text.startIndex, offsetBy: safeHighlightStart + safeHighlightLength)
                
                // 直接使用字符串索引创建AttributedString范围
                let startAttrIndex = AttributedString.Index(startIndex, within: attributedString)
                let endAttrIndex = AttributedString.Index(endIndex, within: attributedString)
                
                if let startAttrIndex = startAttrIndex, let endAttrIndex = endAttrIndex {
                    let range = startAttrIndex..<endAttrIndex
                    attributedString[range].backgroundColor = .yellow
                    attributedString[range].foregroundColor = .black
                    attributedString[range].font = .system(size: fontSize + 2, weight: .bold)
                }
            }
        }
        
        return attributedString
    }
} 
