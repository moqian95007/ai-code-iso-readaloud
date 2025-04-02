import SwiftUI

/**
 * 自定义视图，用于显示带有高亮效果的文本
 */
struct HighlightedText: View {
    let text: String
    let highlightRange: NSRange
    // 添加朗读状态参数
    let isSpeaking: Bool
    
    var body: some View {
        Text(attributedString)
    }
    
    // 根据高亮范围构建富文本
    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)
        
        // 只有在朗读状态下才应用高亮
        if isSpeaking && 
           highlightRange.location != NSNotFound && 
           highlightRange.length > 0 && 
           highlightRange.location + highlightRange.length <= text.utf16.count {
            
            // 创建AttributedString的范围
            if let range = Range(highlightRange, in: text) {
                // 转换为AttributedString的索引
                let startIndex = AttributedString.Index(range.lowerBound, within: attributedString)
                let endIndex = AttributedString.Index(range.upperBound, within: attributedString)
                
                // 确保索引有效
                if let startIndex = startIndex, let endIndex = endIndex {
                    let attrRange = startIndex..<endIndex
                    
                    // 设置高亮属性
                    attributedString[attrRange].backgroundColor = .yellow
                    attributedString[attrRange].foregroundColor = .black
                    attributedString[attrRange].font = .system(.body, weight: .bold)
                }
            }
        }
        
        return attributedString
    }
} 