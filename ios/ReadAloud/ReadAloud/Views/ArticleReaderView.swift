import SwiftUI
import AVFoundation
import Combine
// 自定义Slider组件在项目内部，无需特殊导入

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
    
    // 用于跟踪初始化时间，防止短时间内重复初始化
    private static var lastInitTime: Date = Date(timeIntervalSince1970: 0)
    private static var lastInitArticleId: UUID? = nil
    
    // 自定义初始化方法，接收必要的依赖
    init(article: Article, selectedListId: UUID? = nil, useLastPlaylist: Bool = false, articleManager: ArticleManager) {
        // 检查是否是短时间内对同一篇文章的重复初始化
        let now = Date()
        let isSameArticle = Self.lastInitArticleId == article.id
        let isRecentInit = now.timeIntervalSince(Self.lastInitTime) < 0.3
        
        if isSameArticle && isRecentInit {
            print("跳过对文章ID \(article.id) 的重复初始化 (时间间隔: \(now.timeIntervalSince(Self.lastInitTime))秒)")
            // 继续初始化，但不打印日志
            self._article = State(initialValue: article)
            self.selectedListId = selectedListId
            self.useLastPlaylist = useLastPlaylist
            self.articleManager = articleManager
            self._currentListArticles = State(initialValue: SpeechManager.shared.lastPlayedArticles)
            return
        }
        
        // 更新最后初始化时间和文章ID
        Self.lastInitTime = now
        Self.lastInitArticleId = article.id
        
        print("========= ArticleReaderView.init =========")
        print("初始化文章: \(article.title), ID: \(article.id.uuidString)")
        if let selectedListId = selectedListId {
            print("指定播放列表ID: \(selectedListId.uuidString)")
        } else {
            print("未指定播放列表ID")
        }
        print("使用上次播放列表: \(useLastPlaylist)")
        
        self._article = State(initialValue: article)
        self.selectedListId = selectedListId
        self.useLastPlaylist = useLastPlaylist
        self.articleManager = articleManager
        print("====================================")
        
        // 初始化时尝试获取当前播放列表
        self._currentListArticles = State(initialValue: SpeechManager.shared.lastPlayedArticles)
        print("初始化时播放列表文章数: \(SpeechManager.shared.lastPlayedArticles.count)")
    }
    
    // 状态管理
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var articleManager: ArticleManager
    @ObservedObject private var listManager = ArticleListManager.shared
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
    
    // 添加存储当前正在显示的段落ID
    @State private var currentVisibleParagraphId: String? = nil
    // 添加防抖变量，避免过于频繁的滚动
    @State private var lastScrollTime: Date = Date()
    
    // 添加两个变量，用于跟踪连续滚动
    @State private var consecutiveScrollCount: Int = 0
    @State private var lastScrolledParagraph: Int = -1
    
    var body: some View {
        VStack(spacing: 0) {
            // 将内容部分提取为单独的视图
            ArticleContentView(
                article: article,
                speechDelegate: speechDelegate,
                speechManager: speechManager,
                themeManager: themeManager,
                isAppLaunch: isAppLaunch,
                onTextTap: handleTextTap,
                getLastPlaybackParagraphId: getLastPlaybackParagraphId,
                scrollToCurrentParagraph: scrollToCurrentParagraph
            )
            
            Spacer()
            
            // 将底部控制区域提取为单独的视图
            // 创建一个局部变量来存储BottomControlView，以减少表达式复杂度
            let bottomControlView = BottomControlView(
                article: article,
                speechManager: speechManager,
                speechDelegate: speechDelegate,
                themeManager: themeManager,
                playbackManager: PlaybackManager.shared,
                timerManager: timerManager,
                isAppLaunch: $isAppLaunch,
                showSpeedSelector: $showSpeedSelector,
                showVoiceSelector: $showVoiceSelector,
                showArticleList: $showArticleList,
                showTimerSheet: $showTimerSheet,
                showVoiceLanguageError: $showVoiceLanguageError,
                availableVoices: $availableVoices,
                currentListArticles: $currentListArticles,
                handlePlayNext: playNextArticle,
                handlePlayPrevious: playPreviousArticle,
                articleManager: articleManager,
                listManager: listManager,
                getListArticles: { self.listArticles },
                extractChapterNumber: extractChapterNumber
            )
            
            // 使用创建的视图
            bottomControlView
        }
        .onAppear {
            print("ArticleReaderView 出现")
            print("当前文章ID: \(article.id)")
            
            // 获取当前文章所属的文档或列表ID
            let currentContentSourceId = article.listId
            print("当前文章所属内容源ID: \(currentContentSourceId?.uuidString ?? "无")")
            
            // 检查SpeechManager中的播放列表，确保与当前文章来自同一个内容源
            if !speechManager.lastPlayedArticles.isEmpty {
                let managerSourceId = speechManager.lastPlayedArticles.first?.listId
                print("SpeechManager播放列表内容源ID: \(managerSourceId?.uuidString ?? "无")")
                
                // 如果内容源ID不匹配，强制更新播放列表
                if managerSourceId != currentContentSourceId {
                    print("⚠️ 检测到内容源不匹配，强制更新播放列表")
                    
                    // 获取当前文章所在的正确播放列表
                    let articlesToPlay = listArticles
                    print("设置播放列表为当前文章所在列表，包含 \(articlesToPlay.count) 篇文章")
                    if !articlesToPlay.isEmpty {
                        print("当前列表第一篇: \(articlesToPlay.first?.title ?? "无"), ID: \(articlesToPlay.first?.id.uuidString ?? "无")")
                        print("当前列表最后一篇: \(articlesToPlay.last?.title ?? "无"), ID: \(articlesToPlay.last?.id.uuidString ?? "无")")
                    }
                    
                    // 更新播放列表
                    speechManager.updatePlaylist(articlesToPlay)
                    currentListArticles = articlesToPlay
                } else {
                    // 内容源匹配，同步播放列表状态
                    self.syncPlaylistState()
                }
            } else {
                // SpeechManager的播放列表为空，设置新的播放列表
                let articlesToPlay = listArticles
                print("SpeechManager播放列表为空，设置新的播放列表，包含 \(articlesToPlay.count) 篇文章")
                speechManager.updatePlaylist(articlesToPlay)
                currentListArticles = articlesToPlay
            }
            
            // 记录当前播放内容类型为文章
            UserDefaults.standard.set("article", forKey: "lastPlayedContentType")
            
            // 隐藏底部标签栏
            hideTabBar()
            
            // 订阅通知
            self.playNextSubscription = NotificationCenter.default.publisher(for: Notification.Name("PlayNextArticle"))
                .sink { _ in
                    print("收到PlayNextArticle通知")
                    
                    // 避免短时间内重复触发
                    let now = Date()
                    if now.timeIntervalSince(Self.lastPlayNextTime) < 1.0 {
                        print("忽略重复的通知")
                        return
                    }
                    
                    Self.lastPlayNextTime = now
                    
                    // 播放下一篇文章
                    self.playNextArticle()
                }
            
            // 订阅定时器完成通知
            self.timerCompletedSubscription = NotificationCenter.default.publisher(for: Notification.Name("TimerCompleted"))
                .sink { _ in
                    print("收到定时器完成通知，停止播放")
                    
                    // 如果正在播放，则暂停
                    if self.speechManager.isPlaying {
                        self.speechManager.pauseSpeaking()
                    }
                }
            
            // 获取可用的语音
            self.availableVoices = AVSpeechSynthesisVoice.speechVoices()
            print("获取到 \(self.availableVoices.count) 个可用语音")
            
            // 安全检查：强制重置之前可能存在的播放状态
            if !isAppLaunch && speechManager.getSynthesizerStatus() {
                print("检测到合成器正在播放，但这是一个新的ArticleReaderView实例，强制重置...")
                speechManager.stopSpeaking(resetResumeState: true)
            }
            
            // 设置播放列表
            if useLastPlaylist {
                print("使用上次播放列表，包含 \(speechManager.lastPlayedArticles.count) 篇文章")
                if !speechManager.lastPlayedArticles.isEmpty {
                    print("上次播放列表第一篇: \(speechManager.lastPlayedArticles.first?.title ?? "无"), ID: \(speechManager.lastPlayedArticles.first?.id.uuidString ?? "无")")
                    print("上次播放列表最后一篇: \(speechManager.lastPlayedArticles.last?.title ?? "无"), ID: \(speechManager.lastPlayedArticles.last?.id.uuidString ?? "无")")
                }
            } else {
                // 根据所在列表设置播放上下文
                let articlesToPlay = listArticles
                print("设置播放列表为当前文章所在列表，包含 \(articlesToPlay.count) 篇文章")
                if !articlesToPlay.isEmpty {
                    print("当前列表第一篇: \(articlesToPlay.first?.title ?? "无"), ID: \(articlesToPlay.first?.id.uuidString ?? "无")")
                    print("当前列表最后一篇: \(articlesToPlay.last?.title ?? "无"), ID: \(articlesToPlay.last?.id.uuidString ?? "无")")
                }
                speechManager.updatePlaylist(articlesToPlay)
                
                // 更新当前文章的播放列表到最近的列表
                speechManager.lastPlayedArticles = articlesToPlay
            }
            
            // 初始化语音管理器
            speechManager.setup(for: article)
            
            // 在初始化后，检查全局播放状态
            let playbackManager = PlaybackManager.shared
            
            // 新增: 检查全局是否有其他文章在播放
            if playbackManager.isPlaying && playbackManager.currentContentId != article.id {
                print("⚠️ 检测到全局有其他文章正在播放 - ID: \(playbackManager.currentContentId?.uuidString ?? "未知"), 标题: \(playbackManager.currentTitle)")
                print("保留全局播放状态，不自动开始播放当前文章")
                
                // 确保本地UI显示为暂停状态
                speechManager.isPlaying = false
                
                // 额外提示: 不进行状态检查和同步
                print("跳过状态检查和同步，保持当前全局播放")
            } else if playbackManager.isPlaying && playbackManager.currentContentId == article.id {
                // 如果全局正在播放当前文章，同步本地UI
                print("检测到当前文章正在全局播放，同步更新本地播放状态")
                speechManager.isPlaying = true
                speechManager.objectWillChange.send()
                
                // 强制立即刷新进度条和高亮状态
                if speechManager.isResuming {
                    print("立即刷新进度条：位置 \(speechManager.currentPlaybackPosition), 进度: \(Int(speechManager.currentProgress * 100))%")
                    
                    // 使用SpeechManager的forceUpdateUI方法强制更新UI
                    speechManager.forceUpdateUI()
                }
                
                // 进行单次完整的播放状态检查和同步
                print("执行单次完整的播放状态检查和同步...")
                checkAndSyncPlaybackState()
            } else {
                // 没有任何内容在播放，正常执行
                
                // 强制立即刷新进度条和高亮状态
                if speechManager.isResuming {
                    print("立即刷新进度条：位置 \(speechManager.currentPlaybackPosition), 进度: \(Int(speechManager.currentProgress * 100))%")
                    
                    // 使用SpeechManager的forceUpdateUI方法强制更新UI
                    speechManager.forceUpdateUI()
                }
                
                // 进行单次完整的播放状态检查和同步
                print("执行单次完整的播放状态检查和同步...")
                checkAndSyncPlaybackState()
            }
            
            // 通知已进入播放界面
            NotificationCenter.default.post(name: Notification.Name("EnterPlaybackView"), object: nil)
            
            // 保存最近播放的文章ID
            UserDefaults.standard.set(article.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
            
            print("==============================================")
        }
        .onDisappear {
            // 恢复底部标签栏
            showTabBar()
            
            print("========= ArticleReaderView.onDisappear =========")
            
            // 记录离开播放界面的时间戳
            UserDefaults.standard.set(Date(), forKey: "lastExitPlaybackViewTime")
            
            // 重要: 禁用文档库加载，防止返回到文章列表时加载文档库
            // 获取FileReadView中的isDocumentLoadingDisabled变量并设置为true
            // 由于无法直接修改另一个文件中的private变量，使用通知方式
            NotificationCenter.default.post(
                name: Notification.Name("DisableDocumentLoading"),
                object: nil,
                userInfo: ["disabled": true]
            )
            print("已发送禁用文档库加载的通知")
            
            // 取消订阅
            self.playNextSubscription?.cancel()
            self.timerCompletedSubscription?.cancel()
            
            // 通知已离开播放界面
            NotificationCenter.default.post(name: Notification.Name("ExitPlaybackView"), object: nil)
            
            // 保存朗读进度
            speechManager.savePlaybackProgress()
            print("==============================================")
        }
        .sheet(isPresented: $showSpeedSelector) {
            SpeedSelectorView(selectedRate: $speechManager.selectedRate, showSpeedSelector: $showSpeedSelector)
                .onDisappear {
                    speechManager.applyNewSpeechRate()
                }
        }
        // 使用条件创建视图方式来显示语音选择器
        .background { // 使用背景视图来包含条件渲染的sheet
            EmptyView() // 空视图作为背景
                .sheet(isPresented: $showVoiceSelector) {
                    if showVoiceSelector { // 只有当实际需要显示时才创建VoiceSelectorView
                        VoiceSelectorView(
                            selectedVoiceIdentifier: $speechManager.selectedVoiceIdentifier, 
                            showVoiceSelector: $showVoiceSelector,
                            availableVoices: availableVoices,
                            articleLanguage: article.detectLanguage() // 现在只有在sheet实际显示时才会调用
                        )
                        .onDisappear {
                            speechManager.applyNewVoice()
                        }
                    }
                }
        }
        .sheet(isPresented: $showArticleList) {
            // 添加调试日志，验证传递的ID是否正确
            let _ = {
                print("正在显示章节列表 - 当前文章ID: \(article.id)")
                print("当前列表包含 \(currentListArticles.count) 个章节")
                if let index = currentListArticles.firstIndex(where: { $0.id == article.id }) {
                    print("当前文章在列表中的索引: \(index+1)/\(currentListArticles.count)")
                } else {
                    print("警告: 当前文章ID不在列表中!")
                }
            }()
            
            ArticleListPopoverView(
                articles: currentListArticles,
                currentArticleId: article.id,
                onSelectArticle: { selectedArticle in
                    print("选择了章节: \(selectedArticle.title)")
                    print("选择的章节ID: \(selectedArticle.id), 当前章节ID: \(article.id)")
                    
                    // 检查是否是选择了与当前相同的章节
                    if selectedArticle.id == article.id {
                        print("选择了当前正在显示的章节，无需切换")
                        return
                    }
                    
                    // 设置切换文章标志，防止触发自动播放逻辑
                    // 注意：这个标志会在播放完成时检查，所以在整个过程中都不要重置它
                    speechDelegate.isArticleSwitching = true
                    print("已设置isArticleSwitching=true，防止触发自动播放逻辑")
                    
                    // 停止当前播放
                    if speechManager.isPlaying {
                        speechManager.stopSpeaking(resetResumeState: true)
                    }
                    
                    // 重置播放状态，但保留文章切换标志
                    speechDelegate.startPosition = 0
                    speechDelegate.wasManuallyPaused = false
                    // 注意：不在这里重置isArticleSwitching
                    
                    // 保存最近播放的文章ID
                    UserDefaults.standard.set(selectedArticle.id.uuidString, forKey: UserDefaultsKeys.lastPlayedArticleId)
                    
                    // 更新到选择的文章
                    self.article = selectedArticle
                    
                    // 设置并开始播放新选择的章节
                    speechManager.setup(for: selectedArticle)
                    print("已切换到章节: \(selectedArticle.title)")
                    
                    // 延迟一点开始播放，确保之前的停止操作已完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("开始播放章节: \(selectedArticle.title)")
                        // 不要在这里重置文章切换标志
                        // speechDelegate.isArticleSwitching = false
                        // print("重置isArticleSwitching=false，准备开始新章节播放")
                        
                        speechManager.startSpeaking()
                        
                        // 在朗读真正开始后再重置标志
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if self.speechDelegate.isSpeaking {
                                print("朗读已经开始，现在才安全地重置isArticleSwitching=false")
                                self.speechDelegate.isArticleSwitching = false
                            }
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
        // 使用条件创建方式显示语言错误警报
        .background { // 使用背景视图来包含条件渲染的alert
            EmptyView()
                .alert("提示", isPresented: $showVoiceLanguageError) {
                    Button("确定", role: .cancel) { }
                } message: {
                    if showVoiceLanguageError { // 仅在实际显示警报时才计算语言
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
                        return Text("select_voice_prompt".localized(with: languageName, languageName))
                    } else {
                        return Text("")
                    }
                }
        }
    }
    
    // 添加文章内容视图组件
    private struct ArticleContentView: View {
        let article: Article
        let speechDelegate: SpeechDelegate
        let speechManager: SpeechManager
        let themeManager: ThemeManager
        let isAppLaunch: Bool
        let onTextTap: (Int, String) -> Void
        let getLastPlaybackParagraphId: () -> String?
        let scrollToCurrentParagraph: (ScrollViewProxy) -> Void
        
        // 添加防抖动状态
        @State private var lastHighlightChangeTime = Date()
        @State private var isProcessingScroll = false
        
        var body: some View {
            ScrollView {
                ScrollViewReader { scrollView in
                    VStack(alignment: .leading, spacing: 0) {
                        // 高亮显示的文本内容
                        ArticleHighlightedText(
                            text: article.content,
                            highlightRange: speechDelegate.highlightRange,
                            onTap: onTextTap,
                            themeManager: themeManager
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 150) // 增加底部填充，确保最后几段文本可以滚动到合适位置
                    }
                    .onChange(of: speechDelegate.highlightRange) { newValue in
                        // 防抖动处理：确保不会频繁触发滚动
                        let now = Date()
                        let timeSinceLastChange = now.timeIntervalSince(lastHighlightChangeTime)
                        
                        // 只有距离上次高亮变化超过0.5秒才考虑滚动，防止频繁滚动
                        if timeSinceLastChange > 0.5 && !isProcessingScroll {
                            isProcessingScroll = true // 标记正在处理滚动
                            
                            // 延迟执行滚动，让系统有时间稳定
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                scrollToCurrentParagraph(scrollView)
                                
                                // 重置标志
                                self.isProcessingScroll = false
                                self.lastHighlightChangeTime = Date()
                            }
                        }
                    }
                    .onAppear {
                        // 初始化时滚动到上次播放位置
                        if speechManager.isResuming && !speechManager.isPlaying && isAppLaunch {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if let paragraphId = getLastPlaybackParagraphId() {
                                    print("初始化时滚动到上次播放位置: \(paragraphId)")
                                    withAnimation {
                                        scrollView.scrollTo(paragraphId, anchor: UnitPoint(x: 0, y: 0.08))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.visible) // 显示滚动指示器，提供更好的视觉反馈
        }
    }
    
    // 添加底部控制视图组件 - 将主要控制部分移到这里
    private struct BottomControlView: View {
        let article: Article
        let speechManager: SpeechManager
        let speechDelegate: SpeechDelegate
        let themeManager: ThemeManager
        let playbackManager: PlaybackManager
        let timerManager: TimerManager
        @Binding var isAppLaunch: Bool
        @Binding var showSpeedSelector: Bool
        @Binding var showVoiceSelector: Bool
        @Binding var showArticleList: Bool
        @Binding var showTimerSheet: Bool
        @Binding var showVoiceLanguageError: Bool
        @Binding var availableVoices: [AVSpeechSynthesisVoice]
        @Binding var currentListArticles: [Article]
        let handlePlayNext: () -> Void
        let handlePlayPrevious: () -> Void
        let articleManager: ArticleManager
        let listManager: ArticleListManager
        let getListArticles: () -> [Article]
        let extractChapterNumber: (String) -> Int?
        
        var body: some View {
            // 底部播放控制区域
            VStack(spacing: 5) {
                // 时间显示
                TimeDisplayView(speechManager: speechManager)
                
                // 上次播放位置恢复提示
                PlaybackResumeView(
                    speechManager: speechManager,
                    speechDelegate: speechDelegate,
                    isAppLaunch: $isAppLaunch
                )
                
                // 进度条和快进/快退按钮
                ProgressControlView(
                    speechManager: speechManager,
                    themeManager: themeManager
                )
                
                // 播放控制区
                PlaybackControlsView(
                    article: article,
                    speechManager: speechManager,
                    speechDelegate: speechDelegate,
                    themeManager: themeManager,
                    playbackManager: playbackManager,
                    isAppLaunch: $isAppLaunch,
                    showSpeedSelector: $showSpeedSelector,
                    showVoiceLanguageError: $showVoiceLanguageError,
                    handlePlayNext: handlePlayNext,
                    handlePlayPrevious: handlePlayPrevious
                )
                
                // 设置按钮区域
                SettingsButtonsView(
                    article: article,
                    speechManager: speechManager,
                    speechDelegate: speechDelegate,
                    themeManager: themeManager,
                    timerManager: timerManager,
                    showArticleList: $showArticleList,
                    showTimerSheet: $showTimerSheet,
                    showVoiceSelector: $showVoiceSelector,
                    availableVoices: $availableVoices,
                    currentListArticles: $currentListArticles,
                    articleManager: articleManager,
                    listManager: listManager,
                    getListArticles: getListArticles,
                    extractChapterNumber: extractChapterNumber
                )
            }
        }
    }
    
    // 时间显示视图 - 完全重写
    private struct TimeDisplayView: View {
        let speechManager: SpeechManager
        
        // 使用State存储当前时间和总时间
        @State private var currentTimeString: String = "00:00"
        @State private var totalTimeString: String = "00:00"
        @State private var refreshTimer: Timer?
        @State private var uniqueID = UUID()  // 用于强制视图刷新
        
        var body: some View {
            HStack {
                Text(currentTimeString)
                    .font(.caption)
                    .id("current\(uniqueID)")
                
                Spacer()
                
                Text(totalTimeString)
                    .font(.caption)
                    .id("total\(uniqueID)")
            }
            .padding(.horizontal)
            .onAppear {
                // 初始设置时间显示
                updateTimeDisplay()
                // 启动定时器
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
        
        // 更新时间显示
        private func updateTimeDisplay() {
            // 使用新方法获取时间，这会同时触发SpeechManager的UI刷新
            let timeInfo = speechManager.getCurrentTimeInfo()
            let currentTime = timeInfo.current
            let totalTime = timeInfo.total
            
            // 格式化时间
            currentTimeString = formatTime(currentTime)
            totalTimeString = formatTime(totalTime)
            
            // 打印时间信息，帮助调试
            if speechManager.isPlaying && (currentTime == 0 || totalTime == 0) {
                print("时间异常: \(currentTimeString)/\(totalTimeString)")
            }
        }
        
        // 格式化时间显示
        private func formatTime(_ seconds: TimeInterval) -> String {
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%02d:%02d", mins, secs)
        }
        
        // 启动独立定时器
        private func startTimer() {
            stopTimer()
            
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                // 确保在主线程更新UI
                DispatchQueue.main.async {
                    updateTimeDisplay()
                    
                    // 强制视图更新 - 通过改变ID
                    uniqueID = UUID()
                }
            }
            
            // 确保定时器在主线程运行并添加到运行循环
            if let timer = refreshTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        
        // 停止定时器
        private func stopTimer() {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    // 恢复播放提示视图
    private struct PlaybackResumeView: View {
        let speechManager: SpeechManager
        let speechDelegate: SpeechDelegate
        @Binding var isAppLaunch: Bool
        
        var body: some View {
            if speechManager.isResuming && !speechManager.isPlaying && isAppLaunch {
                HStack {
                    Button(action: {
                        // 设置手动暂停标志，防止播放完成后自动跳转
                        speechDelegate.wasManuallyPaused = true
                        print("继续上次播放：设置wasManuallyPaused=true，防止播放完成后自动跳转")
                        
                        // 从保存的位置开始播放
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
                        print("从头开始按下")
                        // 重置播放位置，使用startSpeakingFromPosition方法从头开始
                        if (speechManager.isPlaying) {
                            speechManager.stopSpeaking(resetResumeState: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                print("重新开始播放")
                                speechManager.startSpeaking()
                            }
                        } else {
                            // 不在播放中，直接设置起始位置为0
                            speechManager.startSpeakingFromPosition(0)
                        }
                    }) {
                        Text("start_from_beginning".localized)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // 进度控制视图
    private struct ProgressControlView: View {
        let speechManager: SpeechManager
        let themeManager: ThemeManager
        
        var body: some View {
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
                
                // 进度条，支持拖拽和点击
                SliderWithTapHandler(
                    value: Binding(
                        get: { speechManager.currentProgress },
                        set: { speechManager.currentProgress = $0 }
                    ),
                    range: 0...1,
                    onEditingChanged: { editing in
                        speechManager.isDragging = editing
                        
                        if !editing {
                            speechManager.seekToProgress(speechManager.currentProgress)
                        }
                    },
                    onTap: { progress in
                        // 点击处理
                        speechManager.seekToProgress(progress)
                    },
                    accentColor: themeManager.isDarkMode ? .white : .blue
                )
                
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
            .padding(.horizontal)
        }
    }
    
    // 播放控制视图
    private struct PlaybackControlsView: View {
        let article: Article
        let speechManager: SpeechManager
        let speechDelegate: SpeechDelegate
        let themeManager: ThemeManager
        let playbackManager: PlaybackManager
        @Binding var isAppLaunch: Bool
        @Binding var showSpeedSelector: Bool
        @Binding var showVoiceLanguageError: Bool
        let handlePlayNext: () -> Void
        let handlePlayPrevious: () -> Void
        
        var body: some View {
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
                    handlePlayPrevious()
                }) {
                    Image(systemName: "backward.end.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(themeManager.isDarkMode ? .white : .blue)
                }
                .padding(.trailing, 20)
                
                // 播放/暂停按钮
                Button(action: {
                    if playbackManager.isPlaying && playbackManager.currentContentId != article.id {
                        // 如果当前有其他内容在播放，先停止它
                        playbackManager.stopPlayback()
                        // 短暂延迟后再开始播放
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            handlePlayPauseAction()
                        }
                        return
                    }
                    
                    handlePlayPauseAction()
                }) {
                    // 计算播放按钮显示状态
                    let isLocalPlaying = speechManager.isPlaying && speechManager.getCurrentArticle()?.id == article.id
                    let isGlobalPlaying = playbackManager.isPlaying && playbackManager.currentContentId == article.id
                    let shouldShowPlaying = isLocalPlaying || isGlobalPlaying
                    
                    // 不再根据isProcessingAudio显示进度，直接显示播放/暂停按钮
                    Image(systemName: shouldShowPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(themeManager.isDarkMode ? .white : .blue)
                }
                
                // 下一篇按钮
                Button(action: {
                    handlePlayNext()
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
                        Text(speechManager.playbackMode.rawValue.localized)
                            .font(.system(size: 16))
                    }
                    .frame(width: 70)  // 设置固定宽度
                    .padding(8)
                }
                
                Spacer()
            }
            .padding(.vertical, 10)
        }
        
        // 将播放按钮的逻辑提取到独立方法中
        private func handlePlayPauseAction() {
            // 获取全局播放状态
            let playbackManager = PlaybackManager.shared
            
            // 检查当前播放的是否为当前文章 - 拆分复杂表达式避免编译器超时
            let isPlayingByThisManager = speechManager.isPlaying 
            let isArticleMatchInThisManager = speechManager.getCurrentArticle()?.id == article.id
            let isSpeechManagerPlaying = isPlayingByThisManager && isArticleMatchInThisManager
            
            let isPlayingGlobally = playbackManager.isPlaying
            let isArticleMatchGlobally = playbackManager.currentContentId == article.id
            let isPlaybackManagerPlaying = isPlayingGlobally && isArticleMatchGlobally
            
            let isCurrentArticlePlaying = isSpeechManagerPlaying || isPlaybackManagerPlaying
            
            if isCurrentArticlePlaying {
                // 如果当前文章正在播放，则暂停播放
                speechManager.pauseSpeaking()
            } else {
                // 如果其他文章正在播放，先停止它
                if speechManager.isPlaying || playbackManager.isPlaying {
                    print("检测到其他文章正在播放，先停止它再播放当前文章")
                    
                    // 设置切换文章标志，防止触发自动播放逻辑
                    speechDelegate.isArticleSwitching = true
                    print("已设置isArticleSwitching=true，防止触发自动播放逻辑")
                    
                    // 在停止当前播放前添加标记，表明这是因为切换文章而停止的
                    speechDelegate.wasManuallyPaused = true
                    
                    // 使用强制设置方法替换原来的代码
                    speechManager.forceSetup(for: article)
                    
                    // 添加一小段延迟，确保isArticleSwitching标志被正确处理
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if speechDelegate.isArticleSwitching {
                            print("stopSpeaking后isArticleSwitching仍为true，这是正常的")
                        } else {
                            print("⚠️ 警告：stopSpeaking后isArticleSwitching已被重置为false")
                        }
                    }
                } else {
                    // 确保设置为当前文章
                    speechManager.setup(for: article)
                }
                
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
                    // 从保存的位置开始播放，确保设置手动暂停标志为true
                    // 防止播放完成时自动跳转到下一章
                    speechDelegate.wasManuallyPaused = true
                    
                    // 不要重置isArticleSwitching标志，而是使用一个延迟回调
                    // 确保当前位置有效
                    let position = max(0, min(speechManager.currentPlaybackPosition, article.content.count - 1))
                    print("从保存的位置恢复播放: \(position)/\(article.content.count)")
                    
                    speechManager.startSpeakingFromPosition(position)
                    
                    // 在朗读真正开始后再重置标志
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if speechDelegate.isSpeaking {
                            print("朗读已经开始，现在才安全地重置isArticleSwitching=false")
                            speechDelegate.isArticleSwitching = false
                        }
                    }
                } else {
                    // 不要重置isArticleSwitching标志，而是使用一个延迟回调
                    speechManager.startSpeaking()
                    
                    // 在朗读真正开始后再重置标志
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if speechDelegate.isSpeaking {
                            print("朗读已经开始，现在才安全地重置isArticleSwitching=false")
                            speechDelegate.isArticleSwitching = false
                        }
                    }
                }
                isAppLaunch = false
            }
        }
        
        // 检查语音语言是否与文章语言兼容 - 为嵌套视图添加辅助方法
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
            let isVoiceChineseVariant = voiceMainLanguage == "zh" || voiceMainLanguage == "yue" || voiceMainLanguage == "cmn"
            let isArticleChineseVariant = articleMainLanguage == "zh" || articleMainLanguage == "yue" || articleMainLanguage == "cmn"
            if isVoiceChineseVariant && isArticleChineseVariant {
                print("中文变体语言，视为兼容")
                return true
            }
            
            // 特殊处理：英文和中文语音的广泛兼容性
            // 有些用户可能喜欢用英文声音读中文，或用中文声音读英文
            let isZhEnCombination = voiceMainLanguage == "zh" && articleMainLanguage == "en"
            let isEnZhCombination = voiceMainLanguage == "en" && articleMainLanguage == "zh"
            if isZhEnCombination || isEnZhCombination {
                print("中英文跨语言朗读，允许用户使用")
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
    }
    
    // 设置按钮视图
    private struct SettingsButtonsView: View {
        let article: Article
        let speechManager: SpeechManager
        let speechDelegate: SpeechDelegate
        let themeManager: ThemeManager
        let timerManager: TimerManager
        @Binding var showArticleList: Bool
        @Binding var showTimerSheet: Bool
        @Binding var showVoiceSelector: Bool
        @Binding var availableVoices: [AVSpeechSynthesisVoice]
        @Binding var currentListArticles: [Article]
        let articleManager: ArticleManager
        let listManager: ArticleListManager
        let getListArticles: () -> [Article]
        let extractChapterNumber: (String) -> Int?
        
        var body: some View {
            HStack(spacing: 20) {
                // 列表按钮
                Button(action: {
                    handleListButtonTapped()
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 18))
                        
                        Text("article_list".localized)
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
                                    Text("chapter".localized)
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
                                Text("after_chapter".localized)
                                    .font(.system(size: 14))
                            } else if !timerManager.formattedRemainingTime().isEmpty {
                                Text(timerManager.formattedRemainingTime())
                                    .font(.system(size: 14))
                                    .monospacedDigit()
                            } else {
                                Text("timer".localized)
                                    .font(.system(size: 14))
                            }
                        } else {
                            Text("timer".localized)
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
                        
                        Text(themeManager.isDarkMode ? "night_mode".localized : "day_mode".localized)
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
                        
                        Text(themeManager.fontSizeOption.localizedText)
                            .font(.system(size: 14))
                    }
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                
                // 切换主播按钮
                Button(action: {
                    handleVoiceButtonTapped()
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: "person.wave.2")
                            .font(.system(size: 18))
                        
                        Text("voice".localized)
                            .font(.system(size: 14))
                    }
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding(.bottom, 30)
        }
        
        // 列表按钮处理逻辑
        private func handleListButtonTapped() {
            // 原来的列表按钮逻辑
            // 确保已加载文章
            articleManager.loadArticles()
            
            // 发送通知告知需要更新播放列表
            NotificationCenter.default.post(name: Notification.Name("OpenArticleList"), object: nil)
            
            // 添加详细ID诊断日志
            print("========= 章节ID诊断信息 =========")
            print("当前文档ID: \(article.id.uuidString)")
            print("当前文档标题: \(article.title)")
            
            // 获取播放列表 - 优先使用SpeechManager的lastPlayedArticles
            currentListArticles = speechManager.lastPlayedArticles
            
            // 打印初始播放列表的ID信息
            print("初始播放列表包含 \(currentListArticles.count) 篇文章")
            
            // 确保当前列表有文章
            if currentListArticles.isEmpty {
                // 如果SpeechManager的列表为空，尝试使用私有计算属性中的listArticles
                print("警告: 播放列表为空，尝试使用计算属性中的listArticles")
                currentListArticles = getListArticles()
                
                print("使用listArticles后，播放列表包含 \(currentListArticles.count) 篇文章")
            }
            
            handleArticleListConsistency()
            
            // 打印当前列表文章数量和状态
            print("列表按钮 - 播放列表文章数: \(currentListArticles.count)")
            print("当前文章ID: \(article.id)")
            if let index = currentListArticles.firstIndex(where: { $0.id == article.id }) {
                print("当前文章在列表中的索引: \(index+1)/\(currentListArticles.count)")
            }
            
            // 显示列表弹窗
            showArticleList = true
        }
        
        // 确保文章列表一致性
        private func handleArticleListConsistency() {
            // 确保当前文章在列表中
            if !currentListArticles.contains(where: { $0.id == article.id }) {
                print("=== ID不匹配诊断信息 ===")
                print("当前文章不在播放列表中，检查是否可能是相同章节的不同对象...")
                print("当前文章ID: \(article.id.uuidString)")
                print("当前文章标题: \(article.title)")
                
                // 从当前文章标题中提取章节号
                let currentChapterNumber = extractChapterNumber(article.title)
                print("当前文章提取的章节号: \(currentChapterNumber ?? -1)")
                
                // 检查是否有相同章节号的文章已在列表中
                var existingSameChapterArticle: Article? = nil
                var existingSameChapterIndex: Int? = nil
                
                // 尝试查找可能匹配的文章
                var possibleMatches: [(index: Int, article: Article, reason: String)] = []
                
                for (index, listArticle) in currentListArticles.enumerated() {
                    var matchReason = ""
                    
                    if listArticle.title == article.title {
                        // 标题完全匹配
                        matchReason = "标题完全匹配"
                        possibleMatches.append((index, listArticle, matchReason))
                        existingSameChapterArticle = listArticle
                        existingSameChapterIndex = index
                        print("找到标题完全匹配的文章：\(listArticle.title)（ID: \(listArticle.id.uuidString)）")
                        break
                    } else if let currentNumber = currentChapterNumber,
                              let listNumber = extractChapterNumber(listArticle.title),
                              currentNumber == listNumber {
                        // 章节号匹配
                        matchReason = "章节号匹配: \(currentNumber)"
                        possibleMatches.append((index, listArticle, matchReason))
                        existingSameChapterArticle = listArticle
                        existingSameChapterIndex = index
                        print("找到章节号匹配的文章：\(listArticle.title)（ID: \(listArticle.id.uuidString)）")
                        break
                    }
                }
                
                // 处理匹配逻辑
                if let existingArticle = existingSameChapterArticle, let existingIndex = existingSameChapterIndex {
                    print("使用现有章节对象（ID: \(existingArticle.id.uuidString)）替换当前文章（ID: \(article.id.uuidString)）...")
                    // 在这里不能直接修改article，因为它是一个let常量
                    print("章节已被替换，无需修改列表")
                } else {
                    print("未找到匹配的章节，按章节顺序插入当前文章")
                    
                    // 确定插入位置
                    var insertIndex = currentListArticles.count // 默认插入到末尾
                    
                    // 如果能够提取出章节号，则寻找合适的插入位置
                    if let currentNumber = currentChapterNumber {
                        print("当前文章章节号: \(currentNumber)")
                        
                        // 寻找合适的插入位置
                        for (index, listArticle) in currentListArticles.enumerated() {
                            if let listNumber = extractChapterNumber(listArticle.title), 
                               listNumber > currentNumber {
                                insertIndex = index
                                break
                            }
                        }
                    }
                    
                    // 在确定的位置插入文章
                    currentListArticles.insert(article, at: insertIndex)
                    print("已将当前文章插入到位置 \(insertIndex+1)/\(currentListArticles.count)")
                }
            } else {
                print("当前文章ID已在列表中")
            }
        }
        
        // 处理语音按钮点击
        private func handleVoiceButtonTapped() {
            // 获取所有可用的语音列表
            let allVoices = AVSpeechSynthesisVoice.speechVoices()
            print("获取到 \(allVoices.count) 个语音")
            
            // 直接设置可用语音列表
            availableVoices = allVoices
            print("设置到 availableVoices: \(availableVoices.count) 个语音")
            
            // 如果没有选择语音或选择的语音不在可用语音中，默认选择第一个语音
            if speechManager.selectedVoiceIdentifier.isEmpty || !availableVoices.contains(where: { $0.identifier == speechManager.selectedVoiceIdentifier }) {
                if let defaultVoice = availableVoices.first {
                    speechManager.selectedVoiceIdentifier = defaultVoice.identifier
                }
            }
            
            // 显示语音选择器
            DispatchQueue.main.async {
                showVoiceSelector = true
            }
        }
    }
    
    // 检查语音语言是否与文章语言兼容 - 这个方法需要从SettingsButtonsView中调用
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
        let isVoiceChineseVariant = voiceMainLanguage == "zh" || voiceMainLanguage == "yue" || voiceMainLanguage == "cmn"
        let isArticleChineseVariant = articleMainLanguage == "zh" || articleMainLanguage == "yue" || articleMainLanguage == "cmn"
        if isVoiceChineseVariant && isArticleChineseVariant {
            print("中文变体语言，视为兼容")
            return true
        }
        
        // 特殊处理：英文和中文语音的广泛兼容性
        // 有些用户可能喜欢用英文声音读中文，或用中文声音读英文
        let isZhEnCombination = voiceMainLanguage == "zh" && articleMainLanguage == "en"
        let isEnZhCombination = voiceMainLanguage == "en" && articleMainLanguage == "zh"
        if isZhEnCombination || isEnZhCombination {
            print("中英文跨语言朗读，允许用户使用")
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
    
    // 滚动到当前高亮段落
    private func scrollToCurrentParagraph(scrollView: ScrollViewProxy) {
        // 获取全局播放状态
        let playbackManager = PlaybackManager.shared
        
        // 只有在正在朗读状态且朗读的是当前文章时才考虑滚动
        let isGlobalPlaying = playbackManager.isPlaying && playbackManager.currentContentId == article.id
        let isLocalPlaying = speechManager.isPlaying && speechManager.getCurrentArticle()?.id == article.id
        
        if !speechDelegate.isSpeaking || (!isGlobalPlaying && !isLocalPlaying) {
            return // 如果没有朗读活动或不是当前文章，不滚动
        }
        
        guard let paragraphId = getCurrentParagraphId(range: speechDelegate.highlightRange) else { return }
        
        // 提取段落索引
        let paragraphIndex = Int(paragraphId.replacingOccurrences(of: "paragraph_", with: "")) ?? -1
        
        // ==== 严格滚动控制 ====
        // 1. 检查是否与当前可见段落相同 - 如果相同，坚决不滚动
        if paragraphId == currentVisibleParagraphId {
            return
        }
        
        // 2. 只有在绝对必要时才滚动：
        // - 初始化时 (currentVisibleParagraphId 为空)
        // - 段落跳转超过2个段落
        // - 间隔足够长(1.5秒)且是新段落
        let now = Date()
        let timeSinceLastScroll = now.timeIntervalSince(lastScrollTime)
        let isNewParagraph = paragraphIndex != lastScrolledParagraph
        let isParagraphGapLarge = abs(paragraphIndex - lastScrolledParagraph) > 2
        
        // 高度保守的滚动策略，大大减少滚动次数
        let shouldScroll = currentVisibleParagraphId == nil || 
                          isParagraphGapLarge || 
                          (isNewParagraph && timeSinceLastScroll > 1.5)
        
        if !shouldScroll {
            return
        }
        
        // 更新状态，准备滚动
        currentVisibleParagraphId = paragraphId
        lastScrollTime = now
        
        // 只有在段落确实发生变化时才考虑滚动
        if !isNewParagraph {
            return
        }
        
        // 更新最后滚动的段落
        lastScrolledParagraph = paragraphIndex
        
        // 固定锚点 - 使用更小的值，确保段落在屏幕更靠上的位置
        let fixedAnchor: CGFloat = 0.08
        
        // 使用较长的动画持续时间，使滚动更平滑
        let animationDuration: Double = 0.8
        
        print("滚动到段落: \(paragraphId), 索引: \(paragraphIndex)")
        
        // 确保安全地滚动
        withAnimation(.easeInOut(duration: animationDuration)) {
            scrollView.scrollTo(paragraphId, anchor: UnitPoint(x: 0, y: fixedAnchor))
        }
    }
    
    // 查找当前高亮范围所在的段落ID
    private func getCurrentParagraphId(range: NSRange) -> String? {
        // 如果高亮范围无效，直接返回nil
        if range.location == NSNotFound || range.length <= 0 {
            return nil
        }
        
        // 如果高亮范围太接近末尾，可能是边界情况，保留当前段落
        if currentVisibleParagraphId != nil && range.location >= article.content.count - 5 {
            return currentVisibleParagraphId
        }
        
        let paragraphs = article.content.components(separatedBy: "\n\n")
        var currentPosition = 0
        var lastParaId: String? = nil
        var closestDistance = Int.max
        
        // 记录传入的高亮范围信息
        print("获取段落ID - 高亮位置: \(range.location), 长度: \(range.length)")
        
        // 遍历所有段落，找到包含高亮范围的段落
        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphStart = currentPosition
            let paragraphEnd = currentPosition + paragraph.count + 1  // +1 for at least one newline
            
            // 更严格的检查：高亮位置必须在段落范围内
            if range.location >= paragraphStart && range.location <= paragraphEnd {
                // 如果当前段落为空或非常短，不应该触发滚动
                if paragraph.count < 10 {
                    // 跳过很短的段落
                    currentPosition += paragraph.count + 2
                    continue
                }
                
                let paragraphId = "paragraph_\(index)"
                
                // 计算高亮位置在段落中的相对位置
                let relativePosition = range.location - paragraphStart
                
                // 如果高亮位置太接近段落边界（前5%或后5%），可能是边界情况
                // 在这种情况下，如果已有当前段落ID，保留它以避免不必要的滚动
                let isVeryNearBoundary = relativePosition < Int(Double(paragraph.count) * 0.05) || 
                                       relativePosition > Int(Double(paragraph.count) * 0.95)
                
                if isVeryNearBoundary && currentVisibleParagraphId != nil {
                    // 如果太接近边界且有当前段落ID，尝试检查这是否只是高亮的微小变化
                    let currentIndex = Int(currentVisibleParagraphId!.replacingOccurrences(of: "paragraph_", with: "")) ?? -1
                    
                    // 如果当前段落与找到的段落相邻，优先保持当前段落不变
                    if abs(currentIndex - index) <= 1 {
                        print("高亮在段落边界，保持当前段落不变")
                        return currentVisibleParagraphId
                    }
                }
                
                // 对于普通情况，返回找到的段落ID
                return paragraphId
            }
            
            // 额外检查：如果没有找到精确匹配，记录最接近的段落
            let distance = abs(range.location - (paragraphStart + paragraph.count / 2))
            if distance < closestDistance {
                closestDistance = distance
                lastParaId = "paragraph_\(index)"
            }
            
            // 更新位置计数器
            currentPosition += paragraph.count + 2  // +2 for "\n\n"
        }
        
        // 如果没有精确匹配，但有最近的段落，并且距离不是太远（100个字符以内）
        if let lastId = lastParaId, closestDistance < 100 {
            print("使用最接近的段落ID: \(lastId), 距离: \(closestDistance)")
            return lastId
        }
        
        // 如果找不到合适的段落ID，保留当前段落ID（如果有的话）
        if currentVisibleParagraphId != nil {
            print("无法确定段落，保留当前段落ID")
            return currentVisibleParagraphId
        }
        
        return nil
    }
    
    // 获取上次播放位置所在的段落ID
    private func getLastPlaybackParagraphId() -> String? {
        let lastPosition = speechManager.currentPlaybackPosition
        if lastPosition <= 0 {
            return nil
        }
        
        let paragraphs = article.content.components(separatedBy: "\n\n")
        var currentPosition = 0
        
        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphLength = paragraph.count + 2 // +2 for "\n\n"
            
            if lastPosition >= currentPosition && lastPosition < currentPosition + paragraphLength {
                return "paragraph_\(index)"
            }
            
            currentPosition += paragraphLength
        }
        
        return nil
    }
    
    // 检查并同步播放状态 - 解决在播放过程中再次打开相同文档时状态不同步问题
    private func checkAndSyncPlaybackState() {
        print("开始检查并同步播放状态...")
        
        // 获取PlaybackManager实例
        let playbackManager = PlaybackManager.shared
        
        // 获取AVSpeechSynthesizer实例当前是否在朗读 - getSynthesizerStatus方法已经增强了状态检测
        let isSpeaking = SpeechManager.shared.getSynthesizerStatus()
        print("合成器状态检查 - 是否在朗读: \(isSpeaking)，UI显示状态: \(speechManager.isPlaying)，全局状态: \(playbackManager.isPlaying)")
        
        // 检查播放状态是否一致
        let isUiStateSynced = (isSpeaking == speechManager.isPlaying)
        let isGlobalStateSynced = (speechManager.isPlaying == playbackManager.isPlaying)
        
        if isUiStateSynced && isGlobalStateSynced {
            // 所有状态一致，无需操作
            print("所有播放状态已同步，无需修复")
            return
        }
        
        // 重要：检查全局是否有其他文章在播放
        if playbackManager.isPlaying && playbackManager.currentContentId != article.id {
            print("检测到全局有其他文章正在播放(ID: \(playbackManager.currentContentId?.uuidString ?? "未知"))，保留其播放状态")
            
            // 确保本地UI状态与实际状态一致，但不更新全局状态
            if isSpeaking != speechManager.isPlaying {
                speechManager.isPlaying = isSpeaking
                speechManager.objectWillChange.send()
                print("仅更新本地UI状态为: \(isSpeaking ? "播放中" : "已暂停")，保留全局播放状态")
            }
            return
        }
        
        // 如果合成器在朗读但界面显示为暂停，更新界面状态
        if isSpeaking && !speechManager.isPlaying {
            print("检测到状态不同步：合成器正在朗读但UI显示为暂停状态，正在修复...")
            
            // 直接修改UI状态为播放中，不使用异步，确保立即生效
            speechManager.isPlaying = true
            
            // 强制UI进行刷新
            speechManager.objectWillChange.send()
            
            // 更新全局播放状态
            if !playbackManager.isPlaying {
                playbackManager.startPlayback(contentId: article.id, title: article.title, type: .article)
            }
            
            print("已将UI状态更新为播放中，全局状态已同步")
        }
        // 如果合成器不在朗读但界面显示为播放中，更新界面状态
        else if !isSpeaking && speechManager.isPlaying {
            print("检测到状态不同步：合成器已停止但UI显示为播放状态，正在修复...")
            
            // 直接修改UI状态为暂停，不使用异步，确保立即生效
            speechManager.isPlaying = false
            
            // 强制UI进行刷新
            speechManager.objectWillChange.send()
            
            // 更新全局播放状态
            if playbackManager.isPlaying {
                playbackManager.stopPlayback()
            }
            
            print("已将UI状态更新为暂停，全局状态已同步")
        }
        // 确保本地UI状态与全局状态保持一致
        else if speechManager.isPlaying != playbackManager.isPlaying {
            print("检测到UI状态与全局状态不一致，正在同步...")
            
            if speechManager.isPlaying {
                // 本地在播放但全局显示为暂停，更新全局状态
                playbackManager.startPlayback(contentId: article.id, title: article.title, type: .article)
                print("已更新全局状态为播放中")
            } else {
                // 本地已暂停但全局显示为播放中，更新全局状态
                playbackManager.stopPlayback()
                print("已更新全局状态为暂停")
            }
        }
    }
    
    // 播放下一篇文章
    private func playNextArticle() {
        print("========= ArticleReaderView.playNextArticle =========")
        print("当前文章: \(article.title)")
        print("当前文章ID: \(article.id)")
        
        // 获取当前文章所属的文档或列表ID
        let currentContentSourceId = article.listId
        print("当前文章所属内容源ID: \(currentContentSourceId?.uuidString ?? "无")")
        
        // 检查播放列表中的文章是否与当前文章来自同一个内容源
        if !currentListArticles.isEmpty {
            // 获取播放列表中第一篇文章的内容源ID
            let playlistSourceId = currentListArticles.first?.listId
            print("播放列表内容源ID: \(playlistSourceId?.uuidString ?? "无")")
            
            // 如果内容源ID不匹配，需要更新播放列表
            if playlistSourceId != currentContentSourceId {
                print("⚠️ 检测到内容源不匹配，重置播放列表")
                
                // 获取当前文章所在的正确播放列表
                let articlesToPlay = listArticles
                if !articlesToPlay.isEmpty {
                    // 更新播放列表
                    speechManager.updatePlaylist(articlesToPlay)
                    // 同步到当前视图使用的列表
                    currentListArticles = articlesToPlay
                    print("已重置播放列表，文章数: \(articlesToPlay.count)")
                }
            }
        }
        
        print("列表文章数量: \(currentListArticles.count)")
        
        // 打印当前播放列表中所有文章的ID
        if !currentListArticles.isEmpty {
            print("播放列表中的所有文章ID:")
            for (index, listArticle) in currentListArticles.enumerated() {
                print("[\(index)] \(listArticle.title) - ID: \(listArticle.id)")
            }
        } else {
            print("播放列表为空")
        }
        
        // 防止重复快速处理
        let now = Date()
        if now.timeIntervalSince(ArticleReaderView.lastArticlePlayTime) < 1.5 {
            print("⚠️ 播放操作间隔太短，忽略此次请求")
            return
        }
        ArticleReaderView.lastArticlePlayTime = now
        
        // 首先确保停止当前所有播放
        if speechManager.isPlaying {
            // 设置切换文章标志，防止触发自动播放逻辑
            speechDelegate.isArticleSwitching = true
            print("已设置isArticleSwitching=true，防止触发自动播放逻辑")
            
            speechManager.stopSpeaking(resetResumeState: true)
        }
        
        // 重置关键状态标志
        speechDelegate.startPosition = 0
        speechDelegate.wasManuallyPaused = false
        speechDelegate.isArticleSwitching = false // 重置切换标志
        
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
            print("下一篇文章: \(nextArticle.title), ID: \(nextArticle.id)")
            
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
            print("当前文章ID: \(article.id)")
            
            // 如果当前文章不在列表中，尝试播放列表的第一篇文章
            if let firstArticle = currentListArticles.first {
                print("播放列表的第一篇文章: \(firstArticle.title), ID: \(firstArticle.id)")
                
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
    
    // 播放上一篇文章
    private func playPreviousArticle() {
        print("========= ArticleReaderView.playPreviousArticle =========")
        print("当前文章: \(article.title)")
        print("当前文章ID: \(article.id)")
        
        // 获取当前文章所属的文档或列表ID
        let currentContentSourceId = article.listId
        print("当前文章所属内容源ID: \(currentContentSourceId?.uuidString ?? "无")")
        
        // 检查播放列表中的文章是否与当前文章来自同一个内容源
        if !currentListArticles.isEmpty {
            // 获取播放列表中第一篇文章的内容源ID
            let playlistSourceId = currentListArticles.first?.listId
            print("播放列表内容源ID: \(playlistSourceId?.uuidString ?? "无")")
            
            // 如果内容源ID不匹配，需要更新播放列表
            if playlistSourceId != currentContentSourceId {
                print("⚠️ 检测到内容源不匹配，重置播放列表")
                
                // 获取当前文章所在的正确播放列表
                let articlesToPlay = listArticles
                if !articlesToPlay.isEmpty {
                    // 更新播放列表
                    speechManager.updatePlaylist(articlesToPlay)
                    // 同步到当前视图使用的列表
                    currentListArticles = articlesToPlay
                    print("已重置播放列表，文章数: \(articlesToPlay.count)")
                }
            }
        }
        
        print("列表文章数量: \(currentListArticles.count)")
        
        // 打印当前播放列表中所有文章的ID
        if !currentListArticles.isEmpty {
            print("播放列表中的所有文章ID:")
            for (index, listArticle) in currentListArticles.enumerated() {
                print("[\(index)] \(listArticle.title) - ID: \(listArticle.id)")
            }
        } else {
            print("播放列表为空")
        }
        
        // 防止重复快速处理
        let now = Date()
        if now.timeIntervalSince(ArticleReaderView.lastArticlePlayTime) < 1.5 {
            print("⚠️ 播放操作间隔太短，忽略此次请求")
            return
        }
        ArticleReaderView.lastArticlePlayTime = now
        
        // 首先确保停止当前所有播放
        if speechManager.isPlaying {
            // 设置切换文章标志，防止触发自动播放逻辑
            speechDelegate.isArticleSwitching = true
            print("已设置isArticleSwitching=true，防止触发自动播放逻辑")
            
            speechManager.stopSpeaking(resetResumeState: true)
        }
        
        // 重置关键状态标志
        speechDelegate.startPosition = 0
        speechDelegate.wasManuallyPaused = false
        speechDelegate.isArticleSwitching = false // 重置切换标志
        
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
            print("上一篇文章: \(previousArticle.title), ID: \(previousArticle.id)")
            
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
                print("播放列表的最后一篇文章: \(lastArticle.title), ID: \(lastArticle.id)")
                
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
    
    // 从文章标题中提取章节号
    private func extractChapterNumber(from title: String) -> Int? {
        // 支持多种章节标题格式
        // 例如：第33章、第33章 证实、33章、Chapter 33 等
        let patterns = [
            "第(\\d+)章", // 匹配"第33章"
            "第(\\d+)回", // 匹配"第33回"
            "Chapter (\\d+)", // 匹配"Chapter 33"
            "(\\d+)章", // 匹配"33章"
            "章(\\d+)" // 匹配"章33"
        ]
        
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let nsString = title as NSString
                let results = regex.matches(in: title, options: [], range: NSRange(location: 0, length: nsString.length))
                
                if let match = results.first, match.numberOfRanges > 1 {
                    let numberRange = match.range(at: 1)
                    let numberString = nsString.substring(with: numberRange)
                    return Int(numberString)
                }
            } catch {
                print("正则表达式错误: \(error)")
            }
        }
        
        return nil
    }
    
    // 同步播放列表状态
    private func syncPlaylistState() {
        print("同步播放列表状态")
        
        // 获取当前SpeechManager中的播放列表
        let managerList = speechManager.lastPlayedArticles
        
        // 更新当前视图中的播放列表
        if managerList.count > 0 {
            self.currentListArticles = managerList
            print("从SpeechManager更新播放列表，文章数: \(managerList.count)")
            
            // 打印列表中的文章ID
            // print("播放列表中的文章ID:")
            // for (index, article) in managerList.enumerated() {
            //     print("[\(index)] \(article.title) - ID: \(article.id)")
            // }
            
            // 检查当前文章是否在列表中
            if let index = managerList.firstIndex(where: { $0.id == article.id }) {
                print("当前文章在播放列表中，索引: \(index)")
            } else {
                print("警告: 当前文章不在播放列表中")
            }
        } else {
            print("警告: SpeechManager中的播放列表为空")
        }
    }
    
    // 添加处理文本点击事件的方法
    private func handleTextTap(paragraphIndex: Int, paragraphText: String) {
        print("点击了段落 \(paragraphIndex), 内容: \(paragraphText.prefix(20))...")
        
        // 停止当前播放
        if speechManager.isPlaying {
            speechManager.pauseSpeaking()
        }
        
        // 计算段落在文本中的实际字符位置
        let paragraphs = article.content.components(separatedBy: "\n\n")
        var characterPosition = 0
        
        // 计算到当前段落之前的所有文本长度
        for i in 0..<paragraphIndex {
            if i < paragraphs.count {
                characterPosition += paragraphs[i].count + 2 // +2 为段落间的 "\n\n"
            }
        }
        
        print("计算得到的字符位置: \(characterPosition)")
        
        // 设置起始位置和标志位
        speechDelegate.startPosition = characterPosition
        speechDelegate.wasManuallyPaused = true
        
        // 从指定位置开始播放
        speechManager.startSpeakingFromPosition(characterPosition)
    }
    
    // 隐藏底部标签栏
    private func hideTabBar() {
        NotificationCenter.default.post(name: Notification.Name("HideTabBar"), object: nil)
    }
    
    // 显示底部标签栏
    private func showTabBar() {
        NotificationCenter.default.post(name: Notification.Name("ShowTabBar"), object: nil)
    }
} 