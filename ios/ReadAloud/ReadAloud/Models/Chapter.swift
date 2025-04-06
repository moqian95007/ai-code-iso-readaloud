import Foundation

/// 章节模型，用于存储识别出的文档章节
struct Chapter: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String // 章节标题，例如 "第一章 初见"
    var content: String // 章节内容
    var startIndex: Int // 在原文中的起始位置
    var endIndex: Int // 在原文中的结束位置
    var documentId: UUID // 所属文档ID
    
    // 计算章节序号
    var chapterNumber: Int {
        // 尝试从标题中提取数字
        if let number = extractNumber(from: title) {
            return number
        }
        return 0
    }
    
    // 实现Equatable协议
    static func == (lhs: Chapter, rhs: Chapter) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.startIndex == rhs.startIndex &&
               lhs.endIndex == rhs.endIndex &&
               lhs.documentId == rhs.documentId
    }
    
    // 从标题中提取数字
    private func extractNumber(from title: String) -> Int? {
        // 匹配常见的章节格式
        let patterns = [
            "第([0-9零一二三四五六七八九十百千万]+)[章回节集卷篇]", // 中文数字或阿拉伯数字章节格式
            "Chapter\\s*([0-9]+)", // 英文章节格式
            "([0-9]+)\\.", // 数字后跟点的格式
            "([0-9]+)、" // 数字后跟顿号的格式
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, options: [], range: nsRange) {
                    // 提取匹配的数字部分
                    if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: title) {
                        let extracted = String(title[range])
                        
                        // 如果是中文数字，转换为阿拉伯数字
                        if let number = Int(extracted) {
                            return number
                        } else {
                            return convertChineseNumberToArabic(extracted)
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // 将中文数字转换为阿拉伯数字
    private func convertChineseNumberToArabic(_ chineseNumber: String) -> Int {
        let chineseNumbers: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
            "十": 10, "百": 100, "千": 1000, "万": 10000
        ]
        
        var result = 0
        var temp = 0
        var lastUnit = 1
        
        for char in chineseNumber {
            if let value = chineseNumbers[char] {
                if value >= 10 { // 是单位（十、百、千、万）
                    if temp == 0 { // 如果前面没有数字，如"十"开头的情况
                        temp = 1
                    }
                    result += temp * value
                    temp = 0
                    lastUnit = value
                } else { // 是数字（一到九）
                    temp = value
                }
            }
        }
        
        // 处理最后的数字
        result += temp
        
        return result == 0 ? 1 : result // 如果解析失败，默认返回1
    }
} 