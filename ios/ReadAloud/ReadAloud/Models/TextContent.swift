import Foundation

/// 提供通用文本内容处理的协议
protocol TextContent {
    /// 文本内容
    var content: String { get }
    
    /// 获取内容预览
    /// - Parameter maxLength: 最大预览长度，默认为 50
    /// - Returns: 截断后的预览文本
    func contentPreview(maxLength: Int) -> String
}

extension TextContent {
    /// 默认实现的内容预览方法
    func contentPreview(maxLength: Int = 50) -> String {
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        } else {
            return content
        }
    }
} 