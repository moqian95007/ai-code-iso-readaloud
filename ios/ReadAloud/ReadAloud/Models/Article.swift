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
        // 如果文章内容为空或者太短，直接返回默认语言
        if content.isEmpty || content.count < 5 {
            return "zh" // 默认返回中文
        }
        
        // 使用NLLanguageRecognizer进行语言检测
        let recognizer = NLLanguageRecognizer()
        
        // 只处理文章的前1000个字符，提高检测速度和准确性
        let textToProcess = content.count > 1000 ? String(content.prefix(1000)) : content
        recognizer.processString(textToProcess)
        
        // 获取检测结果并计算置信度
        guard let languageCode = recognizer.dominantLanguage?.rawValue,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[recognizer.dominantLanguage!]
        else {
            print("语言检测失败，使用默认中文")
            return "zh" // 默认返回中文
        }
        
        // 检查置信度是否足够高
        if confidence < 0.6 {
            print("语言检测置信度不足: \(confidence)，使用默认中文")
            return "zh" // 置信度低于0.6时使用默认语言
        }
        
        print("检测到文章语言: \(languageCode)，置信度: \(confidence)")
        return languageCode
    }
} 