import SwiftUI
import AVFoundation

/// 文章阅读和朗读的主视图
struct ArticleReaderView: View {
    // 文章数据
    let article: Article
    
    // 状态管理
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    // 弹窗状态
    @State private var showSpeedSelector: Bool = false
    @State private var showVoiceSelector: Bool = false
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    
    // 应用启动状态标志
    @State private var isAppLaunch: Bool = true
    
    // 语音代理
    @ObservedObject private var speechDelegate = SpeechDelegate.shared
    
    // 错误提示状态
    @State private var showVoiceLanguageError: Bool = false
    
    var body: some View {
        VStack {
            // 标题
            Text(article.title)
                .font(.title)
                .padding()
                .lineLimit(1)
                .truncationMode(.tail)
            
            // 文本展示区
            ScrollViewReader { scrollView in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // 将长文本分成段落
                        let paragraphs = article.content.components(separatedBy: "\n\n")
                        
                        // 遍历段落并分别处理
                        ForEach(0..<paragraphs.count, id: \.self) { index in
                            let paragraph = paragraphs[index]
                            let paragraphId = "paragraph_\(index)"
                            
                            // 计算该段落是否包含当前朗读的文本
                            let containsHighlight = speechManager.paragraphContainsHighlight(
                                paragraph: paragraph, 
                                fullText: article.content
                            )
                            
                            Text(paragraph)
                                .font(.system(size: themeManager.fontSize))
                                .padding(5)
                                .background(themeManager.highlightBackgroundColor(isHighlighted: containsHighlight))
                                .id(paragraphId)
                                .onTapGesture {
                                    handleTextTap(paragraphIndex: index, paragraph: paragraph)
                                }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(themeManager.scrollViewBackgroundColor())
                .cornerRadius(10)
                .padding()
                .onChange(of: speechDelegate.highlightRange) { _ in
                    scrollToCurrentParagraph(scrollView: scrollView)
                }
            }
            
            // 进度控制区域
            VStack(spacing: 5) {
                // 上次播放位置恢复提示
                if speechManager.isResuming && !speechManager.isPlaying && isAppLaunch {
                    HStack {
                        Button(action: {
                            speechManager.startSpeakingFromPosition(speechManager.currentPlaybackPosition)
                            isAppLaunch = false
                        }) {
                            Label("继续上次播放", systemImage: "play.circle")
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // 从头开始按钮
                        Button(action: {
                            // 重置恢复状态并清除保存的进度
                            speechManager.stopSpeaking()
                            isAppLaunch = false
                        }) {
                            Text("从头开始")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 5)
                }
                
                // 时间显示
                HStack {
                    Text(speechManager.formatTime(speechManager.currentTime))
                        .font(.caption)
                    Spacer()
                    Text(speechManager.formatTime(speechManager.totalTime))
                        .font(.caption)
                }
                
                // 进度条和快进/快退按钮
                HStack {
                    // 后退15秒按钮
                    Button(action: {
                        speechManager.skipBackward(seconds: 15)
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
                    }
                    .padding(.trailing, 8)
                    
                    // 进度条，支持拖动
                    Slider(
                        value: $speechManager.currentProgress,
                        in: 0...1,
                        onEditingChanged: { editing in
                            speechManager.isDragging = editing
                            
                            if !editing {
                                speechManager.seekToProgress(speechManager.currentProgress)
                            }
                        }
                    )
                    .accentColor(themeManager.isDarkMode ? .white : .blue)
                    
                    // 前进15秒按钮
                    Button(action: {
                        speechManager.skipForward(seconds: 15)
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
            
            // 播放控制区
            HStack {
                // 语速调节按钮
                Button(action: {
                    showSpeedSelector = true
                }) {
                    HStack {
                        Image(systemName: "speedometer")
                            .font(.system(size: 22))
                        Text("\(String(format: "%.1f", speechManager.selectedRate))x")
                            .font(.system(size: 16))
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .padding(.trailing, 12)
                
                // 播放/暂停按钮
                Button(action: {
                    if speechManager.isPlaying {
                        speechManager.pauseSpeaking()
                    } else {
                        // 检查语音语言是否匹配
                        let articleLanguage = article.detectLanguage()
                        if let voice = speechManager.getSelectedVoice() {
                            let isCompatible = isLanguageCompatible(voiceLanguage: voice.language, articleLanguage: articleLanguage)
                            if !isCompatible {
                                // 显示错误提示
                                showVoiceLanguageError = true
                                return
                            }
                        }
                        
                        if speechManager.isResuming {
                            speechManager.startSpeakingFromPosition(speechManager.currentPlaybackPosition)
                        } else {
                            speechManager.startSpeaking()
                        }
                        isAppLaunch = false
                    }
                }) {
                    Image(systemName: speechManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(themeManager.isDarkMode ? .white : .blue)
                }
                
                // 按钮文字说明
                Text(speechManager.isPlaying ? "暂停" : (speechManager.isResuming ? "继续" : "播放"))
                    .font(.headline)
                    .padding(.leading, 5)
            }
            .padding(.bottom, 15)
            
            // 设置按钮区域
            HStack(spacing: 20) {
                // 日间/夜间模式切换按钮
                Button(action: {
                    themeManager.toggleDarkMode()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 18))
                        
                        Text(themeManager.isDarkMode ? "夜间" : "日间")
                            .font(.system(size: 16))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 字体大小切换按钮
                Button(action: {
                    themeManager.nextFontSize()
                }) {
                    HStack(spacing: 5) {
                        // 显示单个"A"，大小根据当前字体选项动态调整
                        switch themeManager.fontSizeOption {
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
                        
                        Text(themeManager.fontSizeOption.rawValue)
                            .font(.system(size: 16))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 切换主播按钮
                Button(action: {
                    // 获取所有可用的语音列表
                    let allVoices = AVSpeechSynthesisVoice.speechVoices()
                    print("获取到 \(allVoices.count) 个语音")
                    
                    // 直接设置可用语音列表
                    self.availableVoices = allVoices
                    print("设置到 availableVoices: \(self.availableVoices.count) 个语音")
                    
                    // 如果没有选择语音或选择的语音不在可用语音中，默认选择第一个语音
                    if speechManager.selectedVoiceIdentifier.isEmpty || !self.availableVoices.contains(where: { $0.identifier == speechManager.selectedVoiceIdentifier }) {
                        if let defaultVoice = self.availableVoices.first {
                            speechManager.selectedVoiceIdentifier = defaultVoice.identifier
                        }
                    }
                    
                    // 显示语音选择器
                    DispatchQueue.main.async {
                        self.showVoiceSelector = true
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.wave.2")
                            .font(.system(size: 18))
                        
                        Text("主播")
                            .font(.system(size: 16))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding(.bottom, 30)
        }
        .onAppear {
            // 初始化语音管理器
            speechManager.setup(for: article)
            
            // 通知已进入播放界面
            NotificationCenter.default.post(name: Notification.Name("EnterPlaybackView"), object: nil)
            
            // 保存最近播放的文章ID
            UserDefaults.standard.set(article.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
        }
        .onDisappear {
            // 通知已离开播放界面
            NotificationCenter.default.post(name: Notification.Name("ExitPlaybackView"), object: nil)
            
            // 清理资源
            speechManager.cleanup()
        }
        .sheet(isPresented: $showSpeedSelector) {
            SpeedSelectorView(selectedRate: $speechManager.selectedRate, showSpeedSelector: $showSpeedSelector)
                .onDisappear {
                    speechManager.applyNewSpeechRate()
                }
        }
        .sheet(isPresented: $showVoiceSelector) {
            VoiceSelectorView(
                selectedVoiceIdentifier: $speechManager.selectedVoiceIdentifier, 
                showVoiceSelector: $showVoiceSelector,
                availableVoices: availableVoices,
                articleLanguage: article.detectLanguage()
            )
            .onDisappear {
                speechManager.applyNewVoice()
            }
        }
        .background(themeManager.backgroundColor())
        .foregroundColor(themeManager.foregroundColor())
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .alert("提示", isPresented: $showVoiceLanguageError) {
            Button("确定", role: .cancel) { }
        } message: {
            let languageNames = [
                "zh": "中文",
                "en": "英文",
                "ja": "日文",
                "ko": "韩文",
                "fr": "法文",
                "de": "德文",
                "es": "西班牙文",
                "it": "意大利文",
                "ru": "俄文"
            ]
            let articleLanguage = article.detectLanguage()
            let languageName = languageNames[articleLanguage] ?? articleLanguage
            Text("请选择\(languageName)主播朗读\(languageName)文章")
        }
    }
    
    // 处理文本点击事件
    private func handleTextTap(paragraphIndex: Int, paragraph: String) {
        var startPosition = 0
        let paragraphs = article.content.components(separatedBy: "\n\n")
        
        for i in 0..<paragraphIndex {
            startPosition += paragraphs[i].count + 2  // +2 for "\n\n"
        }
        
        if speechManager.isPlaying {
            speechManager.stopSpeaking()
        }
        
        speechManager.startSpeakingFromPosition(startPosition)
    }
    
    // 滚动到当前高亮段落
    private func scrollToCurrentParagraph(scrollView: ScrollViewProxy) {
        // 只有在正在朗读状态才进行滚动
        if speechDelegate.isSpeaking {
            if let paragraphId = getCurrentParagraphId(range: speechDelegate.highlightRange) {
                withAnimation {
                    scrollView.scrollTo(paragraphId, anchor: UnitPoint(x: 0, y: 0.25))
                }
            }
        }
    }
    
    // 查找当前高亮范围所在的段落ID
    private func getCurrentParagraphId(range: NSRange) -> String? {
        let paragraphs = article.content.components(separatedBy: "\n\n")
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
    
    // 检查语音语言是否与文章语言兼容
    private func isLanguageCompatible(voiceLanguage: String, articleLanguage: String) -> Bool {
        // 提取语言代码（如 "zh-CN" 中的 "zh"）
        let voiceMainLanguage = voiceLanguage.split(separator: "-").first?.lowercased() ?? voiceLanguage.lowercased()
        let articleMainLanguage = articleLanguage.split(separator: "-").first?.lowercased() ?? articleLanguage.lowercased()
        
        // 如果主要语言代码相同，则认为兼容
        return voiceMainLanguage == articleMainLanguage
    }
} 