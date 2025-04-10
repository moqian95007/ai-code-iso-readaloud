import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MOBI文件解析器
class MOBIParser {
    // MOBI格式常量
    private struct MOBIConstants {
        static let palmDBHeader = 78
        static let mobiHeader = 16
        static let recordInfoSize = 8
        static let mobiMagic = "MOBI"
        static let exthHeader = "EXTH"
    }
    
    // EXTH记录类型常量
    private struct EXTHType {
        static let author = 100
        static let publisher = 101
        static let description = 103
        static let title = 503
    }
    
    // 解析MOBI文件
    static func parse(url: URL) throws -> String {
        print("开始解析MOBI文件: \(url.lastPathComponent)")
        
        // 读取MOBI文件数据
        let mobiData = try Data(contentsOf: url)
        
        // 验证文件大小
        guard mobiData.count > MOBIConstants.palmDBHeader else {
            throw NSError(domain: "MOBIParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "MOBI文件格式错误：文件太小或损坏"])
        }
        
        // 解析PalmDB Header
        let numRecords = getUInt16(data: mobiData, offset: 76)
        print("MOBI文件记录数量: \(numRecords)")
        
        if numRecords < 1 {
            throw NSError(domain: "MOBIParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "MOBI文件格式错误：没有找到记录"])
        }
        
        // 记录信息偏移量
        var recordsInfoOffset = MOBIConstants.palmDBHeader
        var recordOffsets: [UInt32] = []
        
        // 读取所有记录的偏移地址
        for i in 0..<numRecords {
            let recordOffset = getUInt32(data: mobiData, offset: recordsInfoOffset)
            recordOffsets.append(recordOffset)
            recordsInfoOffset += MOBIConstants.recordInfoSize
        }
        
        // 第0个记录是MOBI头记录
        let headerOffset = Int(recordOffsets[0])
        
        // 验证MOBI标识
        let magicBytes = mobiData.subdata(in: (headerOffset + 16)..<(headerOffset + 20))
        let magic = String(data: magicBytes, encoding: .ascii) ?? ""
        
        if magic != MOBIConstants.mobiMagic {
            throw NSError(domain: "MOBIParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "MOBI文件格式错误：无效的MOBI文件标识"])
        }
        
        // 读取头部信息
        let headerLength = getUInt32(data: mobiData, offset: headerOffset + 20)
        let textEncoding = getUInt32(data: mobiData, offset: headerOffset + 28)
        let fullNameOffset = getUInt32(data: mobiData, offset: headerOffset + 84)
        let fullNameLength = getUInt32(data: mobiData, offset: headerOffset + 88)
        
        // 读取元数据
        var metadata: [String: String] = [:]
        
        // 书名
        if fullNameLength > 0 && fullNameOffset > 0 {
            let titleStart = Int(headerOffset) + Int(fullNameOffset)
            let titleEnd = titleStart + Int(fullNameLength)
            if titleEnd <= mobiData.count {
                let titleData = mobiData.subdata(in: titleStart..<titleEnd)
                if let title = String(data: titleData, encoding: determineTextEncoding(textEncoding)) {
                    metadata["title"] = title
                }
            }
        }
        
        // 查找EXTH头部（扩展头部包含了作者等信息）
        let exthStart = findEXTHHeader(in: mobiData, startFrom: headerOffset)
        if let exthOffset = exthStart {
            let exthLength = getUInt32(data: mobiData, offset: exthOffset + 4)
            let recordCount = getUInt32(data: mobiData, offset: exthOffset + 8)
            
            var currentOffset = exthOffset + 12
            
            // 解析所有EXTH记录
            for _ in 0..<recordCount {
                if currentOffset + 8 > mobiData.count {
                    break
                }
                
                let recordType = getUInt32(data: mobiData, offset: currentOffset)
                let recordLength = getUInt32(data: mobiData, offset: currentOffset + 4)
                
                if recordLength < 8 || currentOffset + Int(recordLength) > mobiData.count {
                    currentOffset += Int(recordLength)
                    continue
                }
                
                let valueData = mobiData.subdata(in: (currentOffset + 8)..<(currentOffset + Int(recordLength)))
                
                // 根据记录类型解析不同的元数据
                if let value = String(data: valueData, encoding: determineTextEncoding(textEncoding)) {
                    switch recordType {
                    case UInt32(EXTHType.author):
                        metadata["author"] = value
                    case UInt32(EXTHType.publisher):
                        metadata["publisher"] = value
                    case UInt32(EXTHType.description):
                        metadata["description"] = value
                    case UInt32(EXTHType.title) where metadata["title"] == nil:
                        metadata["title"] = value
                    default:
                        break
                    }
                }
                
                currentOffset += Int(recordLength)
            }
        }
        
        // 提取文本内容
        var textContent = ""
        
        // 内容通常从第一个记录开始
        let firstContentRecord = 1
        
        // 解析文本内容（通常在非压缩LZ77格式）
        for i in firstContentRecord..<min(Int(numRecords), recordOffsets.count) {
            let recordStart = Int(recordOffsets[i])
            let recordEnd = i + 1 < recordOffsets.count ? Int(recordOffsets[i + 1]) : mobiData.count
            
            let recordData = mobiData.subdata(in: recordStart..<recordEnd)
            
            // 尝试使用检测到的编码解码文本
            if let text = decodeContent(recordData, encoding: determineTextEncoding(textEncoding)) {
                textContent += text
            }
        }
        
        // 移除HTML标签
        textContent = cleanupHTMLContent(textContent)
        
        // 构建完整的文本内容
        var result = ""
        
        // 添加元数据
        if let title = metadata["title"] {
            result += "【电子书标题】\(title)\n\n"
        } else {
            result += "【电子书标题】未知\n\n"
        }
        
        if let author = metadata["author"] {
            result += "【作者】\(author)\n\n"
        }
        
        if let publisher = metadata["publisher"] {
            result += "【出版商】\(publisher)\n\n"
        }
        
        if let description = metadata["description"] {
            result += "【简介】\(description)\n\n"
        }
        
        // 添加正文内容
        result += textContent
        
        // 检查解析内容是否为空
        if isContentEffectivelyEmpty(result) {
            return generateEmptyContentMessage(url.lastPathComponent)
        }
        
        return result
    }
    
    // 检查内容是否实质上为空（只有标题等元数据但没有实际内容）
    private static func isContentEffectivelyEmpty(_ content: String) -> Bool {
        // 移除元数据部分
        let metadataPattern = "【电子书标题】.*?\\n\\n|【作者】.*?\\n\\n|【出版商】.*?\\n\\n|【简介】.*?\\n\\n"
        let contentWithoutMetadata = content.replacingOccurrences(of: metadataPattern, with: "", options: .regularExpression)
        
        // 检查剩余内容是否为空或只有空白字符
        let trimmedContent = contentWithoutMetadata.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedContent.isEmpty {
            return true
        }
        
        // 检查内容去除空格后的长度是否少于100个字符（可能是乱码或无意义内容）
        let contentWithoutSpaces = trimmedContent.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        if contentWithoutSpaces.count <= 100 {
            print("MOBI内容太少或可能是乱码，长度：\(contentWithoutSpaces.count)个字符")
            return true
        }
        
        // 检查是否包含大量可能是乱码的字符
        let nonsensePattern = "RESCsize=|BOUNDARY|FCIS|version=|type="
        if trimmedContent.range(of: nonsensePattern, options: .regularExpression) != nil {
            let contentLines = trimmedContent.components(separatedBy: .newlines)
            // 如果内容行数很少且包含这些乱码特征，也视为无效内容
            if contentLines.count < 10 {
                print("MOBI内容疑似包含乱码")
                return true
            }
        }
        
        return false
    }
    
    // 生成空内容提示信息
    private static func generateEmptyContentMessage(_ filename: String) -> String {
        return """
        【MOBI解析提示】
        
        文件名: \(filename)
        
        无法解析此MOBI文件的内容或解析出的内容不完整（可能是乱码）。ReadAloud应用目前对某些MOBI文件的支持有限，特别是使用DRM保护或特殊压缩格式的MOBI文件。
        
        建议：
        1. 请尝试将此MOBI文件转换为EPUB、TXT或PDF格式后再次导入
        2. 您可以使用Calibre等免费工具进行格式转换
        3. 如果文件包含DRM保护，需要先移除DRM后再进行转换
        
        我们正在努力提升对更多MOBI格式变体的支持，感谢您的理解与耐心。
        """
    }
    
    // 在数据中查找EXTH头部
    private static func findEXTHHeader(in data: Data, startFrom offset: Int) -> Int? {
        let exthString = MOBIConstants.exthHeader.data(using: .ascii)!
        
        for i in offset..<(data.count - exthString.count) {
            var found = true
            for j in 0..<exthString.count {
                if data[i + j] != exthString[j] {
                    found = false
                    break
                }
            }
            if found {
                return i
            }
        }
        
        return nil
    }
    
    // 解码文本内容，处理可能的压缩
    private static func decodeContent(_ data: Data, encoding: String.Encoding) -> String? {
        // 首先尝试直接解码
        if let text = String(data: data, encoding: encoding) {
            return text
        }
        
        // 如果直接解码失败，可能是压缩数据，这里简化处理
        // 实际的MOBI解析器需要处理PalmDoc压缩，这需要更复杂的算法
        return nil
    }
    
    // 根据MOBI编码获取Swift编码
    private static func determineTextEncoding(_ code: UInt32) -> String.Encoding {
        switch code {
        case 1252, 1:
            return .windowsCP1252
        case 65001, 2:
            return .utf8
        default:
            return .utf8 // 默认使用UTF-8
        }
    }
    
    // 从字节获取UInt16
    private static func getUInt16(data: Data, offset: Int) -> UInt16 {
        guard offset + 1 < data.count else { return 0 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
    
    // 从字节获取UInt32
    private static func getUInt32(data: Data, offset: Int) -> UInt32 {
        guard offset + 3 < data.count else { return 0 }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
    
    // 清理HTML内容
    private static func cleanupHTMLContent(_ html: String) -> String {
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
}
