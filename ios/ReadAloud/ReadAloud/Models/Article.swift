import Foundation
import NaturalLanguage

struct Article: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var createdAt: Date
    
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
    
    // 检测文章语言
    func detectLanguage() -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(content)
        guard let languageCode = recognizer.dominantLanguage?.rawValue else {
            return "zh" // 默认返回中文
        }
        return languageCode
    }
} 