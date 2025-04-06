import SwiftUI

/// 浮动球视图
struct FloatingBallView: View {
    @Binding var isVisible: Bool
    @Binding var position: CGPoint
    
    // 记录拖动状态
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    // 使用单例模式获取共享实例
    @ObservedObject private var articleManager = ArticleManager.shared
    @ObservedObject private var speechManager = SpeechManager.shared
    @ObservedObject private var documentLibrary = DocumentLibraryManager.shared
    
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
                // 加载文章列表和文档列表
                loadArticles()
                loadDocuments()
            }
    }
    
    // 处理浮动球点击事件
    private func handleBallTap() {
        print("浮动球被点击")
        
        // 设置标志表明是从浮动球进入，防止自动播放
        UserDefaults.standard.set(true, forKey: "isFromFloatingBall")
        
        // 重新同步UserDefaults
        UserDefaults.standard.synchronize()
        
        // 重新加载文档库和文章库确保数据最新
        documentLibrary.loadDocuments()
        articleManager.loadArticles()
        
        // 尝试获取最近播放类型（文章或文档）
        let contentTypeKey = "lastPlayedContentType"
        var lastPlayedType = UserDefaults.standard.string(forKey: contentTypeKey) ?? "article"
        
        // 检查文档库中是否有最近打开的文档，如果有则优先使用文档类型
        if let lastDocIdString = UserDefaults.standard.string(forKey: "lastOpenedDocumentId"),
           let lastDocId = UUID(uuidString: lastDocIdString),
           documentLibrary.findDocument(by: lastDocId) != nil {
            lastPlayedType = "document" 
            print("通过检查最近打开的文档ID发现有效文档，覆盖内容类型为document")
        }
        
        print("最近播放的内容类型: \(lastPlayedType)")
        // 记录UserDefaults中所有与内容类型相关的键值对
        print("调试UserDefaults - lastOpenedDocumentId: \(UserDefaults.standard.string(forKey: "lastOpenedDocumentId") ?? "nil")")
        print("调试UserDefaults - lastPlayedArticleId: \(UserDefaults.standard.string(forKey: UserDefaultsKeys.lastPlayedArticleId) ?? "nil")")
        print("调试SpeechManager - 是否有章节列表: \(!speechManager.lastPlayedArticles.isEmpty)")
        
        // 根据最近播放类型选择处理方式
        if lastPlayedType == "document" {
            print("根据最近播放类型，应该优先尝试打开文档")
            
            // 额外检查：尝试获取最近一次文档ID，验证是否真的应该优先打开文档
            let lastDocumentKey = "lastOpenedDocumentId"
            if let lastDocIdString = UserDefaults.standard.string(forKey: lastDocumentKey) {
                print("找到最近播放的文档ID字符串: \(lastDocIdString)，确认将优先打开文档")
            } else {
                print("警告：虽然最近播放类型是document，但找不到最近播放的文档ID")
            }
            
            // 优先尝试加载文档
            if tryOpenDocument() {
                print("成功打开文档")
                return
            }
            
            // 如果文档无法打开，尝试加载文章
            if tryOpenArticle() {
                print("未找到文档，回退到打开文章")
                return
            }
            
            print("文档和文章都无法打开")
        } else {
            // 默认先尝试加载文章
            if tryOpenArticle() {
                print("成功打开文章")
                return
            }
            
            // 如果文章无法打开，尝试加载文档
            if tryOpenDocument() {
                print("未找到文章，回退到打开文档")
                return
            }
            
            print("文章和文档都无法打开")
        }
    }
    
    // 尝试打开文章
    private func tryOpenArticle() -> Bool {
        // 尝试从UserDefaults获取最近播放的文章ID
        if let recentArticleIdString = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastPlayedArticleId) {
            print("找到最近播放的文章ID字符串: \(recentArticleIdString)")
            
            if let recentArticleId = UUID(uuidString: recentArticleIdString) {
                print("成功将文章ID字符串转换为UUID: \(recentArticleId), 类型: \(type(of: recentArticleId))")
                
                // 重新加载所有文章，确保文章数据是最新的
                articleManager.loadArticles()
                print("文章库中共有 \(articleManager.articles.count) 篇文章")
                
                // 打印所有文章的ID和标题，用于调试
                for article in articleManager.articles {
                    print("文章库中的文章: '\(article.title)', ID: \(article.id)")
                }
                
                // 查找最近播放的文章，确保文章仍然存在于数据库中
                if let recentArticle = articleManager.findArticle(by: recentArticleId) {
                    // 找到了最近播放的文章，使用它并加载上次的播放列表
                    print("使用最近播放的文章: \(recentArticle.title), ID: \(recentArticle.id)")
                    
                    // 保存当前使用的是上次播放的列表，防止被当前选择的列表覆盖
                    UserDefaults.standard.set(true, forKey: "isUsingLastPlaylist")
                    
                    // 记录最近播放的内容类型为文章
                    UserDefaults.standard.set("article", forKey: "lastPlayedContentType")
                    
                    // 延迟发送通知，确保UI已准备好
                    DispatchQueue.main.async {
                        // 使用明确的useLastPlaylist参数
                        let userInfo: [String: Any] = [
                            "articleId": recentArticle.id,
                            "useLastPlaylist": true
                        ]
                        
                        print("发送OpenArticle通知，文章ID: \(recentArticle.id), 标题: \(recentArticle.title)")
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenArticle"),
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                    return true
                } else {
                    print("最近播放的文章ID \(recentArticleId) 在当前数据库中找不到，搜索了 \(articleManager.articles.count) 篇文章")
                }
            } else {
                print("无法将文章ID字符串转换为UUID: \(recentArticleIdString)")
            }
        } else {
            print("无法从UserDefaults获取最近播放的文章ID")
        }
        
        // 如果没有找到最近播放的文章ID或文章不存在，尝试使用SpeechManager的上次播放列表
        if !speechManager.lastPlayedArticles.isEmpty {
            print("SpeechManager中有 \(speechManager.lastPlayedArticles.count) 篇上次播放的文章")
            
            // 找到上次播放列表中的第一篇文章
            if let lastArticle = speechManager.lastPlayedArticles.first {
                print("获取上次播放列表中的第一篇文章: \(lastArticle.title), ID: \(lastArticle.id)")
                
                // 检查这个文章是否存在于文章管理器中
                if articleManager.findArticle(by: lastArticle.id) != nil {
                    print("确认文章存在于文章库中: \(lastArticle.title)")
                    
                    // 保存当前使用的是上次播放的列表，防止被当前选择的列表覆盖
                    UserDefaults.standard.set(true, forKey: "isUsingLastPlaylist")
                    
                    // 记录最近播放的内容类型为文章
                    UserDefaults.standard.set("article", forKey: "lastPlayedContentType")
                    
                    // 延迟发送通知，确保UI已准备好
                    DispatchQueue.main.async {
                        // 使用明确的useLastPlaylist参数
                        let userInfo: [String: Any] = [
                            "articleId": lastArticle.id,
                            "useLastPlaylist": true
                        ]
                        
                        print("发送OpenArticle通知，文章ID: \(lastArticle.id), 标题: \(lastArticle.title)")
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenArticle"),
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                    return true
                } else {
                    print("上次播放列表中的文章ID \(lastArticle.id) 在当前数据库中找不到")
                }
            }
        } else {
            print("SpeechManager中没有上次播放的列表")
        }
        
        // 如果上述方法都失败，尝试查找有播放记录的文章
        if let playedArticle = findLastPlayedArticle() {
            // 如果找到最近播放过的文章，使用该文章
            print("使用最近播放过的文章: \(playedArticle.title), ID: \(playedArticle.id)")
            
            // 确保这里也使用上次播放列表标记
            UserDefaults.standard.set(true, forKey: "isUsingLastPlaylist")
            
            // 记录最近播放的内容类型为文章
            UserDefaults.standard.set("article", forKey: "lastPlayedContentType")
            
            // 延迟发送通知，确保UI已准备好
            DispatchQueue.main.async {
                // 使用明确的useLastPlaylist参数
                let userInfo: [String: Any] = [
                    "articleId": playedArticle.id,
                    "useLastPlaylist": true
                ]
                
                print("发送OpenArticle通知，文章ID: \(playedArticle.id), 标题: \(playedArticle.title)")
                NotificationCenter.default.post(
                    name: Notification.Name("OpenArticle"),
                    object: nil,
                    userInfo: userInfo
                )
            }
            return true
        } else {
            print("没有找到有播放记录的文章")
        }
        
        // 如果有文章可用，使用第一篇文章
        if let firstArticle = articleManager.articles.first {
            // 如果没有播放记录，使用第一篇文章
            print("没有播放记录，使用第一篇文章: \(firstArticle.title), ID: \(firstArticle.id)")
            
            // 记录最近播放的内容类型为文章
            UserDefaults.standard.set("article", forKey: "lastPlayedContentType")
            
            // 延迟发送通知，确保UI已准备好
            DispatchQueue.main.async {
                let userInfo: [String: Any] = ["articleId": firstArticle.id]
                
                print("发送OpenArticle通知，文章ID: \(firstArticle.id), 标题: \(firstArticle.title)")
                NotificationCenter.default.post(
                    name: Notification.Name("OpenArticle"),
                    object: nil,
                    userInfo: userInfo
                )
            }
            return true
        } else {
            print("文章库为空，无法打开文章")
        }
        
        return false
    }
    
    // 尝试打开文档
    private func tryOpenDocument() -> Bool {
        // 确保获取最新的UserDefaults值
        UserDefaults.standard.synchronize()
        
        // 尝试获取最近播放的文档ID
        let lastDocumentKey = "lastOpenedDocumentId"
        if let lastDocIdString = UserDefaults.standard.string(forKey: lastDocumentKey) {
            print("找到最近播放的文档ID字符串: \(lastDocIdString)")
            
            // 尝试将字符串转换为UUID
            if let lastDocId = UUID(uuidString: lastDocIdString) {
                print("成功将文档ID字符串转换为UUID: \(lastDocId), 类型: \(type(of: lastDocId))")
                
                // 重新加载所有文档，确保文档数据是最新的
                documentLibrary.loadDocuments()
                print("文档库中共有 \(documentLibrary.documents.count) 个文档")
                
                // 打印所有文档的ID，用于调试
                for doc in documentLibrary.documents {
                    print("文档库中的文档: '\(doc.title)', ID: \(doc.id)")
                }
                
                // 查找文档
                if let document = documentLibrary.findDocument(by: lastDocId) {
                    print("找到最近播放的文档: \(document.title), ID: \(document.id)")
                    
                    // 记录最近播放的内容类型为文档
                    UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
                    print("设置最近播放内容类型为document，文档: \(document.title)")
                    UserDefaults.standard.synchronize()
                    
                    // 发送打开文档的通知
                    DispatchQueue.main.async {
                        let userInfo: [String: Any] = ["documentId": document.id]
                        
                        print("发送OpenDocument通知，文档ID: \(document.id), 标题: \(document.title)")
                        NotificationCenter.default.post(
                            name: Notification.Name("OpenDocument"),
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                    return true
                } else {
                    print("最近播放的文档ID \(lastDocId) 在当前数据库中找不到，搜索了 \(documentLibrary.documents.count) 个文档")
                }
            } else {
                print("无法将文档ID字符串转换为UUID: \(lastDocIdString)")
            }
        } else {
            print("UserDefaults中没有找到最近播放的文档ID")
        }
        
        // 如果没有最近播放的文档，尝试使用第一个文档
        if !documentLibrary.documents.isEmpty {
            let firstDoc = documentLibrary.documents[0]
            print("使用第一个文档: \(firstDoc.title), ID: \(firstDoc.id)")
            
            // 记录最近播放的内容类型为文档
            UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
            print("设置最近播放内容类型为document，文档: \(firstDoc.title)")
            UserDefaults.standard.synchronize()
            
            // 发送打开文档的通知
            DispatchQueue.main.async {
                let userInfo: [String: Any] = ["documentId": firstDoc.id]
                
                print("发送OpenDocument通知，文档ID: \(firstDoc.id), 标题: \(firstDoc.title)")
                NotificationCenter.default.post(
                    name: Notification.Name("OpenDocument"),
                    object: nil,
                    userInfo: userInfo
                )
            }
            return true
        } else {
            print("文档库为空，无法打开文档")
        }
        
        return false
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
    
    // 加载文档列表
    private func loadDocuments() {
        // 确保文档已加载
        documentLibrary.loadDocuments()
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