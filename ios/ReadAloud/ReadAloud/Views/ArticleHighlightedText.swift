import SwiftUI
import Combine

/// 文本高亮显示视图，用于显示文章内容并高亮当前朗读的部分
struct ArticleHighlightedText: View {
    let text: String
    let highlightRange: NSRange
    let onTap: (Int, String) -> Void
    let themeManager: ThemeManager
    @ObservedObject private var speechManager = SpeechManager.shared
    
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
                
                // 判断是正在播放时的高亮还是恢复状态下的高亮
                let isPlayingHighlight = SpeechDelegate.shared.isSpeaking
                
                Text(paragraph)
                    .font(.system(size: themeManager.fontSize))
                    .padding(5)
                    .background(themeManager.highlightBackgroundColor(isHighlighted: containsHighlight, isPlayingHighlight: isPlayingHighlight))
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
        // 当正在播放时使用highlightRange
        let speechDelegate = SpeechDelegate.shared
        let playbackManager = PlaybackManager.shared
        
        // 检查当前打开的文章是否为正在播放的文章
        if let currentArticle = speechManager.getCurrentArticle(), 
           playbackManager.isPlaying && 
           playbackManager.currentContentId != nil && 
           playbackManager.currentContentId != currentArticle.id {
            // 如果全局正在播放的不是当前文章，不显示高亮
            return false
        }
        
        if speechDelegate.isSpeaking {
            guard highlightRange.location != NSNotFound && highlightRange.length > 0 else {
                return false
            }
            
            // 计算段落在完整文本中的精确位置
            var position = 0
            for i in 0..<paragraphIndex {
                position += paragraphs[i].count + 2 // +2 for "\n\n"
            }
            
            // 创建代表当前段落的范围
            let paragraphRange = NSRange(location: position, length: paragraph.count)
            
            // 计算段落范围与高亮范围的交集
            let intersection = NSIntersectionRange(paragraphRange, highlightRange)
            let hasHighlight = intersection.length > 0
            
            // 记录详细的调试信息，帮助诊断问题
            if hasHighlight {
                // 仅记录高亮段落的调试信息，避免日志过多
                let paragraphText = paragraph.prefix(20).replacingOccurrences(of: "\n", with: "")
                let highlightStart = highlightRange.location - paragraphRange.location
                let isNearStart = highlightStart < 20
                let isNearEnd = highlightStart > (paragraph.count - 20)
                
                // 只在高亮接近段落开始或结束时记录日志，这通常是出问题的地方
                if isNearStart || isNearEnd {
                    let position = isNearStart ? "开始" : "结束"
                    print("高亮段落[\(paragraphIndex)](\(position)): \"\(paragraphText)...\", 高亮位置: \(highlightStart)/\(paragraph.count)")
                }
            }
            
            return hasHighlight
        } 
        // 当不在播放但处于恢复状态时，高亮上次位置所在的段落
        else if speechManager.isResuming {
            let lastPosition = speechManager.currentPlaybackPosition
            
            if lastPosition <= 0 {
                return false
            }
            
            var position = 0
            for i in 0..<paragraphIndex {
                position += paragraphs[i].count + 2 // +2 for "\n\n"
            }
            
            let paragraphRange = NSRange(location: position, length: paragraph.count)
            return lastPosition >= paragraphRange.location && lastPosition < (paragraphRange.location + paragraphRange.length)
        }
        
        return false
    }
} 