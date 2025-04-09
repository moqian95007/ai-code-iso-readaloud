import Foundation
import NaturalLanguage

struct Article: Identifiable, Codable, TextContent {
    var id = UUID()
    var title: String
    var content: String
    var createdAt: Date
    var listId: UUID? // 添加所属列表ID
    
    // 添加静态语言缓存字典，使用文章ID作为键
    private static var languageCache: [UUID: String] = [:]
    
    // 用于显示创建时间的格式化字符串
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    // 获取内容预览方法已移至 TextContent 协议实现
    
    // 检测文章语言，添加缓存功能
    func detectLanguage() -> String {
        // 先检查缓存，如果有则直接返回
        if let cachedLanguage = Article.languageCache[id] {
            print("使用缓存的语言检测结果: \(cachedLanguage)")
            return cachedLanguage
        }
        
        // 如果文章内容为空或者太短，直接返回默认语言
        if content.isEmpty || content.count < 5 {
            return "zh" // 默认返回中文
        }
        
        // 使用NLLanguageRecognizer进行语言检测
        let recognizer = NLLanguageRecognizer()
        
        // 只处理文章的前2000个字符，提高检测准确性并确保有足够的样本
        let textToProcess = content.count > 2000 ? String(content.prefix(2000)) : content
        recognizer.processString(textToProcess)
        
        // 获取多种可能的语言和对应置信度
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        print("语言检测结果(前3): \(hypotheses)")
        
        // 获取检测结果并计算置信度
        guard let dominantLanguage = recognizer.dominantLanguage,
              let confidence = hypotheses[dominantLanguage]
        else {
            print("语言检测失败，使用默认中文")
            let defaultLanguage = "zh"
            // 缓存结果
            Article.languageCache[id] = defaultLanguage
            return defaultLanguage // 默认返回中文
        }
        
        // 输出详细的语言识别信息
        print("检测到文章语言: \(dominantLanguage.rawValue)，置信度: \(confidence)")
        
        // 增强英文检测的逻辑
        // 1. 计算英文字符的比例
        let englishCharCount = textToProcess.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0.isPunctuation) }.count
        let englishRatio = Double(englishCharCount) / Double(textToProcess.count)
        print("英文字符比例: \(englishRatio * 100)%")
        
        // 2. 如果英文字符比例高于阈值，但被识别为中文，可能是误判
        if englishRatio > 0.7 && dominantLanguage.rawValue.starts(with: "zh") {
            print("检测到大量英文字符但被识别为中文，尝试二次判断")
            
            // 检查是否有英文作为第二可能的语言，且置信度不低
            if let enConfidence = hypotheses.first(where: { $0.key.rawValue.starts(with: "en") })?.value,
               enConfidence > 0.3 { // 英文的置信度超过30%
                print("修正语言识别结果：从中文修正为英文，英文置信度: \(enConfidence)")
                let result = "en"
                Article.languageCache[id] = result
                return result
            }
            
            // 如果英文字符超过85%，直接判断为英文
            if englishRatio > 0.85 {
                print("英文字符比例超过85%，强制判断为英文")
                let result = "en"
                Article.languageCache[id] = result
                return result
            }
        }
        
        // 检查置信度是否足够高
        if confidence < 0.5 {
            print("语言检测置信度不足: \(confidence)，尝试二次判断")
            
            // 如果英文字符比例高，则可能是英文
            if englishRatio > 0.7 {
                print("英文字符比例高，判断为英文")
                let result = "en"
                Article.languageCache[id] = result
                return result
            }
            
            // 默认使用中文
            let result = "zh"
            Article.languageCache[id] = result
            return result
        }
        
        let result = dominantLanguage.rawValue
        Article.languageCache[id] = result
        return result
    }
    
    // 清除某个文章的语言缓存
    static func clearLanguageCache(for articleId: UUID) {
        languageCache.removeValue(forKey: articleId)
    }
    
    // 清除所有语言缓存
    static func clearAllLanguageCache() {
        languageCache.removeAll()
    }
} 