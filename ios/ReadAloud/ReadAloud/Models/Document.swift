import Foundation

struct Document: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var fileType: String // 文件类型：txt, pdf, epub, mobi等
    var createdAt: Date
    var progress: Double = 0.0 // 阅读进度，0.0-1.0
    var chapterIds: [UUID] = [] // 存储文档中的章节ID，与ArticleList中的articleIds类似
    
    // 用于显示创建时间的格式化字符串
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    // 获取内容预览
    func contentPreview() -> String {
        if content.count > 50 {
            return String(content.prefix(50)) + "..."
        } else {
            return content
        }
    }
    
    // 将文档转换为ArticleList
    func toArticleList() -> ArticleList {
        return ArticleList(
            id: self.id,
            name: self.title,
            createdAt: self.createdAt,
            articleIds: self.chapterIds
        )
    }
} 