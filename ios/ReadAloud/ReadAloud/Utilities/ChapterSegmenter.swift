import Foundation
import NaturalLanguage

class ChapterSegmenter {
    
    // 章节标记正则表达式模式
    private static let chapterPatterns: [String] = [
        // 中文章节模式 - 进一步简化和宽松的匹配
        "^\\s*第[一二三四五六七八九十百千万零〇\\d]+[章节回集卷部篇].*$",
        "^\\s*第\\s*[一二三四五六七八九十百千万零〇\\d]+\\s*[章节回集卷部篇].*$",
        "^\\s*[第]?\\s*[一二三四五六七八九十]\\s*[章节回集卷部篇].*$",
        "^\\s*[一二三四五六七八九十][、.．].*$",
        "^\\s*引子.*$",
        "^\\s*序章.*$",
        "^\\s*尾声.*$",
        "^\\s*前言.*$",
        "^\\s*后记.*$",
        
        // 非常简化的数字章节模式 - 进一步放宽匹配
        "^\\s*第\\s*\\d+\\s*章.*$",
        "^\\s*\\d+\\s*章.*$",
        
        // 英文章节模式
        "^\\s*CHAPTER\\s+[\\dIVXLC]+.*$",
        "^\\s*Chapter\\s+[\\dIVXLC]+.*$",
        "^\\s*PART\\s+[\\dIVXLC]+.*$",
        "^\\s*Part\\s+[\\dIVXLC]+.*$",
        
        // 数字标记模式
        "^\\s*\\d+\\..*$"
    ]
    
    // 在 ChapterSegmenter 类中添加一个新的正则表达式模式
    private static let additionalPatterns: [String] = [
        "^\\s*[Cc]hapter\\s+\\d+.*$",  // 匹配 "Chapter 1" 等
        "^\\s*[Cc]ontent.*$",          // 匹配 "Content" 标题
        "^\\s*目录.*$"                  // 匹配 "目录" 标题
    ]
    
    // 默认章节大小（字符数）- 改为1000字符一章
    private static let defaultChapterSize = 1000
    
    // 将强制启用自动分段改为false，或者添加可选参数
    private static let forceAutoSegmentation = false
    
    // 将文本分割成段落并识别章节
    static func splitTextIntoParagraphs(_ text: String, forceAutoSegmentation: Bool = false) -> (paragraphs: [TextParagraph], chapters: [Chapter]) {
        // 记录开始时间，用于性能分析
        let startTime = CFAbsoluteTimeGetCurrent()
        print("【章节识别】开始分析章节，文本长度: \(text.count)字符")
        
        var chapterStartIndices: [(title: String, index: Int, paragraphIndex: Int)] = []
        var paragraphs: [TextParagraph] = []
        
        // 1. 使用更高效的行分割方法 - 一次性分割所有行
        let lines = text.components(separatedBy: .newlines)
        print("【章节识别】文本共有\(lines.count)行")
        
        // 2. 预编译正则表达式，避免重复创建
        let strictPatterns = [
            "^\\s*第[一二三四五六七八九十百千万零〇\\d]+章\\s*$",
            "^\\s*第[一二三四五六七八九十百千万零〇\\d]+章[：:].+$",
            "^\\s*第\\s*[一二三四五六七八九十百千万零〇\\d]+\\s*章\\s*$",
            "^\\s*第\\s*[一二三四五六七八九十百千万零〇\\d]+\\s*章[：:].+$",
            "^\\s*第\\s*\\d+\\s*章\\s*$",
            "^\\s*第\\s*\\d+\\s*章[：:].+$",
            "^\\s*Chapter\\s*\\d+\\s*$",
            "^\\s*Chapter\\s*\\d+[：:].+$"
        ]
        
        // 预编译正则表达式
        let precompiledRegexes = strictPatterns.compactMap { pattern -> NSRegularExpression? in
            try? NSRegularExpression(pattern: pattern, options: [])
        }
        
        // 3. 使用批处理来提高性能
        let batchSize = 1000
        let batchCount = (lines.count + batchSize - 1) / batchSize
        
        // 临时存储章节候选项
        var chapterCandidates = [(lineIndex: Int, title: String, position: Int)]()
        
        // 计算文本位置的变量
        var currentPosition = 0
        
        // 4. 批量处理文本行
        for batchIndex in 0..<batchCount {
            let startLineIndex = batchIndex * batchSize
            let endLineIndex = min((batchIndex + 1) * batchSize, lines.count)
            
            for lineIndex in startLineIndex..<endLineIndex {
                let line = lines[lineIndex]
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 跳过空行
                if trimmedLine.isEmpty {
                    currentPosition += line.count + 1 // +1 for newline
                    continue
                }
                
                // 使用快速章节检测
                let isChapterTitle = isChapterHeadingFast(trimmedLine, regexes: precompiledRegexes)
                
                if isChapterTitle {
                    // 验证章节标题的有效性
                    if isValidChapterTitle(trimmedLine, position: currentPosition, textLength: text.count) {
                        chapterCandidates.append((lineIndex, trimmedLine, currentPosition))
                        print("【章节识别】找到章节候选: [\(trimmedLine)] 位置: \(currentPosition)")
                    } else {
                        print("【章节识别】忽略无效章节标题: [\(trimmedLine)] 位置: \(currentPosition)")
                    }
                }
                
                // 为所有行创建段落（无论是否为章节标题）
                let language = detectLanguageSimple(trimmedLine)
                let startPos = Double(currentPosition) / Double(text.count)
                let endPos = Double(currentPosition + trimmedLine.count) / Double(text.count)
                
                paragraphs.append(TextParagraph(
                    text: trimmedLine,
                    startPosition: startPos,
                    endPosition: endPos,
                    language: language,
                    startIndex: currentPosition,
                    endIndex: currentPosition + trimmedLine.count,
                    isChapterTitle: isChapterTitle
                ))
                
                // 如果是章节标题，记录详细信息
                if isChapterTitle {
                    chapterStartIndices.append((title: trimmedLine, index: currentPosition, paragraphIndex: paragraphs.count - 1))
                }
                
                // 更新当前位置
                currentPosition += line.count + 1 // +1 for newline
            }
            
            // 定期打印进度
            if batchIndex % 10 == 0 || batchIndex == batchCount - 1 {
                let progress = Double(endLineIndex) / Double(lines.count) * 100
                print("【章节识别】处理进度: \(String(format: "%.1f", progress))%, 已找到\(chapterCandidates.count)个章节候选")
            }
        }
        
        // 过滤并确认最终章节 - 应用额外验证规则
        let filteredChapters = validateAndFilterChapters(chapterStartIndices, text: text)
        
        print("【章节识别】初步识别到\(chapterStartIndices.count)个章节候选，经过过滤后确认\(filteredChapters.count)个有效章节")
        
        // 构建章节结构
        var chapters: [Chapter] = []
        
        // 如果找到章节标题并且没有强制使用自动分段
        if !filteredChapters.isEmpty && !forceAutoSegmentation {
            print("【章节识别】使用识别到的\(filteredChapters.count)个章节标题创建章节")
            for i in 0..<filteredChapters.count {
                let chapterTitle = filteredChapters[i].title
                let chapterStartIndex = filteredChapters[i].index
                
                // 确定章节结束索引
                let chapterEndIndex: Int
                if i < filteredChapters.count - 1 {
                    chapterEndIndex = filteredChapters[i+1].index
                } else {
                    chapterEndIndex = text.count
                }
                
                // 计算章节位置
                let startPosition = Double(chapterStartIndex) / Double(text.count)
                let endPosition = Double(chapterEndIndex) / Double(text.count)
                
                // 创建章节
                let chapter = Chapter(
                    title: chapterTitle,
                    startPosition: startPosition,
                    endPosition: endPosition,
                    startIndex: chapterStartIndex,
                    endIndex: chapterEndIndex,
                    subchapters: nil
                )
                
                // 添加验证步骤
                if validateChapter(chapter, fullText: text) {
                    chapters.append(chapter)
                    
                    // 只打印前10个和后10个章节以避免日志过多
                    if i < 10 || i >= filteredChapters.count - 10 {
                        print("【章节识别】添加章节：\(chapterTitle)，位置：\(startPosition)-\(endPosition)，内容长度：\(chapter.endIndex - chapter.startIndex)字符")
                    } else if i == 10 {
                        print("【章节识别】... 省略中间\(filteredChapters.count - 20)个章节 ...")
                    }
                } else {
                    print("【章节识别】章节「\(chapterTitle)」验证失败，已跳过")
                }
            }
        } else {
            // 自动分段逻辑保持不变
            let defaultChapterSize = 1000 // 每章默认1000字符
            let chapterCount = max(1, text.count / defaultChapterSize)
            
            print("【章节识别】未找到有效章节或强制自动分段，将按每\(defaultChapterSize)字符自动分段为\(chapterCount)章")
            
            for i in 0..<chapterCount {
                let startIndex = i * defaultChapterSize
                let endIndex = min((i + 1) * defaultChapterSize, text.count)
                
                let startPosition = Double(startIndex) / Double(text.count)
                let endPosition = Double(endIndex) / Double(text.count)
                
                let title = "第\(i + 1)部分"
                
                chapters.append(Chapter(
                    title: title,
                    startPosition: startPosition,
                    endPosition: endPosition,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    subchapters: nil
                ))
                
                if i < 5 || i >= chapterCount - 5 {
                    print("【章节识别】添加自动分段章节：\(title)，位置：\(startPosition)-\(endPosition)")
                } else if i == 5 {
                    print("【章节识别】... 省略中间自动分段章节 ...")
                }
            }
        }
        
        // 打印性能统计
        let endTime = CFAbsoluteTimeGetCurrent()
        let timeElapsed = endTime - startTime
        print("【章节识别】章节分析完成，耗时：\(String(format: "%.2f", timeElapsed))秒，识别出\(chapters.count)个章节")
        
        return (paragraphs, chapters)
    }
    
    // 增加一个验证和过滤章节候选项的函数
    private static func validateAndFilterChapters(_ candidates: [(title: String, index: Int, paragraphIndex: Int)], text: String) -> [(title: String, index: Int, paragraphIndex: Int)] {
        guard !candidates.isEmpty else { return [] }
        
        // 章节候选项过多时可能是误识别，进行额外筛选
        if candidates.count > 300 {
            print("【章节验证】候选章节数量过多(\(candidates.count))，可能存在误识别，应用额外筛选规则")
            
            // 检查章节之间的平均间隔
            var totalDistance = 0
            for i in 0..<candidates.count-1 {
                totalDistance += candidates[i+1].index - candidates[i].index
            }
            let averageDistance = totalDistance / (candidates.count - 1)
            
            // 如果平均间隔太小（小于200字符），可能是误识别
            if averageDistance < 200 {
                print("【章节验证】平均章节间隔(\(averageDistance)字符)过小，应用更严格的过滤规则")
                
                // 只保留格式最规范的章节标题
                return candidates.filter { candidate in
                    let trimmedTitle = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 只保留最典型的章节格式
                    return trimmedTitle.hasPrefix("第") && 
                           trimmedTitle.contains("章") && 
                           trimmedTitle.count < 15 ||
                           trimmedTitle.lowercased().hasPrefix("chapter") && 
                           trimmedTitle.count < 12
                }
            }
        }
        
        return candidates
    }
    
    // 优化的章节标题判断函数
    private static func isChapterHeadingFast(_ line: String, regexes: [NSRegularExpression]) -> Bool {
        // 如果行太长可能不是章节标题
        if line.count > 30 {
            return false
        }
        
        // 快速检查：如果行不包含关键词，大多数情况下不是章节标题
        let lowerLine = line.lowercased()
        if !line.contains("章") && !lowerLine.contains("chapter") {
            return false
        }
        
        // 使用预编译的正则表达式检查
        let range = NSRange(location: 0, length: line.utf16.count)
        for regex in regexes {
            if regex.firstMatch(in: line, options: [], range: range) != nil {
                return true
            }
        }
        
        // 补充检查：检查简单的章节模式
        return (line.hasPrefix("第") && line.contains("章") && line.count < 20) ||
               (lowerLine.hasPrefix("chapter") && line.count < 15)
    }
    
    // 简化的语言检测
    private static func detectLanguageSimple(_ text: String) -> String {
        // 检查前10个字符，快速判断主要语言
        let sample = String(text.prefix(min(10, text.count)))
        let chineseChars = sample.filter { char in 
            let scalar = char.unicodeScalars.first!
            return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }.count
        
        return chineseChars > 2 ? "zh-CN" : "en-US"
    }
    
    // 修改isChapterHeading方法，使章节识别更严格
    private static func isChapterHeading(_ line: String) -> Bool {
        // 修改：使用更严格的直接匹配模式
        let commonTitles = ["第一章", "第1章", "第 1 章", "第二章", "第2章", "第 2 章", 
                           "第三章", "第3章", "第 3 章", "序章", "引子", "前言"]
                           
        // 先检查完全匹配
        if commonTitles.contains(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
            print("【章节识别】完全匹配到章节标题: \(line)")
            return true
        }
        
        // 精确的章节标题模式
        // 中文章节模式 - 使用更严格的匹配
        let strictPatterns = [
            "^\\s*第[一二三四五六七八九十百千万零〇\\d]+章\\s*$",
            "^\\s*第[一二三四五六七八九十百千万零〇\\d]+章[：:].+$",
            "^\\s*第\\s*[一二三四五六七八九十百千万零〇\\d]+\\s*章\\s*$",
            "^\\s*第\\s*[一二三四五六七八九十百千万零〇\\d]+\\s*章[：:].+$",
            "^\\s*第\\s*\\d+\\s*章\\s*$",
            "^\\s*第\\s*\\d+\\s*章[：:].+$",
            "^\\s*[Cc]hapter\\s+\\d+\\s*$",
            "^\\s*[Cc]hapter\\s+\\d+[：:].+$"
        ]
        
        // 使用严格的模式匹配
        for pattern in strictPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: line.utf16.count)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    print("【章节识别】严格匹配到章节标题: \(line)")
                    return true
                }
            }
        }
        
        // 额外检查非常明确的模式
        if line.count < 20 && line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("第") && line.contains("章") {
            // 检查是否只包含章节标题的关键特征，排除普通文本
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let components = trimmedLine.components(separatedBy: CharacterSet(charactersIn: "章：: "))
            if components.count <= 3 {
                print("【章节识别】关键特征匹配到章节标题: \(line)")
                return true
            }
        }
        
        // 其他所有宽松匹配都移除
        return false
    }
    
    // 章节标题的启发式识别
    private static func isLikelyChapterTitle(_ line: String) -> Bool {
        // 如果是全大写，且不太长，可能是章节标题
        if line.uppercased() == line && line.count < 50 && line.count > 3 {
            return true
        }
        
        // 如果是短行文本（通常章节标题较短）
        if line.count < 20 {
            // 如果以数字开头，很可能是章节标题
            if let first = line.first, first.isNumber {
                return true
            }
            
            // 以"第"开头的短文本几乎肯定是章节标题
            if line.hasPrefix("第") {
                return true
            }
        }
        
        // 如果包含特定关键词且较短，可能是章节标题
        let keywords = ["章", "节", "回", "卷", "部", "篇", "第", "Chapter", "Part"]
        for keyword in keywords {
            if line.contains(keyword) && line.count < 30 {
                return true
            }
        }
        
        return false
    }
    
    // 检测文本语言
    private static func detectLanguage(_ text: String) -> String {
        // 计算中文字符和英文字符的比例
        let chineseCharCount = text.filter { char in
            let isChineseChar = (char >= "\u{4E00}" && char <= "\u{9FFF}") || 
                               (char >= "\u{3400}" && char <= "\u{4DBF}") || 
                               (char >= "\u{20000}" && char <= "\u{2A6DF}")
            return isChineseChar
        }.count
        
        let englishCharCount = text.filter { char in
            return (char >= "a" && char <= "z") || 
                   (char >= "A" && char <= "Z")
        }.count
        
        // 根据比例选择语言
        if Double(chineseCharCount) / Double(max(1, text.count)) > 0.15 {
            return "zh-CN"
        } else if Double(englishCharCount) / Double(max(1, text.count)) > 0.4 {
            return "en-US"
        } else {
            // 使用自然语言处理进一步检测
            if #available(iOS 12.0, *) {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                if let language = recognizer.dominantLanguage?.rawValue {
                    if language.hasPrefix("zh") {
                        return "zh-CN"
                    } else if language.hasPrefix("en") {
                        return "en-US"
                    }
                }
            }
            
            // 默认中文
            return "zh-CN"
        }
    }
    
    private static func validateChapter(_ chapter: Chapter, fullText: String) -> Bool {
        // 检查章节内容是否为空
        if chapter.startIndex >= chapter.endIndex {
            print("【章节验证】章节「\(chapter.title)」内容为空，已过滤")
            return false
        }
        
        // 检查章节内容长度是否过短
        let contentLength = chapter.endIndex - chapter.startIndex
        if contentLength < 10 { // 少于10个字符的章节视为无效
            print("【章节验证】章节「\(chapter.title)」内容过短（仅\(contentLength)字符），已过滤")
            return false
        }
        
        // 提取章节内容并检查是否全为空白字符
        let chapterContent = chapter.extractContent(from: fullText)
        let trimmedContent = chapterContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty {
            print("【章节验证】章节「\(chapter.title)」内容全为空白字符，已过滤")
            return false
        }
        
        return true
    }
    
    // 修改章节标题识别逻辑，增加更严格的过滤条件
    private static func isValidChapterTitle(_ title: String, position: Int, textLength: Int) -> Bool {
        // 已有的标题检查逻辑
        let titleTrimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 忽略明显是目录或空白的情况
        if titleTrimmed.isEmpty || titleTrimmed.contains("目录") || titleTrimmed.contains("前言") {
            return false
        }
        
        // 特别过滤掉前面的 Chapter_1 到 Chapter_6 这样的标记
        if titleTrimmed.hasPrefix("Chapter_") {
            // 这些通常是文件格式化标记，不是真正的章节
            print("【章节识别】过滤掉格式化章节标记: \(titleTrimmed)")
            return false
        }
        
        // 在文件头部位置(前5%)的标题需要更严格的校验
        let isInFileHeader = position < (textLength / 20) // 文本前5%
        if isInFileHeader {
            // 在文件头部，我们只接受非常明确的章节标题
            let isDefiniteChapter = titleTrimmed.contains("第") && 
                                   (titleTrimmed.contains("章") || 
                                    titleTrimmed.contains("节") ||
                                    titleTrimmed.contains("集"))
            
            // 对于文件头部的内容，如果不是明确的章节标题，直接过滤掉
            if !isDefiniteChapter {
                print("【章节识别】文件头部发现疑似无效章节标题: \(titleTrimmed)，需要进一步验证内容")
                return false
            }
        }
        
        return true
    }
} 