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

// 确保引入了 PlaybackContentType 和 PlaybackManager
// 这两个类型在 ArticleHighlightedText.swift 中定义

@main
struct ReadAloudApp: App {
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
    
    // 添加一个对象，用于处理URL回调
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 初始化，设置后台音频播放
    init() {
        setupBackgroundAudio()
        
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
            // 添加生命周期事件处理
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // 应用即将进入后台，保存进度但不停止播放
                if speechManager.isPlaying {
                    print("应用进入后台，保存播放进度")
                    // 保存当前播放进度
                    speechManager.savePlaybackProgress()
                    // 保存当前播放状态到全局播放管理器
                    if let article = speechManager.getCurrentArticle() {
                        let contentType: PlaybackContentType = article.id.description.hasPrefix("doc-") ? .document : .article
                        playbackManager.startPlayback(contentId: article.id, title: article.title, type: contentType)
                    }
                } else if speechManager.isResuming {
                    // 即使未播放但有恢复状态时也保存进度
                    print("应用进入后台，未播放但有恢复状态，保存进度")
                    speechManager.savePlaybackProgress()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // 应用恢复到前台，同步播放状态
                print("应用恢复到前台，同步播放状态")
            }
        }
    }
}
