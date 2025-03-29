import Foundation
import UIKit

// 文档模型
struct Document: Identifiable, Codable {
    var id = UUID()
    let title: String
    let fileName: String
    let fileURL: URL
    let fileType: DocumentType
    let fileHash: String?  // 文件的MD5哈希值
    var progress: Double = 0.0
    var lastReadDate: Date = Date()
    var coverImageData: Data? = nil  // 存储封面图片数据
    
    enum CodingKeys: String, CodingKey {
        case id, title, fileName, fileURL, fileType, fileHash, progress, lastReadDate, coverImageData
    }
}

// 文档类型枚举
enum DocumentType: String, Codable, CaseIterable {
    case txt
    case epub
    case pdf
    case mobi
    case other
    
    var description: String {
        switch self {
        case .txt: return "文本文档"
        case .epub: return "EPUB电子书"
        case .pdf: return "PDF文档"
        case .mobi: return "Mobi电子书"
        case .other: return "其他文档"
        }
    }
    
    static func fromFileExtension(_ extension: String) -> DocumentType {
        switch `extension`.lowercased() {
        case "txt": return .txt
        case "epub": return .epub
        case "pdf": return .pdf
        case "mobi": return .mobi
        default: return .other
        }
    }
}

// 封面提取器
class CoverExtractor {
    static func extractCover(from url: URL, fileType: DocumentType) -> Data? {
        switch fileType {
        case .epub:
            return extractEpubCover(from: url)
        case .pdf:
            return extractPDFCover(from: url)
        case .mobi:
            return extractMobiCover(from: url)
        default:
            return nil
        }
    }
    
    private static func extractEpubCover(from url: URL) -> Data? {
        // 这里需要引入第三方库如ZIPFoundation来解压epub
        // 简化版：尝试在epub文件中查找常见的封面图片路径
        do {
            // 实际项目中建议使用专门的EPUB解析库
            // 例如： https://github.com/FolioReader/FolioReaderKit
            return nil // 简化版暂不实现完整逻辑
        } catch {
            print("提取EPUB封面出错: \(error)")
            return nil
        }
    }
    
    private static func extractPDFCover(from url: URL) -> Data? {
        guard let pdf = CGPDFDocument(url as CFURL) else { return nil }
        guard let page = pdf.page(at: 1) else { return nil }
        
        let pageRect = page.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        
        let img = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: pageRect.size))
            
            ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            ctx.cgContext.drawPDFPage(page)
        }
        
        return img.jpegData(compressionQuality: 0.7)
    }
    
    private static func extractMobiCover(from url: URL) -> Data? {
        // Mobi格式较复杂，需要专门的解析库
        // 这里简化处理
        return nil
    }
} 