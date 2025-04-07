import Foundation

/// 表示文章分类列表的模型
struct ArticleList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var articleIds: [UUID] = []
    var isDocument: Bool = false // 标记该列表是否为文档转换而来
    
    // 格式化创建日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    // 创建一个新的列表
    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }
    
    // 自定义初始化方法，支持从Document创建
    init(id: UUID, name: String, createdAt: Date, articleIds: [UUID], isDocument: Bool = true) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.articleIds = articleIds
        self.isDocument = isDocument
    }
    
    // 将列表转换为Document（如果不是Document转换而来则返回nil）
    func toDocument(content: String = "", fileType: String = "txt", progress: Double = 0.0) -> Document? {
        return Document(
            id: self.id,
            title: self.name,
            content: content,
            fileType: fileType,
            createdAt: self.createdAt,
            progress: progress,
            chapterIds: self.articleIds
        )
    }
} 