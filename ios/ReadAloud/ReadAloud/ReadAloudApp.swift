//
//  ReadAloudApp.swift
//  ReadAloud
//
//  Created by moqian on 2025/3/27.
//

import SwiftUI
import AVFoundation

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
    
    // 初始化，设置后台音频播放
    init() {
        setupBackgroundAudio()
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
                        position: $floatingBallManager.position
                    )
                    .ignoresSafeArea()
                }
            }
            // 添加生命周期事件处理
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // 应用即将进入后台，保存进度但不停止播放
                if speechManager.isPlaying {
                    print("应用进入后台，保存播放进度")
                    // 保存当前播放状态到全局播放管理器
                    if let article = speechManager.getCurrentArticle() {
                        let contentType: PlaybackContentType = article.id.description.hasPrefix("doc-") ? .document : .article
                        playbackManager.startPlayback(contentId: article.id, title: article.title, type: contentType)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // 应用恢复到前台，同步播放状态
                print("应用恢复到前台，同步播放状态")
            }
        }
    }
}
