import SwiftUI

/// 浮动球视图
struct FloatingBallView: View {
    @Binding var isVisible: Bool
    @Binding var position: CGPoint
    
    // 记录拖动状态
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    // 添加最近播放的文章状态，用于点击跳转
    @ObservedObject private var articleManager = ArticleManager()
    @ObservedObject private var speechManager = SpeechManager.shared
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.8))
            .frame(width: 50, height: 50)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundColor(.white)
                    .font(.system(size: 24))
            )
            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 1, y: 1)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        self.isDragging = true
                        self.position = CGPoint(
                            x: gesture.location.x,
                            y: gesture.location.y
                        )
                    }
                    .onEnded { _ in
                        self.isDragging = false
                    }
            )
            .onTapGesture {
                handleBallTap()
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut, value: isVisible)
            .onAppear {
                // 加载文章列表
                loadArticles()
            }
    }
    
    // 处理浮动球点击事件
    private func handleBallTap() {
        print("浮动球被点击")
        
        // 设置标志表明是从浮动球进入，防止自动播放
        UserDefaults.standard.set(true, forKey: "isFromFloatingBall")
        
        // 尝试从UserDefaults获取最近播放的文章ID
        if let recentArticleIdString = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastPlayedArticleId),
           let recentArticleId = UUID(uuidString: recentArticleIdString) {
            
            // 重新加载所有文章，确保文章数据是最新的
            articleManager.loadArticles()
            
            // 查找最近播放的文章，确保文章仍然存在于数据库中
            if let recentArticle = articleManager.findArticle(by: recentArticleId) {
                // 找到了最近播放的文章，使用它并加载上次的播放列表
                print("使用最近播放的文章: \(recentArticle.title)")
                
                // 保存当前使用的是上次播放的列表，防止被当前选择的列表覆盖
                UserDefaults.standard.set(true, forKey: "isUsingLastPlaylist")
                
                NotificationCenter.default.post(
                    name: Notification.Name("OpenArticle"),
                    object: nil,
                    userInfo: ["articleId": recentArticle.id, "useLastPlaylist": true]
                )
                return
            } else {
                print("最近播放的文章ID \(recentArticleId) 在当前数据库中找不到")
            }
        } else {
            print("无法从UserDefaults获取最近播放的文章ID")
        }
        
        // 如果没有找到最近播放的文章ID或文章不存在，尝试使用SpeechManager的上次播放列表
        if !speechManager.lastPlayedArticles.isEmpty {
            // 找到上次播放列表中的第一篇文章
            if let lastArticle = speechManager.lastPlayedArticles.first {
                print("使用上次播放列表中的第一篇文章: \(lastArticle.title)")
                // 保存当前使用的是上次播放的列表，防止被当前选择的列表覆盖
                UserDefaults.standard.set(true, forKey: "isUsingLastPlaylist")
                
                // 发送通知，让HomeView处理导航，并包含上一次播放列表的信息
                NotificationCenter.default.post(
                    name: Notification.Name("OpenArticle"),
                    object: nil,
                    userInfo: ["articleId": lastArticle.id, "useLastPlaylist": true]
                )
                return
            }
        } else {
            print("SpeechManager中没有上次播放的列表")
        }
        
        // 如果上述方法都失败，尝试查找有播放记录的文章
        if let playedArticle = findLastPlayedArticle() {
            // 如果找到最近播放过的文章，使用该文章
            print("使用最近播放过的文章: \(playedArticle.title)")
            // 确保这里也使用上次播放列表标记
            UserDefaults.standard.set(true, forKey: "isUsingLastPlaylist")
            
            NotificationCenter.default.post(
                name: Notification.Name("OpenArticle"),
                object: nil,
                userInfo: ["articleId": playedArticle.id, "useLastPlaylist": true]
            )
            return
        }
        
        // 如果所有尝试都失败，使用第一篇文章
        if let firstArticle = articleManager.articles.first {
            // 如果没有播放记录，使用第一篇文章
            print("没有播放记录，使用第一篇文章: \(firstArticle.title)")
            NotificationCenter.default.post(
                name: Notification.Name("OpenArticle"),
                object: nil,
                userInfo: ["articleId": firstArticle.id]
            )
        } else {
            print("没有找到任何可播放的文章")
        }
    }
    
    // 找到最近真正播放过的文章
    private func findLastPlayedArticle() -> Article? {
        // 遍历所有文章，检查它们是否有播放记录
        var mostRecentArticle: Article? = nil
        var mostRecentTime: Date? = nil
        
        for article in articleManager.articles {
            // 检查该文章是否有播放记录
            let wasPlayingKey = UserDefaultsKeys.wasPlaying(for: article.id)
            let lastTimeKey = UserDefaultsKeys.lastPlaybackTime(for: article.id)
            
            // 只有文章曾经播放过，才考虑它
            if UserDefaults.standard.bool(forKey: wasPlayingKey) || 
               UserDefaults.standard.double(forKey: lastTimeKey) > 0 {
                
                // 获取最后播放时间
                if let lastPlayTime = getLastPlayTime(for: article.id) {
                    // 如果这是第一个找到的文章，或者这个文章的播放时间比当前记录的更近
                    if mostRecentTime == nil || lastPlayTime > mostRecentTime! {
                        mostRecentArticle = article
                        mostRecentTime = lastPlayTime
                    }
                }
            }
        }
        
        return mostRecentArticle
    }
    
    // 获取文章最后播放的时间
    private func getLastPlayTime(for articleId: UUID) -> Date? {
        // 检查是否存储了最后播放时间戳
        let key = UserDefaultsKeys.lastPlayTime(for: articleId)
        if let timeInterval = UserDefaults.standard.object(forKey: key) as? TimeInterval {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return nil
    }
    
    // 加载文章列表
    private func loadArticles() {
        // 确保文章已加载
        articleManager.loadArticles()
    }
}

// 预览
struct FloatingBallView_Previews: PreviewProvider {
    static var previews: some View {
        Color.gray.opacity(0.3)
            .edgesIgnoringSafeArea(.all)
            .overlay(
                FloatingBallView(
                    isVisible: .constant(true),
                    position: .constant(CGPoint(x: 200, y: 300))
                )
            )
    }
} 