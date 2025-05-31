import Foundation

/// 表示单个内容项的阅读进度
struct ContentProgress: Codable, Identifiable {
    // ID使用文章ID或章节ID
    var id: String
    // 内容类型
    var contentType: String // 可能是 "article", "chapter", "document"
    // 最后阅读时间
    var lastReadTime: Date
    // 阅读进度百分比 (0.0-1.0)
    var progress: Double
    // 阅读位置
    var position: Int
    // 所属文档ID
    var documentId: String?
    // 标题，用于展示
    var title: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case lastReadTime = "last_read_time"
        case progress
        case position
        case documentId = "document_id"
        case title
    }
}

/// 用户阅读进度集合
struct ReadingProgress: Codable {
    // 用户ID
    var userId: Int
    // 上次同步时间
    var lastSyncTime: Date
    // 各内容阅读进度
    var contentProgresses: [ContentProgress]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case lastSyncTime = "last_sync_time"
        case contentProgresses = "content_progresses"
    }
    
    // 从UserDefaults中读取阅读进度
    static func loadFromUserDefaults() -> [ContentProgress] {
        var result = [ContentProgress]()
        
        // 获取所有文章ID
        if let articleIdsData = UserDefaults.standard.data(forKey: UserDefaultsKeys.lastPlayedArticles) {
            // 直接从SpeechManager中存储的lastPlayedArticles获取文章列表
            if let articles = try? JSONDecoder().decode([Article].self, from: articleIdsData) {
                print("从UserDefaults中读取到\(articles.count)篇最近播放的文章")
                
                for article in articles {
                    // 获取阅读进度
                    let progressKey = UserDefaultsKeys.lastProgress(for: article.id)
                    let positionKey = UserDefaultsKeys.lastPlaybackPosition(for: article.id)
                    let timeKey = UserDefaultsKeys.lastPlayTime(for: article.id)
                    
                    if let progress = UserDefaults.standard.object(forKey: progressKey) as? Double,
                       let position = UserDefaults.standard.object(forKey: positionKey) as? Int {
                        
                        // 获取最后阅读时间
                        let lastReadTime: Date
                        if let timestamp = UserDefaults.standard.object(forKey: timeKey) as? TimeInterval {
                            lastReadTime = Date(timeIntervalSince1970: timestamp)
                        } else {
                            lastReadTime = Date()
                        }
                        
                        // 创建进度对象
                        let contentProgress = ContentProgress(
                            id: article.id.uuidString,
                            contentType: "article",
                            lastReadTime: lastReadTime,
                            progress: progress,
                            position: position,
                            documentId: nil,
                            title: article.title
                        )
                        
                        result.append(contentProgress)
                        print("添加文章阅读进度: \(article.title), 进度: \(Int(progress * 100))%, 位置: \(position)")
                    }
                }
            } else {
                print("无法解码lastPlayedArticles为Article数组")
            }
        } else {
            print("UserDefaults中没有找到lastPlayedArticles数据")
        }
        
        // 获取所有文档进度
        if let documentsData = UserDefaults.standard.data(forKey: "documents"),
           let documents = try? JSONDecoder().decode([Document].self, from: documentsData) {
            
            for document in documents {
                // 获取文档的章节ID和阅读进度
                if document.progress > 0 {
                    // 文档级别的进度
                    let docProgress = ContentProgress(
                        id: document.id.uuidString,
                        contentType: "document",
                        lastReadTime: Date(), // 从lastDocumentPlayTime_获取
                        progress: document.progress,
                        position: 0, // 文档级别不关注具体位置
                        documentId: nil,
                        title: document.title
                    )
                    result.append(docProgress)
                    print("添加文档阅读进度: \(document.title), 进度: \(Int(document.progress * 100))%")
                    
                    // 当前章节的进度
                    let lastChapterKey = "lastChapter_\(document.id.uuidString)"
                    if let lastChapterIndex = UserDefaults.standard.object(forKey: lastChapterKey) as? Int,
                       lastChapterIndex >= 0 && lastChapterIndex < document.chapterIds.count {
                        
                        let chapterId = document.chapterIds[lastChapterIndex]
                        let progressKey = UserDefaultsKeys.lastProgress(for: chapterId)
                        let positionKey = UserDefaultsKeys.lastPlaybackPosition(for: chapterId)
                        
                        if let progress = UserDefaults.standard.object(forKey: progressKey) as? Double,
                           let position = UserDefaults.standard.object(forKey: positionKey) as? Int {
                            
                            let chapterProgress = ContentProgress(
                                id: chapterId.uuidString,
                                contentType: "chapter",
                                lastReadTime: Date(),
                                progress: progress,
                                position: position,
                                documentId: document.id.uuidString,
                                title: "第\(lastChapterIndex+1)章" // 实际实现应获取章节标题
                            )
                            result.append(chapterProgress)
                            print("添加章节阅读进度: 第\(lastChapterIndex+1)章, 进度: \(Int(progress * 100))%, 位置: \(position)")
                        }
                    }
                }
            }
        }
        
        print("总共加载了\(result.count)条阅读进度记录")
        return result
    }
    
    // 将阅读进度应用到UserDefaults
    static func applyProgressesToUserDefaults(progresses: [ContentProgress]) {
        for progress in progresses {
            // 将字符串ID转换为UUID
            guard let id = UUID(uuidString: progress.id) else { continue }
            
            // 根据内容类型存储进度
            switch progress.contentType {
            case "article", "chapter":
                // 存储阅读进度和位置
                UserDefaults.standard.set(progress.progress, forKey: UserDefaultsKeys.lastProgress(for: id))
                UserDefaults.standard.set(progress.position, forKey: UserDefaultsKeys.lastPlaybackPosition(for: id))
                // 存储最后阅读时间
                let timestamp = progress.lastReadTime.timeIntervalSince1970
                UserDefaults.standard.set(timestamp, forKey: UserDefaultsKeys.lastPlayTime(for: id))
                
            case "document":
                // 如果是文档类型，需要更新Document对象
                if let documentsData = UserDefaults.standard.data(forKey: "documents"),
                   var documents = try? JSONDecoder().decode([Document].self, from: documentsData) {
                    
                    // 查找并更新文档进度
                    if let index = documents.firstIndex(where: { $0.id.uuidString == progress.id }) {
                        documents[index].progress = progress.progress
                        
                        // 保存更新后的文档列表
                        if let updatedData = try? JSONEncoder().encode(documents) {
                            UserDefaults.standard.set(updatedData, forKey: "documents")
                        }
                    }
                }
                
            default:
                break
            }
        }
        
        // 通知进度已更新
        NotificationCenter.default.post(name: NSNotification.Name("ReadingProgressUpdated"), object: nil)
    }
} 