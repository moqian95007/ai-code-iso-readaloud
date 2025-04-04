import SwiftUI
import AVFoundation
import Combine

/// 文章阅读和朗读的主视图
struct ArticleReaderView: View {
    // 文章数据
    @State private var article: Article
    @State private var currentListArticles: [Article] = []
    
    // 选中的列表ID (可选)
    var selectedListId: UUID? = nil
    
    // 是否使用上一次的播放列表
    var useLastPlaylist: Bool = false
    
    // 用于防止重复处理PlayNextArticle通知
    private static var lastPlayNextTime: Date = Date(timeIntervalSince1970: 0)
    
    // 用于防止重复调用playNextArticle
    private static var lastArticlePlayTime: Date = Date(timeIntervalSince1970: 0)
    
    // 初始化方法
    init(article: Article, selectedListId: UUID? = nil, useLastPlaylist: Bool = false) {
        self._article = State(initialValue: article)
        self.selectedListId = selectedListId
        self.useLastPlaylist = useLastPlaylist
    }
    
    // 状态管理
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var articleManager = ArticleManager()
    @StateObject private var listManager = ArticleListManager()
    @StateObject private var timerManager = TimerManager.shared
    
    // 弹窗状态
    @State private var showSpeedSelector: Bool = false
    @State private var showVoiceSelector: Bool = false
    @State private var showArticleList: Bool = false
    @State private var showTimerSheet: Bool = false
    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    
    // 应用启动状态标志
    @State private var isAppLaunch: Bool = true
    
    // 语音代理
    @ObservedObject private var speechDelegate = SpeechDelegate.shared
    
    // 错误提示状态
    @State private var showVoiceLanguageError: Bool = false
    
    // 用于取消通知订阅
    @State private var playNextSubscription: AnyCancellable?
    @State private var timerCompletedSubscription: AnyCancellable?
    
    // 获取当前列表中的所有文章
    private var listArticles: [Article] {
        // 如果有指定的列表ID，优先使用该列表
        if let listId = selectedListId {
            // 如果是默认的"所有文章"列表
            if listManager.lists.first?.id == listId {
                return articleManager.articles
            }
            
            // 否则获取该列表中的所有文章
            if let list = listManager.lists.first(where: { $0.id == listId }) {
                // 根据ID获取文章对象
                return list.articleIds.compactMap { id in
                    articleManager.findArticle(by: id)
                }
            }
        }
        
        // 如果没有指定列表或找不到指定列表，使用原来的逻辑
        // 如果当前文章没有所属列表，就只显示当前文章
        let containingLists = listManager.listsContainingArticle(articleId: article.id)
        
        // 如果文章不属于任何列表或者只属于默认的"所有文章"列表，就只显示当前文章
        if containingLists.isEmpty || (containingLists.count == 1 && containingLists[0].id == listManager.lists.first?.id) {
            return [article]
        }
        
        // 获取文章所属的非默认列表中的第一个
        let firstNonDefaultList = containingLists.first { $0.id != listManager.lists.first?.id }
        
        // 获取该列表中的所有文章
        if let listId = firstNonDefaultList?.id {
            // 找到列表中所有文章的ID
            if let list = listManager.lists.first(where: { $0.id == listId }) {
                // 根据ID获取文章对象
                return list.articleIds.compactMap { id in
                    articleManager.findArticle(by: id)
                }
            }
        }
        
        // 默认情况下只显示当前文章
        return [article]
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
                Spacer()
                
                // 语速调节按钮
                Button(action: {
                    showSpeedSelector = true
                }) {
                    VStack {
                        Image(systemName: "speedometer")
                            .font(.system(size: 22))
                        Text("\(String(format: "%.1f", speechManager.selectedRate))x")
                            .font(.system(size: 16))
                    }
                    .frame(width: 70)  // 设置固定宽度
                    .padding(8)
                }
                
                Spacer()
                
                // 上一篇按钮
                Button(action: {
                    playPreviousArticle()
                }) {
                    Image(systemName: "backward.end.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(themeManager.isDarkMode ? .white : .blue)
                }
                .padding(.trailing, 20)
                
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
                        
                        // 点击播放按钮时设置手动暂停标志为 true
                        // 这可以防止系统将从暂停位置继续播放误识别为播放完成
                        speechDelegate.wasManuallyPaused = true
                        
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
                
                // 下一篇按钮
                Button(action: {
                    playNextArticle()
                }) {
                    Image(systemName: "forward.end.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(themeManager.isDarkMode ? .white : .blue)
                }
                .padding(.leading, 20)
                
                Spacer()
                
                // 播放模式切换按钮
                Button(action: {
                    speechManager.togglePlaybackMode()
                }) {
                    VStack {
                        Image(systemName: speechManager.playbackMode.iconName)
                            .font(.system(size: 22))
                        Text(speechManager.playbackMode.rawValue)
                            .font(.system(size: 16))
                    }
                    .frame(width: 70)  // 设置固定宽度
                    .padding(8)
                }
                
                Spacer()
            }
            .padding(.bottom, 15)
            
            // 设置按钮区域
            HStack(spacing: 20) {
                // 列表按钮
                Button(action: {
                    // 确保已加载文章
                    articleManager.loadArticles()
                    showArticleList = true
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 18))
                        
                        Text("列表")
                            .font(.system(size: 14))
                    }
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 定时关闭按钮
                Button(action: {
                    showTimerSheet = true
                }) {
                    VStack(spacing: 5) {
                        // 根据定时器状态显示不同图标
                        if timerManager.isTimerActive {
                            ZStack {
                                Image(systemName: "timer")
                                    .font(.system(size: 18))
                                
                                // 如果定时器激活，显示时间或标记
                                if timerManager.selectedOption == .afterChapter {
                                    Text("章")
                                        .font(.system(size: 9))
                                        .offset(x: 0, y: 2)
                                }
                            }
                        } else {
                            Image(systemName: "timer")
                                .font(.system(size: 18))
                        }
                        
                        // 显示定时状态或"定时"文字
                        if timerManager.isTimerActive {
                            if timerManager.selectedOption == .afterChapter {
                                Text("本章后")
                                    .font(.system(size: 14))
                            } else if !timerManager.formattedRemainingTime().isEmpty {
                                Text(timerManager.formattedRemainingTime())
                                    .font(.system(size: 14))
                                    .monospacedDigit()
                            } else {
                                Text("定时")
                                    .font(.system(size: 14))
                            }
                        } else {
                            Text("定时")
                                .font(.system(size: 14))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(timerManager.isTimerActive ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 日间/夜间模式切换按钮
                Button(action: {
                    themeManager.toggleDarkMode()
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: themeManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 18))
                        
                        Text(themeManager.isDarkMode ? "夜间" : "日间")
                            .font(.system(size: 14))
                    }
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 字体大小切换按钮
                Button(action: {
                    themeManager.nextFontSize()
                }) {
                    VStack(spacing: 5) {
                        // 使用固定大小的"A"
                        Text("A")
                            .font(.system(size: 22))
                        
                        Text(themeManager.fontSizeOption.rawValue)
                            .font(.system(size: 14))
                    }
                    .frame(width: 60, height: 60)
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
                    VStack(spacing: 5) {
                        Image(systemName: "person.wave.2")
                            .font(.system(size: 18))
                        
                        Text("主播")
                            .font(.system(size: 14))
                    }
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding(.bottom, 30)
        }
        .onAppear {
            print("========= ArticleReaderView.onAppear =========")
            
            // 添加状态变量防止过度频繁的调用
            struct AppearState {
                static var lastAppearTime: Date = Date(timeIntervalSince1970: 0)
                static var isInitializing: Bool = false
            }
            
            // 检查是否短时间内重复调用
            let now = Date()
            if now.timeIntervalSince(AppearState.lastAppearTime) < 0.5 && AppearState.isInitializing {
                print("短时间内重复进入onAppear，跳过初始化")
                print("==============================================")
                return
            }
            
            AppearState.lastAppearTime = now
            AppearState.isInitializing = true
            
            // 初始化语音管理器
            speechManager.setup(for: article)
            
            // 加载文章列表
            articleManager.loadArticles()
            
            // 通知已进入播放界面
            NotificationCenter.default.post(name: Notification.Name("EnterPlaybackView"), object: nil)
            
            // 保存最近播放的文章ID
            UserDefaults.standard.set(article.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
            
            // 设置播放列表
            let isUsingLastPlaylist = UserDefaults.standard.bool(forKey: "isUsingLastPlaylist")
            if ((useLastPlaylist || isUsingLastPlaylist) && !speechManager.lastPlayedArticles.isEmpty) {
                // 如果需要使用上一次的播放列表，且播放列表不为空
                print("使用上一次的播放列表")
                currentListArticles = speechManager.lastPlayedArticles
            } else {
                // 否则使用当前列表，检查SpeechManager是否已有播放列表
                if !useLastPlaylist && !isUsingLastPlaylist && !speechManager.lastPlayedArticles.isEmpty 
                   && speechManager.lastPlayedArticles.contains(where: { $0.id == article.id }) {
                    // 如果当前文章在已有播放列表中，且不是来自上次播放列表的请求，则使用SpeechManager中的播放列表
                    print("保留SpeechManager中已有的播放列表")
                    currentListArticles = speechManager.lastPlayedArticles
                } else {
                    // 使用从列表计算得到的播放列表
                    print("使用当前列表计算的播放列表")
                    currentListArticles = listArticles
                }
            }
            print("设置当前播放列表: \(currentListArticles.count)篇文章")
            
            // 更新speechManager中的播放列表
            speechManager.updatePlaylist(currentListArticles)
            print("更新SpeechManager播放列表完成")
            
            // 监听播放下一篇文章的通知
            playNextSubscription = NotificationCenter.default.publisher(for: Notification.Name("PlayNextArticle"))
                .receive(on: RunLoop.main)
                .sink { _ in
                    print("收到PlayNextArticle通知，准备播放下一篇")
                    
                    // 防止重复快速处理
                    let now = Date()
                    if now.timeIntervalSince(ArticleReaderView.lastPlayNextTime) < 2.0 {
                        print("两次PlayNextArticle触发间隔太短，忽略此次请求")
                        return
                    }
                    ArticleReaderView.lastPlayNextTime = now
                    
                    // 特殊处理：列表中只有一篇文章的情况
                    if self.currentListArticles.count == 1 && self.speechManager.playbackMode == .listRepeat {
                        print("列表中只有一篇文章，直接从头开始播放当前文章")
                        
                        // 停止当前所有播放
                        self.speechManager.stopSpeaking(resetResumeState: true)
                        
                        // 延迟加长到2秒，确保之前的播放状态完全重置
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            // 确保语音代理状态已完全重置
                            self.speechDelegate.startPosition = 0
                            self.speechDelegate.wasManuallyPaused = false
                            // 使用公共方法重置播放标志
                            self.speechManager.resetPlaybackFlags()
                            
                            // 从头开始播放
                            self.speechManager.startSpeaking()
                            print("重新开始播放唯一文章")
                        }
                    } else {
                        // 有多篇文章，正常处理下一篇
                        self.playNextArticle()
                    }
                }
            
            // 检查是否是从列表循环模式导航而来
            let isFromListRepeat = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isFromListRepeat)
            
            // 获取是否是通过浮动球进入
            let isFromFloatingBall = UserDefaults.standard.bool(forKey: "isFromFloatingBall")
            
            print("是否从列表循环跳转而来: \(isFromListRepeat)")
            print("是否从浮动球进入: \(isFromFloatingBall)")
            
            // 只有在从列表循环模式导航且非浮动球进入时才自动播放
            if isFromListRepeat && speechManager.playbackMode == .listRepeat && !isFromFloatingBall {
                print("检测到是从列表循环跳转而来，准备自动开始播放")
                // 重置标记
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isFromListRepeat)
                
                // 增加延迟时间到1.2秒，确保视图已完全加载且前一个播放已完全停止
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    // 确保重置所有状态标志
                    self.speechDelegate.startPosition = 0
                    self.speechDelegate.wasManuallyPaused = false
                    // 使用公共方法重置播放标志
                    self.speechManager.resetPlaybackFlags()
                    
                    print("开始自动播放")
                    // 确保从头开始播放
                    self.speechManager.startSpeaking()
                }
            }
            
            // 重置浮动球标记
            if isFromFloatingBall {
                UserDefaults.standard.set(false, forKey: "isFromFloatingBall")
            }
            
            // 打印列表循环状态
            if currentListArticles.count == 1 {
                print("⚠️ 注意：列表中只有一篇文章，列表循环将重新播放同一篇文章")
            }
            
            // 监听定时器完成通知
            timerCompletedSubscription = NotificationCenter.default.publisher(for: Notification.Name("TimerCompleted"))
                .receive(on: RunLoop.main)
                .sink { _ in
                    print("定时器完成，已停止播放")
                }
            
            // 重置初始化标志，允许下次初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                AppearState.isInitializing = false
            }
            
            print("==============================================")
        }
        .onDisappear {
            print("========= ArticleReaderView.onDisappear =========")
            
            // 在页面消失时不要立即处理，而是延迟一段时间，防止短暂过渡导致的错误处理
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 仅当页面真的已经消失时（导航已完成）才发送通知
                // 通知已离开播放界面
                NotificationCenter.default.post(name: Notification.Name("ExitPlaybackView"), object: nil)
                
                // 重置使用上次播放列表的标志
                UserDefaults.standard.set(false, forKey: "isUsingLastPlaylist")
                
                // 清理资源
                self.speechManager.cleanup()
            }
            
            // 取消通知订阅
            playNextSubscription?.cancel()
            timerCompletedSubscription?.cancel()
            
            print("==============================================")
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
        .sheet(isPresented: $showArticleList) {
            ArticleListPopoverView(
                articles: currentListArticles,
                currentArticleId: article.id,
                onSelectArticle: { selectedArticle in
                    // 打开选中的文章
                    if selectedArticle.id != article.id {
                        // 改为本地切换而非发送通知
                        // 停止当前播放
                        if speechManager.isPlaying {
                            speechManager.stopSpeaking(resetResumeState: true)
                        }
                        
                        // 重置播放状态
                        speechDelegate.startPosition = 0
                        speechDelegate.wasManuallyPaused = false
                        speechManager.resetPlaybackFlags()
                        
                        // 保存最近播放的文章ID
                        UserDefaults.standard.set(selectedArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
                        
                        // 本地更新文章状态
                        article = selectedArticle
                        
                        // 设置新文章到播放器
                        speechManager.setup(for: selectedArticle)
                        
                        // 稍后开始播放
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.speechManager.startSpeaking()
                        }
                    }
                },
                isPresented: $showArticleList
            )
        }
        .sheet(isPresented: $showTimerSheet) {
            TimerSheetView(isPresented: $showTimerSheet)
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
        print("========= 用户点击了文本段落 =========")
        print("点击的段落索引: \(paragraphIndex)")
        print("文本段落长度: \(paragraph.count)")
        
        // 安全检查：确保文章内容有效
        let paragraphs = article.content.components(separatedBy: "\n\n")
        
        // 确保索引在有效范围内
        if paragraphIndex < 0 || paragraphIndex >= paragraphs.count {
            print("段落索引超出范围")
            return
        }
        
        var startPosition = 0
        
        for i in 0..<paragraphIndex {
            startPosition += paragraphs[i].count + 2  // +2 for "\n\n"
        }
        
        // 确保计算的位置有效
        if startPosition < 0 || startPosition >= article.content.count {
            print("计算的起始位置无效: \(startPosition)，超出范围[0, \(article.content.count)]")
            startPosition = 0
        }
        
        print("计算的起始位置: \(startPosition)")
        
        // 确保完全停止当前播放，重置所有状态
        if speechManager.isPlaying {
            // 设置标志防止触发循环播放
            speechDelegate.wasManuallyPaused = true
            // 停止当前播放但不重置恢复状态
            speechManager.stopSpeaking(resetResumeState: false)
        }
        
        // 清除可能存在的旧位置信息
        speechDelegate.startPosition = startPosition
        
        // 延迟一点开始播放，确保之前的停止操作已完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("开始从位置 \(startPosition) 播放")
            // 确保设置正确的标志，防止从中间位置播放结束后自动循环
            self.speechDelegate.wasManuallyPaused = true
            self.speechManager.startSpeakingFromPosition(startPosition)
        }
        
        print("=======================================")
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
        // 特殊情况处理
        if voiceLanguage.isEmpty || articleLanguage.isEmpty {
            print("语言代码为空，默认兼容")
            return true // 如果语言代码为空，默认为兼容
        }
        
        // 提取语言代码（如 "zh-CN" 中的 "zh"）
        let voiceMainLanguage = voiceLanguage.split(separator: "-").first?.lowercased() ?? voiceLanguage.lowercased()
        let articleMainLanguage = articleLanguage.split(separator: "-").first?.lowercased() ?? articleLanguage.lowercased()
        
        // 增加日志
        print("比较语音语言: \(voiceMainLanguage) 与文章语言: \(articleMainLanguage)")
        
        // 特殊处理：部分中文变体兼容性
        if (voiceMainLanguage == "zh" || voiceMainLanguage == "yue" || voiceMainLanguage == "cmn") &&
           (articleMainLanguage == "zh" || articleMainLanguage == "yue" || articleMainLanguage == "cmn") {
            print("中文变体语言，视为兼容")
            return true
        }
        
        // 特殊处理：语音朗读器
        if voiceMainLanguage == "auto" {
            print("语音为自动检测，视为兼容")
            return true // 自动语言检测，总是视为兼容
        }
        
        // 如果主要语言代码相同，则认为兼容
        let isCompatible = voiceMainLanguage == articleMainLanguage
        
        if isCompatible {
            print("语言兼容：\(voiceMainLanguage) 与 \(articleMainLanguage)")
        } else {
            print("语言不兼容：\(voiceMainLanguage) 与 \(articleMainLanguage)")
        }
        
        return isCompatible
    }
    
    // 播放下一篇文章
    private func playNextArticle() {
        print("========= ArticleReaderView.playNextArticle =========")
        print("当前文章: \(article.title)")
        print("列表文章数量: \(currentListArticles.count)")
        
        // 防止重复快速处理
        let now = Date()
        if now.timeIntervalSince(ArticleReaderView.lastArticlePlayTime) < 1.5 {
            print("⚠️ 播放操作间隔太短，忽略此次请求")
            return
        }
        ArticleReaderView.lastArticlePlayTime = now
        
        // 首先确保停止当前所有播放
        if speechManager.isPlaying {
            speechManager.stopSpeaking(resetResumeState: true)
        }
        
        // 重置关键状态标志
        speechDelegate.startPosition = 0
        speechDelegate.wasManuallyPaused = false
        
        // 设置标记，表示这是从列表循环模式跳转的
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.isFromListRepeat)
        print("设置列表循环跳转标记")
        
        // 特殊处理：列表中只有一篇文章的情况
        if currentListArticles.count == 1 && currentListArticles[0].id == article.id {
            print("列表中只有一篇文章，直接从头开始播放当前文章")
            
            // 重置播放状态
            speechManager.setup(for: article)
            
            // 延迟更久以确保所有状态已重置
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // 再次确保代理状态已重置
                self.speechDelegate.startPosition = 0
                self.speechDelegate.wasManuallyPaused = false
                // 使用公共方法重置播放标志
                self.speechManager.resetPlaybackFlags()
                
                // 从头开始播放
                self.speechManager.startSpeaking()
                print("开始循环播放唯一文章")
            }
            return
        }
        
        // 获取当前文章在列表中的索引
        if let currentIndex = currentListArticles.firstIndex(where: { $0.id == article.id }) {
            print("当前文章索引: \(currentIndex)")
            
            // 计算下一篇文章的索引
            let nextIndex = (currentIndex + 1) % currentListArticles.count
            print("下一篇文章索引: \(nextIndex)")
            
            // 在列表循环模式下，直接播放下一篇文章，即使循环到自己
            let nextArticle = currentListArticles[nextIndex]
            print("下一篇文章: \(nextArticle.title)")
            
            // 关键修改: 不再发送通知，直接在本地更新文章状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // 确保播放控制状态已正确重置
                self.speechDelegate.startPosition = 0
                self.speechDelegate.wasManuallyPaused = false
                self.speechManager.resetPlaybackFlags()
                
                // 保存最近播放的文章ID
                UserDefaults.standard.set(nextArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
                
                // 直接本地更新文章状态
                self.article = nextArticle
                
                // 设置播放器为新文章
                self.speechManager.setup(for: nextArticle)
                
                // 稍微延迟开始播放
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.speechManager.startSpeaking()
                    print("本地切换到下一篇并开始播放")
                }
            }
        } else {
            print("当前文章不在列表中，尝试使用第一篇文章")
            
            // 如果当前文章不在列表中，尝试播放列表的第一篇文章
            if let firstArticle = currentListArticles.first {
                print("播放列表的第一篇文章: \(firstArticle.title)")
                
                // 添加延迟以确保状态已重置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // 确保播放控制状态已正确重置
                    self.speechDelegate.startPosition = 0
                    self.speechDelegate.wasManuallyPaused = false
                    self.speechManager.resetPlaybackFlags()
                    
                    // 保存最近播放的文章ID
                    UserDefaults.standard.set(firstArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
                    
                    // 直接本地更新文章状态
                    self.article = firstArticle
                    
                    // 设置播放器为新文章
                    self.speechManager.setup(for: firstArticle)
                    
                    // 稍微延迟开始播放
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.speechManager.startSpeaking()
                        print("本地切换到第一篇并开始播放")
                    }
                }
            } else {
                print("列表中没有文章可播放")
            }
        }
        
        print("=================================================")
    }
    
    private func handlePlayNextArticle() {
        print("========= handlePlayNextArticle =========")
        // 获取当前文章的索引
        if let currentIndex = currentListArticles.firstIndex(where: { $0.id == article.id }) {
            // 计算下一篇文章的索引（循环处理）
            let nextIndex = (currentIndex + 1) % currentListArticles.count
            
            // 获取下一篇要播放的文章
            let nextArticle = currentListArticles[nextIndex]
            
            // 保存最近播放的文章ID
            UserDefaults.standard.set(nextArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
            
            // 更新当前文章
            article = nextArticle
            
            // 设置新文章到播放器
            speechManager.setup(for: nextArticle)
            
            // 开始播放
            speechManager.startSpeaking()
            
            print("已切换到下一篇文章: \(nextArticle.title)")
        } else if !currentListArticles.isEmpty {
            // 如果当前文章不在列表中，播放列表的第一篇
            let firstArticle = currentListArticles[0]
            
            // 保存最近播放的文章ID
            UserDefaults.standard.set(firstArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
            
            // 更新当前文章
            article = firstArticle
            
            // 设置新文章到播放器
            speechManager.setup(for: firstArticle)
            
            // 开始播放
            speechManager.startSpeaking()
            
            print("文章不在列表中，已切换到第一篇: \(firstArticle.title)")
        } else {
            print("列表中没有文章可播放")
        }
    }
    
    // 播放上一篇文章
    private func playPreviousArticle() {
        print("========= ArticleReaderView.playPreviousArticle =========")
        print("当前文章: \(article.title)")
        print("列表文章数量: \(currentListArticles.count)")
        
        // 防止重复快速处理
        let now = Date()
        if now.timeIntervalSince(ArticleReaderView.lastArticlePlayTime) < 1.5 {
            print("⚠️ 播放操作间隔太短，忽略此次请求")
            return
        }
        ArticleReaderView.lastArticlePlayTime = now
        
        // 首先确保停止当前所有播放
        if speechManager.isPlaying {
            speechManager.stopSpeaking(resetResumeState: true)
        }
        
        // 重置关键状态标志
        speechDelegate.startPosition = 0
        speechDelegate.wasManuallyPaused = false
        
        // 设置标记，表示这是从列表循环模式跳转的
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.isFromListRepeat)
        print("设置列表循环跳转标记")
        
        // 特殊处理：列表中只有一篇文章的情况
        if currentListArticles.count == 1 && currentListArticles[0].id == article.id {
            print("列表中只有一篇文章，直接从头开始播放当前文章")
            
            // 重置播放状态
            speechManager.setup(for: article)
            
            // 延迟以确保所有状态已重置
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // 再次确保代理状态已重置
                self.speechDelegate.startPosition = 0
                self.speechDelegate.wasManuallyPaused = false
                // 使用公共方法重置播放标志
                self.speechManager.resetPlaybackFlags()
                
                // 从头开始播放
                self.speechManager.startSpeaking()
                print("开始循环播放唯一文章")
            }
            return
        }
        
        // 获取当前文章在列表中的索引
        if let currentIndex = currentListArticles.firstIndex(where: { $0.id == article.id }) {
            print("当前文章索引: \(currentIndex)")
            
            // 计算上一篇文章的索引
            let previousIndex = (currentIndex - 1 + currentListArticles.count) % currentListArticles.count
            print("上一篇文章索引: \(previousIndex)")
            
            // 获取上一篇文章
            let previousArticle = currentListArticles[previousIndex]
            print("上一篇文章: \(previousArticle.title)")
            
            // 关键修改: 不再发送通知，直接在本地更新文章状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // 确保播放控制状态已正确重置
                self.speechDelegate.startPosition = 0
                self.speechDelegate.wasManuallyPaused = false
                self.speechManager.resetPlaybackFlags()
                
                // 保存最近播放的文章ID
                UserDefaults.standard.set(previousArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
                
                // 直接本地更新文章状态
                self.article = previousArticle
                
                // 设置播放器为新文章
                self.speechManager.setup(for: previousArticle)
                
                // 稍微延迟开始播放
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.speechManager.startSpeaking()
                    print("本地切换到上一篇并开始播放")
                }
            }
        } else {
            print("当前文章不在列表中，尝试使用最后一篇文章")
            
            // 如果当前文章不在列表中，尝试播放列表的最后一篇文章
            if let lastArticle = currentListArticles.last {
                print("播放列表的最后一篇文章: \(lastArticle.title)")
                
                // 添加延迟以确保状态已重置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // 确保播放控制状态已正确重置
                    self.speechDelegate.startPosition = 0
                    self.speechDelegate.wasManuallyPaused = false
                    self.speechManager.resetPlaybackFlags()
                    
                    // 保存最近播放的文章ID
                    UserDefaults.standard.set(lastArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
                    
                    // 直接本地更新文章状态
                    self.article = lastArticle
                    
                    // 设置播放器为新文章
                    self.speechManager.setup(for: lastArticle)
                    
                    // 稍微延迟开始播放
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.speechManager.startSpeaking()
                        print("本地切换到最后一篇并开始播放")
                    }
                }
            } else {
                print("列表中没有文章可播放")
            }
        }
        
        print("=================================================")
    }
    
    private func handleFloatingButtonTap() {
        // 使用上一次播放的文章列表
        if !speechManager.lastPlayedArticles.isEmpty {
            currentListArticles = speechManager.lastPlayedArticles
        }
        showArticleList = true
    }
} 