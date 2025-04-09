import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Compression
import CoreFoundation
import ZIPFoundation

// EPUB和MOBI文件解析器
class EBookParser {
    // EPUB结构相关常量
    private struct EPUBConstants {
        static let containerPath = "META-INF/container.xml"
        static let contentFolderName = "OEBPS"
        static let contentTypesFile = "mimetype"
    }
    
    // MOBI相关常量
    private struct MOBIConstants {
        static let headerIdentifier = "BOOKMOBI"
        static let textEncoding = String.Encoding.utf8
    }
    
    // ZIP文件结构常量
    private struct ZipConstants {
        static let localFileHeaderSignature: UInt32 = 0x04034b50
        static let centralDirectorySignature: UInt32 = 0x02014b50
        static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
        static let dataDescriptorSignature: UInt32 = 0x08074b50
    }
    
    // 解析EPUB文件
    static func parseEPUB(url: URL) throws -> String {
        print("开始解析EPUB文件: \(url.lastPathComponent)")
        
        // 创建临时目录用于解压文件
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            // 创建临时目录
            try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
            
            // 读取EPUB文件（其实是一个ZIP文件）
            let epubData = try Data(contentsOf: url)
            
            // 解压文件到临时目录
            try simplifiedUnzip(epubData, to: tempDirectoryURL)
            
            // 解析container.xml找到内容文件
            let containerURL = tempDirectoryURL.appendingPathComponent(EPUBConstants.containerPath)
            guard fileManager.fileExists(atPath: containerURL.path) else {
                throw NSError(domain: "EBookParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "EPUB格式错误：找不到container.xml文件"])
            }
            
            // 解析container.xml找到OPF文件位置
            let containerXml = try String(contentsOf: containerURL, encoding: .utf8)
            guard let opfPath = extractOPFPath(from: containerXml) else {
                throw NSError(domain: "EBookParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "EPUB格式错误：无法找到内容文件路径"])
            }
            
            let opfURL = tempDirectoryURL.appendingPathComponent(opfPath)
            guard fileManager.fileExists(atPath: opfURL.path) else {
                throw NSError(domain: "EBookParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "EPUB格式错误：找不到内容文件"])
            }
            
            // 从OPF文件解析目录和内容
            let opfContent = try String(contentsOf: opfURL, encoding: .utf8)
            
            // 提取元数据（标题等）
            let metadata = extractMetadata(from: opfContent)
            
            // 提取所有HTML/XHTML内容文件并按顺序排列
            let contentFiles = extractContentFiles(from: opfContent)
            
            // 基于opfURL的目录解析内容文件的绝对路径
            let opfDirectory = opfURL.deletingLastPathComponent()
            
            // 读取并解析所有内容文件
            var fullText = ""
            fullText += "【电子书标题】\(metadata.title)\n\n"
            
            if !metadata.author.isEmpty {
                fullText += "【作者】\(metadata.author)\n\n"
            }
            
            // 章节内容
            for contentFile in contentFiles {
                let contentURL = opfDirectory.appendingPathComponent(contentFile)
                if fileManager.fileExists(atPath: contentURL.path) {
                    let htmlContent = try String(contentsOf: contentURL, encoding: .utf8)
                    let plainText = extractTextFromHTML(htmlContent)
                    fullText += "\n\n\(plainText)\n\n"
                }
            }
            
            // 清理临时文件
            try? fileManager.removeItem(at: tempDirectoryURL)
            
            return fullText
        } catch {
            // 确保清理临时文件
            try? fileManager.removeItem(at: tempDirectoryURL)
            throw error
        }
    }
    
    // 更简单的解压方法，使用FileManager的解压能力
    private static func simplifiedUnzip(_ zipData: Data, to destinationURL: URL) throws {
        // 将ZIP数据先保存为临时文件
        let temporaryZipURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try zipData.write(to: temporaryZipURL)
        
        defer {
            // 清理临时ZIP文件
            try? FileManager.default.removeItem(at: temporaryZipURL)
        }
        
        do {
            // 使用FileManager来解压文件
            try FileManager.default.unzipItem(at: temporaryZipURL, to: destinationURL)
        } catch {
            print("标准解压失败: \(error.localizedDescription)")
            
            // 如果标准解压失败，尝试使用备用方法
            try fallbackExtractEPUB(zipData, to: destinationURL)
        }
    }
    
    // 备用方法：简化版的EPUB解析，专注于提取文本内容而不是完整解压
    private static func fallbackExtractEPUB(_ epubData: Data, to destinationURL: URL) throws {
        // 假设EPUB文件结构一般较为简单
        // 先搜索"META-INF/container.xml"的内容
        if let containerXMLStart = findPattern(in: epubData, pattern: "<container".data(using: .utf8)!),
           let containerXMLEnd = findPattern(in: epubData, pattern: "</container>".data(using: .utf8)!, startFrom: containerXMLStart) {
            
            let containerXMLRange = containerXMLStart..<(containerXMLEnd + "</container>".count)
            let containerXMLData = epubData.subdata(in: containerXMLRange)
            
            // 创建META-INF目录
            let metaInfDir = destinationURL.appendingPathComponent("META-INF")
            try FileManager.default.createDirectory(at: metaInfDir, withIntermediateDirectories: true)
            
            // 保存container.xml
            try containerXMLData.write(to: metaInfDir.appendingPathComponent("container.xml"))
            
            // 尝试查找并提取OPF文件
            if let opfPathStart = findPattern(in: containerXMLData, pattern: "full-path=\"".data(using: .utf8)!) {
                let startPos = opfPathStart + "full-path=\"".count
                var opfPath = ""
                
                for i in startPos..<containerXMLData.count {
                    if containerXMLData[i] == 0x22 { // 双引号
                        break
                    }
                    if let char = String(data: Data([containerXMLData[i]]), encoding: .utf8) {
                        opfPath.append(char)
                    }
                }
                
                if !opfPath.isEmpty {
                    // 尝试提取OPF文件
                    if let opfStart = findPattern(in: epubData, pattern: "<package".data(using: .utf8)!),
                       let opfEnd = findPattern(in: epubData, pattern: "</package>".data(using: .utf8)!, startFrom: opfStart) {
                        
                        let opfRange = opfStart..<(opfEnd + "</package>".count)
                        let opfData = epubData.subdata(in: opfRange)
                        
                        // 保存OPF文件
                        let opfComponents = opfPath.components(separatedBy: "/")
                        var currentPath = destinationURL
                        
                        // 创建目录结构
                        for i in 0..<opfComponents.count-1 {
                            currentPath = currentPath.appendingPathComponent(opfComponents[i])
                            try FileManager.default.createDirectory(at: currentPath, withIntermediateDirectories: true)
                        }
                        
                        // 保存OPF文件
                        try opfData.write(to: destinationURL.appendingPathComponent(opfPath))
                        
                        // 简单提取HTML内容文件
                        let opfString = String(data: opfData, encoding: .utf8) ?? ""
                        extractHtmlFilesFromEPUB(epubData, opfString: opfString, destinationURL: destinationURL)
                    }
                }
            }
        }
    }
    
    // 在数据中查找模式
    private static func findPattern(in data: Data, pattern: Data, startFrom: Int = 0) -> Int? {
        for i in startFrom..<(data.count - pattern.count + 1) {
            var match = true
            for j in 0..<pattern.count {
                if data[i + j] != pattern[j] {
                    match = false
                    break
                }
            }
            if match {
                return i
            }
        }
        return nil
    }
    
    // 从EPUB数据中提取HTML文件
    private static func extractHtmlFilesFromEPUB(_ epubData: Data, opfString: String, destinationURL: URL) {
        let htmlPattern = "href=\"([^\"]*)\"[^>]*media-type=\"application/xhtml\\+xml\""
        let regex = try? NSRegularExpression(pattern: htmlPattern, options: [.caseInsensitive])
        
        if let regex = regex {
            let nsString = opfString as NSString
            let matches = regex.matches(in: opfString, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: opfString) {
                    let htmlPath = String(opfString[range])
                    
                    // 查找这个HTML文件的内容
                    if let htmlStart = findPattern(in: epubData, pattern: "<html".data(using: .utf8)!),
                       let htmlEnd = findPattern(in: epubData, pattern: "</html>".data(using: .utf8)!, startFrom: htmlStart) {
                        
                        let htmlRange = htmlStart..<(htmlEnd + "</html>".count)
                        let htmlData = epubData.subdata(in: htmlRange)
                        
                        // 保存HTML文件
                        let pathComponents = htmlPath.components(separatedBy: "/")
                        var currentPath = destinationURL
                        
                        // 创建目录结构
                        for i in 0..<pathComponents.count-1 {
                            currentPath = currentPath.appendingPathComponent(pathComponents[i])
                            try? FileManager.default.createDirectory(at: currentPath, withIntermediateDirectories: true)
                        }
                        
                        try? htmlData.write(to: destinationURL.appendingPathComponent(htmlPath))
                    }
                }
            }
        }
    }
    
    // 解析MOBI文件
    static func parseMOBI(url: URL) throws -> String {
        print("开始解析MOBI文件: \(url.lastPathComponent)")
        
        // 由于MOBI格式复杂且没有标准Swift解析库，我们提供一个基础实现
        // 在实际应用中，建议使用专门的MOBI解析库或转换为其他格式
        
        do {
            // 读取文件数据
            let data = try Data(contentsOf: url)
            
            // 检查是否是有效的MOBI文件（简单检查）
            guard data.count > 60 else {
                throw NSError(domain: "EBookParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "MOBI文件太小，无法解析"])
            }
            
            // 检查文件头部是否包含MOBI标识
            let header = data.prefix(60)
            if let headerString = String(data: header, encoding: .ascii),
               headerString.contains(MOBIConstants.headerIdentifier) {
                
                // 这里是一个简单的实现，实际的MOBI解析非常复杂
                // 我们尝试提取一些可能是文本的部分
                var text = "【MOBI文件】\n\n文件名: \(url.lastPathComponent)\n\n"
                
                // 尝试在文件中寻找文本块（这是一个非常简化的方法）
                // 实际的MOBI解析需要理解整个文件结构
                if let potentialText = scanForText(in: data) {
                    text += potentialText
                } else {
                    text += "无法提取MOBI文件中的文本内容。建议将MOBI转换为EPUB或TXT格式后再导入。"
                }
                
                return text
            } else {
                throw NSError(domain: "EBookParser", code: 11, userInfo: [NSLocalizedDescriptionKey: "不是有效的MOBI文件格式"])
            }
        } catch {
            throw error
        }
    }
    
    // 从container.xml中提取OPF文件路径
    private static func extractOPFPath(from containerXml: String) -> String? {
        // 简单的XML解析，寻找rootfile元素的full-path属性
        guard let range = containerXml.range(of: "full-path=\"", options: .caseInsensitive) else {
            return nil
        }
        
        let startIndex = range.upperBound
        guard let endIndex = containerXml[startIndex...].firstIndex(of: "\"") else {
            return nil
        }
        
        return String(containerXml[startIndex..<endIndex])
    }
    
    // 从OPF文件中提取元数据
    private static func extractMetadata(from opfContent: String) -> (title: String, author: String) {
        var title = "未知标题"
        var author = ""
        
        // 提取标题
        if let titleRange = opfContent.range(of: "<dc:title[^>]*>(.*?)</dc:title>", options: .regularExpression) {
            let titleXml = String(opfContent[titleRange])
            if let startRange = titleXml.range(of: ">"),
               let endRange = titleXml.range(of: "</", options: .backwards) {
                title = String(titleXml[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 提取作者
        if let authorRange = opfContent.range(of: "<dc:creator[^>]*>(.*?)</dc:creator>", options: .regularExpression) {
            let authorXml = String(opfContent[authorRange])
            if let startRange = authorXml.range(of: ">"),
               let endRange = authorXml.range(of: "</", options: .backwards) {
                author = String(authorXml[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return (title, author)
    }
    
    // 从OPF文件中提取内容文件
    private static func extractContentFiles(from opfContent: String) -> [String] {
        var contentFiles: [String] = []
        
        // 简单提取所有item元素
        let pattern = "<item[^>]*href=\"([^\"]*)\"[^>]*media-type=\"application/xhtml\\+xml\"[^>]*>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        
        if let regex = regex {
            let matches = regex.matches(in: opfContent, options: [], range: NSRange(opfContent.startIndex..., in: opfContent))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: opfContent) {
                    let href = String(opfContent[range])
                    contentFiles.append(href)
                }
            }
        }
        
        return contentFiles
    }
    
    // 从HTML中提取纯文本
    private static func extractTextFromHTML(_ html: String) -> String {
        // 保存原始HTML用于在正则替换前处理段落
        var result = html
        
        // 替换常见HTML实体
        let entities = [
            "&nbsp;": " ",
            "&lt;": "<",
            "&gt;": ">",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'"
        ]
        
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // 在删除所有HTML标签前，先将段落和换行标签替换为特殊标记
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<p[^>]*>", with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<div[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<h[1-6][^>]*>", with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: .regularExpression)
        
        // 移除HTML标签
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // 规范化多余的空白和换行（但保留有意义的换行）
        result = result.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // 去除每行首尾的空白字符
        var lines = result.components(separatedBy: "\n")
        for i in 0..<lines.count {
            lines[i] = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        result = lines.joined(separator: "\n")
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 在MOBI文件数据中扫描文本
    private static func scanForText(in data: Data) -> String? {
        // 在MOBI文件中找到可能的文本块
        // 注意：这是一个非常简化的方法，不会处理复杂的MOBI结构
        
        // 尝试寻找HTML或纯文本内容
        let patterns = ["<html", "<body", "<h1", "<h2", "chapter", "Chapter", "CHAPTER"]
        var contentRanges: [Range<Data.Index>] = []
        
        for pattern in patterns {
            if let patternData = pattern.data(using: .utf8) {
                var searchRange = data.startIndex..<data.endIndex
                while let range = data.range(of: patternData, options: [], in: searchRange) {
                    contentRanges.append(range)
                    searchRange = range.upperBound..<data.endIndex
                }
            }
        }
        
        if contentRanges.isEmpty {
            return nil
        }
        
        // 按照位置排序
        contentRanges.sort { $0.lowerBound < $1.lowerBound }
        
        // 尝试从第一个匹配之后提取一些内容
        if let firstRange = contentRanges.first {
            let startIndex = firstRange.lowerBound
            let endIndex = min(startIndex + 10000, data.endIndex) // 提取不超过10KB的内容
            let contentData = data[startIndex..<endIndex]
            
            // 尝试不同的编码
            let encodings: [String.Encoding] = [.utf8, .ascii, .utf16LittleEndian, .utf16BigEndian]
            
            for encoding in encodings {
                if let text = String(data: contentData, encoding: encoding) {
                    // 提取纯文本
                    return extractTextFromHTML(text)
                }
            }
        }
        
        return nil
    }
} 