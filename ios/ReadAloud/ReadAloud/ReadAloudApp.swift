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

// 确保引入了 PlaybackContentType 和 PlaybackManager
// 这两个类型在 ArticleHighlightedText.swift 中定义

// 临时添加CacheManager类用于初始化字体
class CacheManager {
    static let shared = CacheManager()
    
    func initializeCustomFonts() {
        // 临时空实现
        print("初始化自定义字体")
    }
}

@main
struct ReadAloudApp: App {
    // 应用状态
    @Environment(\.scenePhase) private var scenePhase
    
    // 主题管理
    @AppStorage("isDarkMode") private var isDarkMode = false
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var documentLibrary = DocumentLibraryManager.shared
    
    // 使用ObservedObject来订阅FloatingBallManager的变化
    @ObservedObject private var floatingBallManager = FloatingBallManager.shared
    
    // 添加一个状态变量跟踪当前是否在播放页面
    @State private var isInPlaybackView = false
    
    // 共享管理器
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var playbackManager = PlaybackManager.shared
    @ObservedObject private var userManager = UserManager.shared
    private let subscriptionManager = SubscriptionManager.shared
    
    // 添加 ArticleManager 实例
    @StateObject private var articleManager = ArticleManager()
    
    // 添加语言管理器
    @ObservedObject private var languageManager = LanguageManager.shared
    
    // 添加一个对象，用于处理URL回调
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 保存所有视图使用的状态
    @StateObject private var listManager = ArticleListManager.shared
    
    init() {
        // 设置日志系统
        LogManager.setup()
        LogManager.shared.log("应用启动", level: .info, category: "App")
        
        // 初始化默认设置
        initializeDefaultSettings()
        
        // 设置主题 - 修复updateTheme调用
        let colorScheme = isDarkMode ? ColorScheme.dark : ColorScheme.light
        UIApplication.updateTheme(with: colorScheme)
        
        // 设置界面默认外观
        configureAppearance()
        
        // 初始化StoreKit测试交易观察
        StoreKitConfiguration.shared.enableStoreKitTestObserver()
        
        // 设置用户管理器
        // UserManager.shared.setupAuthentication()  // 该方法不存在，暂时注释
        
        // 添加应用启动时的详细日志
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 获取收据数据并详细记录
            if let receiptURL = Bundle.main.appStoreReceiptURL {
                if let receiptData = try? Data(contentsOf: receiptURL) {
                    print("收据数据长度：\(receiptData.count)")
                    print("收据URL路径：\(receiptURL.path)")
                    print("收据文件名：\(receiptURL.lastPathComponent)")
                    print("是否沙盒收据：\(receiptURL.lastPathComponent == "sandboxReceipt")")
                    
                    LogManager.shared.log("收据文件名：\(receiptURL.lastPathComponent)", level: .debug, category: "StoreKit")
                    LogManager.shared.log("是否沙盒收据：\(receiptURL.lastPathComponent == "sandboxReceipt")", level: .debug, category: "StoreKit")
                } else {
                    print("⚠️ 无法获取App Store收据数据 - 文件无法读取")
                    LogManager.shared.log("无法获取App Store收据数据 - 文件无法读取", level: .warning, category: "StoreKit")
                }
            } else {
                print("⚠️ 无法获取App Store收据数据 - 收据URL为空")
                LogManager.shared.log("无法获取App Store收据数据 - 收据URL为空", level: .warning, category: "StoreKit")
            }
            
            // 检查编译模式
            #if DEBUG
            print("应用编译模式: DEBUG")
            LogManager.shared.log("应用编译模式: DEBUG", level: .debug, category: "App")
            #else
            print("应用编译模式: RELEASE")
            LogManager.shared.log("应用编译模式: RELEASE", level: .debug, category: "App")
            #endif
            
            // 检查当前设备信息
            let device = UIDevice.current
            print("设备信息: \(device.name), \(device.systemName) \(device.systemVersion)")
            LogManager.shared.log("设备信息: \(device.name), \(device.systemName) \(device.systemVersion)", level: .info, category: "App")
            
            // 预加载用户订阅状态
            // SubscriptionManager.shared.checkActiveSubscription(forceRefresh: true)  // 该方法不存在，暂时注释
        }
    }
    
    // 配置UI默认外观
    private func configureAppearance() {
        // 初始化自定义字体
        CacheManager.shared.initializeCustomFonts()
        
        // 设置后台音频会话
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .duckOthers, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("设置后台音频会话失败: \(error.localizedDescription)")
            LogManager.shared.log("设置后台音频会话失败: \(error.localizedDescription)", level: .error, category: "App")
        }
        
        // 初始化语言设置
        _ = languageManager
        print("应用启动: 初始化语言设置为 \(languageManager.currentLanguage.rawValue)")
        LogManager.shared.log("初始化语言设置为 \(languageManager.currentLanguage.rawValue)", level: .info, category: "App")
    }
    
    // 应用视图
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
