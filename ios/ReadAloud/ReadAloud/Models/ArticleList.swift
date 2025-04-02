import Foundation

/// 表示文章分类列表的模型
struct ArticleList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var articleIds: [UUID] = []
    
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
} 