import Foundation

struct Chapter: Identifiable {
    var id = UUID()
    let title: String
    let startPosition: Double
    let endPosition: Double
    let startIndex: Int
    let endIndex: Int
    var subchapters: [Chapter]?
    
    // 计算章节文本内容
    func extractContent(from fullText: String) -> String {
        guard startIndex < fullText.count, endIndex <= fullText.count, startIndex < endIndex else {
            return ""
        }
        
        let start = fullText.index(fullText.startIndex, offsetBy: startIndex)
        let end = fullText.index(fullText.startIndex, offsetBy: endIndex)
        return String(fullText[start..<end])
    }
}

// 段落模型（之前已有的可以沿用或整合）
struct TextParagraph {
    let text: String
    let startPosition: Double
    let endPosition: Double
    let language: String
    let startIndex: Int
    let endIndex: Int
    let isChapterTitle: Bool
} 