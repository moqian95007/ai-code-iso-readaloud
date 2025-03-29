import Foundation
import PDFKit
import UIKit

class TextExtractor {
    enum ExtractionError: Error, LocalizedError {
        case fileNotFound
        case unsupportedFormat
        case extractionFailed
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "找不到文件"
            case .unsupportedFormat:
                return "不支持的文件格式"
            case .extractionFailed:
                return "文本提取失败"
            }
        }
    }
    
    static func extractText(from document: Document) throws -> String {
        guard FileManager.default.fileExists(atPath: document.fileURL.path) else {
            throw ExtractionError.fileNotFound
        }
        
        do {
            // 对大文件进行验证
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: document.fileURL.path)
            let fileSize = fileAttributes[.size] as? UInt64 ?? 0
            
            // 如果文件太大（超过10MB），可能需要分块处理
            if fileSize > 10_000_000 {
                print("警告：文件较大 (\(fileSize/1024/1024) MB)，提取可能需要较长时间")
            }
            
            switch document.fileType {
            case .txt:
                return try extractFromTextFile(document.fileURL)
            case .pdf:
                return try extractFromPDF(document.fileURL)
            case .epub:
                return try extractFromEPUB(document.fileURL)
            case .mobi:
                return try extractFromMobi(document.fileURL)
            case .other:
                throw ExtractionError.unsupportedFormat
            }
        } catch let error as ExtractionError {
            throw error
        } catch {
            print("文本提取错误: \(error)")
            throw ExtractionError.extractionFailed
        }
    }
    
    private static func extractFromTextFile(_ url: URL) throws -> String {
        // 支持的编码列表
        let encodings: [String.Encoding] = [
            .utf8,
            .isoLatin1,
            .windowsCP1252,  // 常用于西欧语言
            .macOSRoman,     // 苹果系统编码
            .ascii,          // ASCII编码
            .japaneseEUC,    // 日文编码
            .utf16,          // UTF-16编码
            .utf16BigEndian, // UTF-16 大端编码
            .utf16LittleEndian // UTF-16 小端编码
        ]
        
        // 尝试读取文件数据
        guard let data = try? Data(contentsOf: url) else {
            throw ExtractionError.extractionFailed
        }
        
        // 尝试不同的编码读取
        var extractionError: Error? = nil
        
        for encoding in encodings {
            if let content = String(data: data, encoding: encoding), !content.isEmpty {
                return content
            }
        }
        
        // 如果已知编码都不能解析，尝试强制解码为UTF-8并忽略错误
        let content = String(decoding: data, as: UTF8.self)
        if !content.isEmpty {
            return content
        }
        
        // 无法解码
        throw ExtractionError.extractionFailed
    }
    
    private static func extractFromPDF(_ url: URL) throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ExtractionError.extractionFailed
        }
        
        var text = ""
        for i in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            if let pageText = page.string {
                text += pageText
                text += "\n\n"
            }
        }
        
        if text.isEmpty {
            throw ExtractionError.extractionFailed
        }
        return text
    }
    
    private static func extractFromEPUB(_ url: URL) throws -> String {
        // 实际应用中应使用专门的EPUB解析库
        // 例如FolioReaderKit或使用ZIPFoundation解压后解析XML
        
        // 临时实现，返回一些示例文本以避免错误
        // TODO: 实现真正的EPUB解析
        return "这是一个EPUB文件，暂不支持全文提取。建议转换为PDF或TXT格式后使用。\n\n要阅读此文件，需要实现完整的EPUB解析功能。"
    }
    
    private static func extractFromMobi(_ url: URL) throws -> String {
        // Mobi格式较复杂，需要专门的解析库
        // 临时实现，返回一些示例文本以避免错误
        // TODO: 实现真正的Mobi解析
        return "这是一个Mobi格式电子书，暂不支持全文提取。建议转换为PDF或TXT格式后使用。\n\n要阅读此文件，需要实现完整的Mobi解析功能。"
    }
} 
