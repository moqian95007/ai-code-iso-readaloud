import Foundation

class ChapterManager: ObservableObject {
    @Published var chapters: [Chapter] = []
    @Published var isProcessing: Bool = true // 默认为true，避免初始化后的空窗期
    @Published var processingTimeInSeconds: Double = 0
    @Published var progressPercentage: Double = 0
    private let saveKey = "documentChapters_"
    private let batchSize = 5000 // 一次处理的字符数
    
    // 初始化方法
    init() {
        print("ChapterManager 初始化 - 设置加载状态")
        // 默认为不处理状态
        self.isProcessing = false
        self.progressPercentage = 0
    }
    
    // 识别文档的章节
    func identifyChapters(for document: Document) -> [Chapter] {
        print("ChapterManager.identifyChapters 开始处理文档: \(document.title), 内容长度: \(document.content.count)")
        
        // 检查是否已存在该文档的章节划分 - 快速路径
        if let existingChapters = loadChapters(for: document.id), !existingChapters.isEmpty {
            print("已存在章节划分，快速加载已有章节数据: \(existingChapters.count)个章节")
            
            DispatchQueue.main.async {
                self.chapters = existingChapters
                self.isProcessing = false
                self.progressPercentage = 100
            }
            
            return existingChapters
        }
        
        // 如果没有缓存，设置处理状态
        DispatchQueue.main.async {
            self.isProcessing = true
            self.progressPercentage = 0
        }
        
        // 开始计时
        let startTime = Date()
        
        // 检查文档内容是否为空
        if document.content.isEmpty {
            print("文档内容为空，创建空章节")
            let emptyChapter = createDefaultChapter(content: "（文档内容为空）", documentId: document.id)
            
            DispatchQueue.main.async {
                self.chapters = [emptyChapter]
                self.isProcessing = false
                self.progressPercentage = 100
                self.processingTimeInSeconds = 0
            }
            
            return [emptyChapter]
        }
        
        print("开始识别文档章节 - 解析内容中...")
        let content = document.content
        
        // 设置超时计时器
        var isTimeout = false
        let timeoutDuration: TimeInterval = 30.0 // 30秒超时
        let timeoutWorkItem = DispatchWorkItem {
            isTimeout = true
            print("章节处理超时！创建默认章节")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutDuration, execute: timeoutWorkItem)
        
        // 章节识别正则表达式 - 优化正则表达式以减少匹配次数
        let patterns = [
            "第[0-9零一二三四五六七八九十百千万]+[章回节集卷篇].*?[\n\r]", // 中文章节格式
            "Chapter\\s*[0-9]+.*?[\n\r]", // 英文章节格式
            "[0-9]+\\..*?[\n\r]", // 数字编号格式
            "[0-9]+、.*?[\n\r]" // 数字顿号格式
        ]
        
        // 针对大文件优化方案
        let isLargeFile = content.count > 1000000 // 超过1MB的文档
        let chunkSize = isLargeFile ? 100000 : content.count // 大文件分块处理，每次10万字符
        
        // 优化：合并正则表达式
        let combinedPattern = patterns.joined(separator: "|")
        var regex: NSRegularExpression?
        
        print("编译正则表达式...")
        do {
            regex = try NSRegularExpression(pattern: combinedPattern, options: [])
            print("正则表达式编译成功")
        } catch {
            print("正则表达式编译错误: \(error.localizedDescription)")
            timeoutWorkItem.cancel()
            
            // 创建默认章节
            let defaultChapter = createDefaultChapter(content: content, documentId: document.id)
            
            // 在主线程更新UI状态
            DispatchQueue.main.async {
                self.chapters = [defaultChapter]
                self.isProcessing = false
                self.progressPercentage = 100
                
                // 计算处理时间
                let endTime = Date()
                self.processingTimeInSeconds = endTime.timeIntervalSince(startTime)
                print("章节处理时间(错误情况): \(self.processingTimeInSeconds)秒")
                print("UI状态已更新: isProcessing = false (正则错误)")
            }
            
            return [defaultChapter]
        }
        
        // 存储找到的所有章节位置
        var chapterPositions: [(title: String, start: Int)] = []
        
        // 使用批处理方式处理大型文档
        let totalLength = content.count
        var processedLength = 0
        
        print("开始匹配章节标题...")
        // 使用正则表达式查找章节标题
        if let regex = regex {
            if isLargeFile {
                // 分块处理大文件
                print("文件较大，进行分块处理...")
                var offset = 0
                
                while offset < content.count && !isTimeout {
                    let endOffset = min(offset + chunkSize, content.count)
                    var chunkStart = content.index(content.startIndex, offsetBy: offset)
                    let chunkEnd = content.index(content.startIndex, offsetBy: endOffset)
                    
                    // 确保不会在单词中间切断
                    if offset > 0 {
                        while chunkStart < chunkEnd && !CharacterSet.newlines.contains(content[chunkStart].unicodeScalars.first!) {
                            chunkStart = content.index(after: chunkStart)
                        }
                    }
                    
                    let chunk = content[chunkStart..<chunkEnd]
                    let nsRange = NSRange(chunk.startIndex..<chunk.endIndex, in: chunk)
                    let matches = regex.matches(in: String(chunk), options: [], range: nsRange)
                    
                    for (index, match) in matches.enumerated() {
                        if isTimeout { break }
                        
                        if let range = Range(match.range, in: chunk) {
                            let title = String(chunk[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let startIndex = content.distance(from: content.startIndex, to: chunk.startIndex) + chunk.distance(from: chunk.startIndex, to: range.lowerBound)
                            chapterPositions.append((title: title, start: startIndex))
                        }
                        
                        // 更新进度
                        let blockProgress = Double(offset + matches.count) / Double(totalLength) * 100
                        let progress = min(50.0, blockProgress) // 正则处理占进度的50%
                        if index % 10 == 0 || index == matches.count - 1 {
                            DispatchQueue.main.async {
                                self.progressPercentage = progress
                                if index % 20 == 0 {
                                    print("分块正则匹配进度: \(Int(progress))% (处理了\(offset)/\(totalLength)字符)")
                                }
                            }
                        }
                    }
                    
                    offset = endOffset
                    // 更新处理进度
                    processedLength = offset
                    let progress = min(50.0, Double(processedLength) / Double(totalLength) * 50.0)
                    DispatchQueue.main.async {
                        self.progressPercentage = progress
                        print("文件处理进度: \(Int(progress))% (处理了\(processedLength)/\(totalLength)字符)")
                    }
                }
            } else {
                // 小文件一次性处理
                print("文件较小，一次性处理...")
                let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
                print("开始执行正则匹配...")
                let matches = regex.matches(in: content, options: [], range: nsRange)
                print("正则匹配完成，找到\(matches.count)个潜在章节")
                
                for (index, match) in matches.enumerated() {
                    if isTimeout { break }
                    
                    if let range = Range(match.range, in: content) {
                        let title = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let startIndex = content.distance(from: content.startIndex, to: range.lowerBound)
                        chapterPositions.append((title: title, start: startIndex))
                    }
                    
                    // 更新进度
                    let progress = Double(index) / Double(max(1, matches.count)) * 50 // 正则处理占进度的50%
                    if index % 10 == 0 || index == matches.count - 1 { // 减少更新频率
                        DispatchQueue.main.async {
                            self.progressPercentage = progress
                            if index % 50 == 0 { // 减少日志输出频率
                                print("正则匹配进度: \(Int(progress))% (处理了\(index)/\(matches.count)个匹配)")
                            }
                        }
                    }
                }
            }
        }
        
        // 检查是否超时
        if isTimeout {
            print("处理超时，创建默认章节")
            timeoutWorkItem.cancel()
            
            let defaultChapter = createDefaultChapter(content: content, documentId: document.id)
            
            DispatchQueue.main.async {
                self.chapters = [defaultChapter]
                self.isProcessing = false
                self.progressPercentage = 100
                
                let endTime = Date()
                self.processingTimeInSeconds = endTime.timeIntervalSince(startTime)
                print("章节处理时间(超时情况): \(self.processingTimeInSeconds)秒")
                print("UI状态已更新: isProcessing = false (超时)")
            }
            
            saveChapters([defaultChapter], for: document.id)
            return [defaultChapter]
        } else {
            // 如果没有超时，取消超时任务
            timeoutWorkItem.cancel()
        }
        
        print("排序章节位置...")
        // 排序章节位置（按在文本中的出现顺序）
        chapterPositions.sort(by: { $0.start < $1.start })
        
        // 如果没有识别到章节，创建一个默认章节
        if chapterPositions.isEmpty {
            print("没有识别到章节，创建默认章节")
            let defaultChapter = createDefaultChapter(content: content, documentId: document.id)
            
            // 在主线程更新UI状态
            DispatchQueue.main.async {
                self.chapters = [defaultChapter]
                self.isProcessing = false
                self.progressPercentage = 100
                
                // 计算处理时间
                let endTime = Date()
                self.processingTimeInSeconds = endTime.timeIntervalSince(startTime)
                print("章节处理时间(默认章节): \(self.processingTimeInSeconds)秒")
                print("UI状态已更新: isProcessing = false (默认章节)")
            }
            
            saveChapters([defaultChapter], for: document.id)
            return [defaultChapter]
        }
        
        print("开始创建\(chapterPositions.count)个章节...")
        // 创建章节 - 使用更高效的方法
        var resultChapters: [Chapter] = []
        resultChapters.reserveCapacity(chapterPositions.count + 1) // 预分配内存，+1是为了可能的前言章节
        
        // 检查第一个章节的起始位置，如果不是从头开始，则创建一个前言章节
        if chapterPositions.first!.start > 0 {
            let prefaceContent = String(content[content.startIndex..<content.index(content.startIndex, offsetBy: chapterPositions.first!.start)])
            
            // 确保前言内容不为空
            if !prefaceContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("发现前言内容，长度: \(prefaceContent.count)字符")
                
                // 创建前言章节
                let prefaceChapter = Chapter(
                    id: UUID(),
                    title: "前言",
                    content: prefaceContent,
                    startIndex: 0,
                    endIndex: chapterPositions.first!.start,
                    documentId: document.id,
                    listId: document.id
                )
                
                // 添加前言章节到结果列表
                resultChapters.append(prefaceChapter)
                print("创建前言章节: ID=\(prefaceChapter.id.uuidString), 内容长度=\(prefaceContent.count)")
            } else {
                print("第一章前的内容仅包含空白字符，跳过前言章节创建")
            }
        } else {
            print("第一章从文档开头开始，不需要创建前言章节")
        }
        
        // 使用批处理方式创建章节，减轻UI线程负担
        let batchSize = min(10, chapterPositions.count) // 每次处理10个章节
        var currentBatch = 0
        
        while currentBatch * batchSize < chapterPositions.count && !isTimeout {
            let startIndex = currentBatch * batchSize
            let endIndex = min((currentBatch + 1) * batchSize, chapterPositions.count)
            
            for i in startIndex..<endIndex {
                if isTimeout { break }
                
                let title = chapterPositions[i].title
                let chapterStartIndex = chapterPositions[i].start
                let chapterEndIndex = i < chapterPositions.count - 1 ? chapterPositions[i + 1].start : content.count
                
                // 提取章节内容 - 优化字符串操作
                let startStringIndex = content.index(content.startIndex, offsetBy: chapterStartIndex)
                let endStringIndex = content.index(content.startIndex, offsetBy: min(chapterEndIndex, content.count))
                let chapterContent = String(content[startStringIndex..<endStringIndex])
                
                // 为每个章节创建唯一的ID
                let chapter = Chapter(
                    id: UUID(), // 显式创建新的UUID，确保每个章节ID唯一
                    title: title,
                    content: chapterContent,
                    startIndex: chapterStartIndex,
                    endIndex: chapterEndIndex,
                    documentId: document.id,
                    listId: document.id // 设置章节所属列表ID为文档ID
                )
                
                // 添加章节到结果列表
                resultChapters.append(chapter)
                
                // 添加日志记录章节ID
                if i % 10 == 0 || i == endIndex - 1 {
                    print("创建章节: ID=\(chapter.id.uuidString), 标题=\(chapter.title)")
                }
                
                // 更新进度 (章节创建占进度的50%)
                let progress = 50.0 + (Double(i) / Double(max(1, chapterPositions.count - 1)) * 50.0)
                if i % 5 == 0 || i == chapterPositions.count - 1 { // 减少更新频率
                    DispatchQueue.main.async {
                        self.progressPercentage = progress
                        if i % 10 == 0 { // 减少日志输出频率
                            print("章节创建进度: \(Int(progress))% (创建了\(i+1)/\(chapterPositions.count)个章节)")
                        }
                    }
                }
            }
            
            currentBatch += 1
            
            // 每处理完一批，就检查一下是否需要更新UI
            if currentBatch % 2 == 0 {
                // 让主线程有机会更新UI
                let progress = 50.0 + (Double(min(endIndex, chapterPositions.count)) / Double(chapterPositions.count) * 50.0)
                DispatchQueue.main.async {
                    self.progressPercentage = progress
                    print("批处理进度: \(Int(progress))% (完成批次: \(currentBatch))")
                }
                
                // 检查是否超时
                if isTimeout {
                    print("章节创建过程中超时")
                    break
                }
            }
        }
        
        // 检查是否在章节创建过程中超时
        if isTimeout && resultChapters.isEmpty {
            let defaultChapter = createDefaultChapter(content: content, documentId: document.id)
            resultChapters = [defaultChapter]
            print("章节创建超时，使用默认章节")
        }
        
        print("识别出\(resultChapters.count)个章节")
        
        // 保存章节信息
        print("开始保存章节...")
        saveChapters(resultChapters, for: document.id)
        
        // 在主线程更新UI状态
        DispatchQueue.main.async {
            self.chapters = resultChapters
            self.isProcessing = false
            self.progressPercentage = 100
            
            // 计算处理时间
            let endTime = Date()
            self.processingTimeInSeconds = endTime.timeIntervalSince(startTime)
            print("章节处理时间: \(self.processingTimeInSeconds)秒")
            print("UI状态已更新: isProcessing = false (处理完成)")
        }
        
        return resultChapters
    }
    
    // 创建一个默认章节
    private func createDefaultChapter(content: String, documentId: UUID) -> Chapter {
        return Chapter(
            id: UUID(), // 明确指定唯一ID
            title: "完整内容",
            content: content,
            startIndex: 0,
            endIndex: content.count,
            documentId: documentId,
            listId: documentId // 设置章节所属列表ID为文档ID
        )
    }
    
    // 保存文档的章节划分
    private func saveChapters(_ chapters: [Chapter], for documentId: UUID) {
        // 设置每个章节的documentId和listId，并确保ID唯一
        var updatedChapters: [Chapter] = []
        
        for chapter in chapters {
            // 确保每个章节有唯一ID和正确的引用
            let updatedChapter = ensureChapterProperties(chapter, documentId: documentId)
            updatedChapters.append(updatedChapter)
        }
        
        // 保存章节数据
        if let encoded = try? JSONEncoder().encode(updatedChapters) {
            UserDefaults.standard.set(encoded, forKey: saveKey + documentId.uuidString)
            print("保存了\(updatedChapters.count)个章节")
            
            // 更新文档的章节ID列表
            let chapterIds = updatedChapters.map { $0.id }
            
            // 更新文档库中的章节ID
            let documentLibrary = DocumentLibraryManager.shared
            if let document = documentLibrary.findDocument(by: documentId) {
                var updatedDocument = document
                updatedDocument.chapterIds = chapterIds
                documentLibrary.updateDocument(updatedDocument)
                print("更新了文档的章节ID列表: \(chapterIds.count)个章节")
            }
            
            // 确保将章节添加到对应的ArticleList中
            for chapter in updatedChapters {
                ArticleListManager.shared.addArticleToList(articleId: chapter.id, listId: documentId)
            }
        } else {
            print("章节编码失败")
        }
    }
    
    // 加载文档的章节划分
    private func loadChapters(for documentId: UUID) -> [Chapter]? {
        if let data = UserDefaults.standard.data(forKey: saveKey + documentId.uuidString) {
            if let decoded = try? JSONDecoder().decode([Chapter].self, from: data) {
                print("加载了\(decoded.count)个章节")
                
                // 检查是否有重复ID
                let ids = decoded.map { $0.id }
                let uniqueIds = Set(ids)
                if ids.count != uniqueIds.count {
                    print("警告: 加载的章节中存在\(ids.count - uniqueIds.count)个重复ID!")
                    
                    // 创建新的章节数组，确保每个章节有唯一ID
                    var fixedChapters: [Chapter] = []
                    var seenIds = Set<UUID>()
                    
                    for chapter in decoded {
                        var updatedChapter = chapter
                        if seenIds.contains(chapter.id) {
                            print("修复重复ID: \(chapter.id.uuidString) -> 创建新ID")
                            updatedChapter.id = UUID()
                        }
                        seenIds.insert(updatedChapter.id)
                        fixedChapters.append(updatedChapter)
                    }
                    
                    // 保存修复后的章节
                    print("保存修复后的\(fixedChapters.count)个章节")
                    saveChapters(fixedChapters, for: documentId)
                    return fixedChapters
                }
                
                // 正常返回加载的章节
                return decoded
            }
        }
        return nil
    }
    
    // 清除文档的章节划分
    func clearChapters(for documentId: UUID) {
        UserDefaults.standard.removeObject(forKey: saveKey + documentId.uuidString)
        if chapters.first?.documentId == documentId {
            chapters.removeAll()
        }
        print("清除了文档的章节划分")
    }
    
    // 保存当前识别出的章节
    func saveChapters(for documentId: UUID) {
        print("保存当前\(chapters.count)个章节到文档ID: \(documentId)")
        saveChapters(chapters, for: documentId)
    }
    
    // 确保章节具有所有必需的属性
    private func ensureChapterProperties(_ chapter: Chapter, documentId: UUID) -> Chapter {
        var updatedChapter = chapter
        
        // 保留原始ID，不要覆盖
        // 只有在必要时才分配新ID
        if updatedChapter.id == UUID() || updatedChapter.id == UUID.init() {
            print("章节ID为默认值，分配新ID")
            updatedChapter.id = UUID()
        }
        
        // 记录章节ID，以便调试
        print("保存章节 - 保留原始ID: \(updatedChapter.id.uuidString)")
        
        // 设置文档ID和列表ID
        updatedChapter.documentId = documentId
        updatedChapter.listId = documentId
        
        return updatedChapter
    }
} 