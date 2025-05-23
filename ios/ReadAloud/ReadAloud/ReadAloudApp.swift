//
//  ReadAloudApp.swift
//  ReadAloud
//
//  Created by moqian on 2025/3/27.
//

import SwiftUI
import AVFoundation
import UIKit
import StoreKit
import Combine
import CoreData

// 确保引入了 PlaybackContentType 和 PlaybackManager
// 这两个类型在 ArticleHighlightedText.swift 中定义

// 临时定义CacheManager，如果项目中没有这个类
class CacheManager {
    static let shared = CacheManager()
    
    func initializeCustomFonts() {
        // 临时空实现
        print("初始化自定义字体")
    }
}

// 临时定义LogManager，如果项目中没有这个类
class LogManager {
    static func setup() {
        // 临时空实现
        print("设置日志系统")
    }
}

@main
struct ReadAloudApp: App {
    // 获取环境
    @Environment(\.scenePhase) private var scenePhase
    
    // 获取AppStorage
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    // 使用ObservedObject来订阅FloatingBallManager的变化
    @ObservedObject private var floatingBallManager = FloatingBallManager.shared
    
    // 添加一个状态变量跟踪当前是否在播放页面
    @State private var isInPlaybackView = false
    
    // 添加SpeechManager实例
    @ObservedObject private var speechManager = SpeechManager.shared
    
    // 添加PlaybackManager实例，用于全局播放状态管理
    @ObservedObject private var playbackManager = PlaybackManager.shared
    
    // 添加UserManager实例，用于管理用户状态
    @ObservedObject private var userManager = UserManager.shared
    
    // 添加 ArticleManager 实例
    @StateObject private var articleManager = ArticleManager()
    
    // 添加语言管理器
    @ObservedObject private var languageManager = LanguageManager.shared
    
    // 添加一个对象，用于处理URL回调
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 保存所有视图使用的状态
    @StateObject private var listManager = ArticleListManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var documentLibrary = DocumentLibraryManager.shared
    
    init() {
        // 预加载AudioFileManager以确保它被初始化
        _ = AudioFileManager.shared
        
        // 设置主题 - 修复updateTheme调用
        let colorScheme = isDarkMode ? ColorScheme.dark : ColorScheme.light
        // 检查ThemeManager是否有updateTheme方法，如果没有则跳过
        // themeManager.updateTheme(for: colorScheme)
        
        // 初始化自定义字体
        CacheManager.shared.initializeCustomFonts()
        
        setupBackgroundAudio()
        
        // 初始化语言设置
        _ = LanguageManager.shared
        print("应用启动: 初始化语言设置为 \(LanguageManager.shared.currentLanguage.rawValue)")
        
        // 初始化StoreKit配置
        _ = StoreKitConfiguration.shared
        StoreKitConfiguration.shared.enableStoreKitTestObserver()
        
        // 初始化订阅检查器
        _ = SubscriptionChecker.shared
        
        // 初始化订阅服务
        _ = SubscriptionService.shared
        
        // 应用启动时同步用户状态
        syncUserStatusOnLaunch()
    }
    
    // 设置后台音频会话
    private func setupBackgroundAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("设置后台音频会话失败: \(error.localizedDescription)")
        }
    }
    
    // 应用启动时同步用户状态
    private func syncUserStatusOnLaunch() {
        // 检查用户是否已登录
        if userManager.isLoggedIn, let user = userManager.currentUser, user.isTokenValid {
            print("应用启动: 用户已登录，同步用户状态")
            
            // 创建同步队列
            let syncQueue = DispatchQueue(label: "com.readaloud.syncQueue", qos: .utility)
            
            // 异步执行同步操作
            syncQueue.async {
                // 1. 同步订阅状态
                SubscriptionRepository.shared.loadSubscriptionsForUser(user.id)
                
                // 2. 同步剩余导入数量
                self.userManager.syncRemoteImportCountToLocal(user: user)
                
                // 完成同步后发送通知，更新UI
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                    print("应用启动: 用户状态同步完成")
                }
            }
        } else {
            print("应用启动: 用户未登录，跳过同步")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // 主要内容视图 - 使用TabView替代原来的NavigationView
                MainTabView()
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EnterPlaybackView"))) { _ in
                        // 进入播放页面时隐藏浮动球
                        print("App层级收到EnterPlaybackView通知，隐藏浮动球")
                        
                        // 在主线程延迟隐藏浮动球，避免可能的导航冲突
                        DispatchQueue.main.async {
                            floatingBallManager.hide()
                            isInPlaybackView = true
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExitPlaybackView"))) { _ in
                        // 离开播放页面时显示浮动球
                        print("App层级收到ExitPlaybackView通知，显示浮动球")
                        
                        // 记录离开播放界面的时间戳
                        UserDefaults.standard.set(Date(), forKey: "lastExitPlaybackViewTime")
                        
                        // 延迟显示浮动球，避免在导航动画过程中显示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            floatingBallManager.show()
                            isInPlaybackView = false
                        }
                    }
                
                // 浮动球视图
                // 使用ZStack使浮动球显示在其他视图上方
                if !isInPlaybackView {
                    FloatingBallView(
                        isVisible: $floatingBallManager.isVisible,
                        position: $floatingBallManager.position,
                        articleManager: articleManager
                    )
                    .ignoresSafeArea()
                }
            }
            .environmentObject(articleManager)
            .environmentObject(listManager)
            .environmentObject(themeManager)
            .environmentObject(documentLibrary)
            .environmentObject(playbackManager)
            .onAppear {
                // 应用启动时自动加载数据
                articleManager.loadArticles()
                listManager.loadLists()
                documentLibrary.loadDocuments()
                
                // 配置日志
                LogManager.setup()
                
                // 写入初始设置
                initializeDefaultSettings()
            }
            .onChange(of: scenePhase) { newScenePhase in
                switch newScenePhase {
                case .active:
                    print("App is active")
                    // 应用变为活动状态时执行的代码
                    articleManager.loadArticles()
                    listManager.loadLists()
                    documentLibrary.loadDocuments()
                case .inactive:
                    print("App is inactive")
                    // 应用变为非活动状态时执行的代码
                    speechManager.savePlaybackProgress()
                    
                    // 应用退出时保存文档进度
                    let contentType = UserDefaults.standard.string(forKey: "lastPlayedContentType") ?? "article"
                    if contentType == "document" {
                        // 发送通知保存文档进度
                        print("应用进入非活动状态：保存文档进度")
                        NotificationCenter.default.post(name: Notification.Name("SaveDocumentProgress"), object: nil)
                    }
                case .background:
                    print("App is in background")
                    // 应用进入后台时执行的代码
                    speechManager.savePlaybackProgress()
                    
                    // 应用进入后台时保存文档进度
                    let contentType = UserDefaults.standard.string(forKey: "lastPlayedContentType") ?? "article"
                    if contentType == "document" {
                        // 发送通知保存文档进度
                        print("应用进入后台：保存文档进度")
                        NotificationCenter.default.post(name: Notification.Name("SaveDocumentProgress"), object: nil)
                    }
                @unknown default:
                    print("Unknown scene phase")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.languageDidChange)) { _ in
                // 语言设置发生变化时的处理
                print("语言设置已更改为: \(languageManager.currentLanguage.rawValue)")
                
                // 强制刷新所有视图
                UserDefaults.standard.set(Date(), forKey: "lastLanguageChangeTime")
                
                // 确保更新所有UI
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: NSNotification.Name("SubscriptionStatusUpdated"), object: nil)
                }
            }
        }
    }
    
    // 初始化默认设置
    private func initializeDefaultSettings() {
        // 这里写入应用首次启动时需要的默认设置
        if UserDefaults.standard.object(forKey: "isFirstLaunch") == nil {
            UserDefaults.standard.set(false, forKey: "isFirstLaunch")
            
            // 设置默认主题和字体大小
            UserDefaults.standard.set(false, forKey: "isDarkMode")
            
            // 将默认语言设置为系统语言
            let languageCode = Locale.current.languageCode ?? "zh"
            UserDefaults.standard.set(languageCode, forKey: "selectedLanguage")
            
            print("首次启动，初始化默认设置完成")
        }
    }
}
