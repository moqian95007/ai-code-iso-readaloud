import SwiftUI

/// 文本高亮显示视图，用于显示文章内容并高亮当前朗读的部分
struct ArticleHighlightedText: View {
    let text: String
    let highlightRange: NSRange
    let onTap: (Int, String) -> Void
    let themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题
            Text(extractTitle())
                .font(.title)
                .padding()
                .lineLimit(1)
                .truncationMode(.tail)
            
            // 将长文本分成段落
            let paragraphs = text.components(separatedBy: "\n\n")
            
            // 遍历段落并分别处理
            ForEach(0..<paragraphs.count, id: \.self) { index in
                let paragraph = paragraphs[index]
                let paragraphId = "paragraph_\(index)"
                
                // 计算该段落是否包含当前朗读的文本
                let containsHighlight = paragraphContainsHighlight(
                    paragraph: paragraph, 
                    paragraphIndex: index, 
                    paragraphs: paragraphs
                )
                
                Text(paragraph)
                    .font(.system(size: themeManager.fontSize))
                    .padding(5)
                    .background(themeManager.highlightBackgroundColor(isHighlighted: containsHighlight))
                    .id(paragraphId)
                    .onTapGesture {
                        onTap(index, paragraph)
                    }
            }
            .padding(.bottom, 20)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.scrollViewBackgroundColor())
    }
    
    // 从文本中提取标题
    private func extractTitle() -> String {
        // 如果文本有多行，尝试使用第一行作为标题
        let lines = text.components(separatedBy: "\n")
        if let firstLine = lines.first, firstLine.count > 0 {
            // 限制标题长度
            if firstLine.count > 50 {
                return String(firstLine.prefix(50)) + "..."
            }
            return firstLine
        }
        return "文章内容"
    }
    
    // 检查段落是否包含高亮范围
    private func paragraphContainsHighlight(paragraph: String, paragraphIndex: Int, paragraphs: [String]) -> Bool {
        guard highlightRange.location != NSNotFound && highlightRange.length > 0 else {
            return false
        }
        
        var position = 0
        for i in 0..<paragraphIndex {
            position += paragraphs[i].count + 2 // +2 for "\n\n"
        }
        
        let paragraphRange = NSRange(location: position, length: paragraph.count)
        return NSIntersectionRange(paragraphRange, highlightRange).length > 0
    }
} 