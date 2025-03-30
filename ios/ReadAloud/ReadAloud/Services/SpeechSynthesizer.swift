import Foundation
import AVFoundation
import Combine

class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isPlaying = false
    @Published var currentPosition: Double = 0.0
    @Published var currentText: String = ""
    @Published var currentReadingCharacterIndex: Int = 0
    @Published var currentReadingCharacterCount: Int = 0
    
    private var synthesizer = AVSpeechSynthesizer()
    public var fullText: String = ""
    private var utterance: AVSpeechUtterance?
    private var document: Document?
    private var documentViewModel: DocumentsViewModel?
    
    // 语音选项
    var voice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "zh-CN")
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var volume: Float = 1.0
    var pitchMultiplier: Float = 1.0
    
    // 章节相关属性
    private var chapters: [Chapter] = []
    private var paragraphs: [TextParagraph] = []
    private var currentChapterIndex: Int = 0
    
    // 添加章节内部进度相关属性
    private var chapterInternalProgress: Double = 0.0
    
    // 添加缓存机制
    private var chaptersCache: [Chapter] = []
    private var chaptersCacheValid: Bool = false
    private var lastChapterRequestTime: Date = Date.distantPast
    
    // 添加在getCurrentChapterIndex方法附近
    private var cachedChapterIndex: Int = 0
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            // 配置音频会话
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("音频会话配置成功")
        } catch {
            print("音频会话配置失败: \(error.localizedDescription)")
        }
    }
    
    func loadDocument(_ document: Document, viewModel: DocumentsViewModel, onProgress: ((Double, String) -> Void)? = nil) {
        self.document = document
        self.documentViewModel = viewModel
        
        // 报告初始进度
        onProgress?(0.0, "准备加载文档...")
        
        // 异步处理
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in  // 提高队列优先级
            guard let self = self else { return }
            
            do {
                // 报告进度
                onProgress?(0.1, "正在提取文本...")
                
                let extractedText = try TextExtractor.extractText(from: document)
                
                // 报告进度
                onProgress?(0.3, "文本提取完成，开始分析章节...")
                
                // 使用异步任务处理章节分析
                let segmentationTask = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    
                    print("【章节解析】准备开始章节分割分析，全文长度：\(extractedText.count)字符")
                    
                    // 章节分割处理
                    let segmentationResult = ChapterSegmenter.splitTextIntoParagraphs(extractedText, forceAutoSegmentation: false)
                    self.paragraphs = segmentationResult.paragraphs
                    
                    // 过滤掉文件开头的无效章节（通常是目录或格式化内容）
                    let filteredChapters = segmentationResult.chapters.filter { chapter in
                        // 内容长度过短的章节（如 Chapter_1 到 Chapter_6）被认为是无效章节
                        let contentLength = chapter.endIndex - chapter.startIndex
                        let isValidContent = contentLength > 100 // 内容至少要有100个字符
                        
                        // 前7个章节都是 Chapter_X 格式，而且内容很短，应该过滤掉
                        let isFormatPrefix = chapter.title.hasPrefix("Chapter_") && contentLength < 100
                        
                        if !isValidContent || isFormatPrefix {
                            print("【章节过滤】过滤无效章节: \(chapter.title)，内容长度: \(contentLength)字符")
                            return false
                        }
                        return true
                    }
                    
                    self.chapters = filteredChapters
                    
                    // 报告进度
                    DispatchQueue.main.async {
                        onProgress?(0.8, "章节分析完成，准备更新UI...")
                    }
                    
                    print("【章节解析】完成章节分割，共识别\(self.chapters.count)个有效章节")
                    
                    // 输出章节验证信息
                    if !self.chapters.isEmpty {
                        for i in 0..<min(3, self.chapters.count) {
                            print("【章节解析】章节\(i+1)标题：\(self.chapters[i].title)")
                        }
                    } else {
                        print("【章节解析】警告：未识别出任何章节")
                    }
                    
                    // 设置full text并更新UI
                    DispatchQueue.main.async {
                        self.fullText = extractedText
                        
                        // 重置朗读进度
                        self.currentPosition = document.progress
                        
                        // 确保章节索引从第一个有效章节开始
                        self.currentChapterIndex = 0
                        self.cachedChapterIndex = 0
                        
                        // 更新当前显示的文本段落
                        self.updateCurrentTextDisplay()
                        
                        // 额外添加：如果文本没有正确显示，再次尝试更新
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if self.currentText.isEmpty && !self.fullText.isEmpty {
                                print("【文本加载】检测到文本可能未正确显示，尝试再次更新")
                                
                                // 尝试从章节中提取内容
                                if !self.chapters.isEmpty {
                                    let chapter = self.chapters[0]
                                    if chapter.startIndex < self.fullText.count && chapter.endIndex <= self.fullText.count {
                                        let startIndex = self.fullText.index(self.fullText.startIndex, offsetBy: chapter.startIndex)
                                        let endIndex = self.fullText.index(self.fullText.startIndex, offsetBy: chapter.endIndex)
                                        self.currentText = String(self.fullText[startIndex..<endIndex])
                                        print("【文本加载】成功重新加载第一章内容，长度: \(self.currentText.count)字符")
                                    }
                                }
                                
                                // 强制UI更新
                                self.objectWillChange.send()
                            }
                        }
                        
                        // 报告完成
                        onProgress?(1.0, "加载完成")
                        
                        // 触发UI更新
                        self.objectWillChange.send()
                        
                        print("【UI更新】章节数据已更新，UI应刷新显示\(self.chapters.count)个章节")
                        print("【章节状态】当前章节索引: \(self.currentChapterIndex)")
                        
                        // 额外添加：直接跳转到第一章确保内容显示
                        if !self.chapters.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                print("【初始化】强制跳转到第一章以确保内容显示")
                                // 使用暂存变量避免循环调用
                                let originalPosition = self.currentPosition
                                
                                // 重置位置
                                self.jumpToChapter(0)
                                
                                // 如果有保存的进度，恢复到正确位置
                                if originalPosition > 0.01 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        print("【初始化】恢复到保存的阅读位置: \(originalPosition)")
                                        self.currentPosition = originalPosition
                                        self.updateCurrentTextDisplay()
                                    }
                                }
                            }
                        }
                    }
                }
                
                // 启动章节分析任务
                DispatchQueue.global(qos: .userInitiated).async(execute: segmentationTask)
                
            } catch {
                DispatchQueue.main.async {
                    self.currentText = "文本提取失败: \(error.localizedDescription)"
                    onProgress?(1.0, "加载失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func updateCurrentTextDisplay() {
        // 根据当前进度定位到文本相应位置
        if !fullText.isEmpty {
            // 检查当前位置对应哪一章
            let chapterIndex = getCurrentChapterIndex()
            if chapterIndex >= 0 && chapterIndex < chapters.count {
                let chapter = chapters[chapterIndex]
                
                // 提取并显示整个章节内容，同时检查内容是否为空
                if chapter.startIndex < fullText.count && chapter.endIndex <= fullText.count && chapter.startIndex < chapter.endIndex {
                    let startIndex = fullText.index(fullText.startIndex, offsetBy: chapter.startIndex)
                    let endIndex = fullText.index(fullText.startIndex, offsetBy: chapter.endIndex)
                    let chapterContent = String(fullText[startIndex..<endIndex])
                    
                    // 检查章节内容是否为空白
                    let trimmedContent = chapterContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedContent.isEmpty {
                        currentText = chapterContent
                        print("【文本更新】显示整章内容，章节: \(chapter.title), 长度: \(currentText.count)字符")
                        
                        // 强制发送多个UI更新通知，确保视图更新
                        forceUIUpdate()
                    } else {
                        // 章节内容为空，但仍显示一些提示
                        currentText = "【本章节内容为空】\n章节标题：\(chapter.title)"
                        print("【文本更新】警告：章节 \(chapter.title) 内容为空，显示提示信息")
                        
                        // 强制UI更新
                        objectWillChange.send()
                    }
                    return
                }
            }
            
            // 如果无法获取章节内容，回退到原来的方法
            let startOffset = min(Int(Double(fullText.count) * currentPosition), fullText.count - 1)
            let startIndex = fullText.index(fullText.startIndex, offsetBy: startOffset)
            let previewLength = min(3000, fullText.count - fullText.distance(from: fullText.startIndex, to: startIndex))
            let endIndex = fullText.index(startIndex, offsetBy: previewLength)
            
            currentText = String(fullText[startIndex..<endIndex])
            print("【文本更新】使用备选方法更新显示位置，显示\(previewLength)字符")
            
            // 强制UI更新
            objectWillChange.send()
        } else {
            print("【文本更新】警告: 文本为空，无法更新显示")
            
            // 如果文本为空但已有章节，尝试再次加载文本
            if !chapters.isEmpty {
                print("【文本更新】检测到章节存在但文本为空，尝试重新加载文本")
                if let doc = document, let viewModel = documentViewModel {
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let text = try TextExtractor.extractText(from: doc)
                            DispatchQueue.main.async {
                                self.fullText = text
                                print("【文本更新】成功重新加载文本，长度: \(text.count)字符")
                                self.updateCurrentTextDisplay()
                            }
                        } catch {
                            print("【文本更新】重新加载文本失败: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    func startSpeaking(from position: Double? = nil) {
        // 停止当前朗读
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // 设置朗读位置
        if let pos = position {
            currentPosition = pos
        }
        
        // 检查文本是否为空
        if fullText.isEmpty {
            print("⚠️ 无法朗读：文本为空")
            return
        }
        
        // 获取当前章节以确保我们只在章节内朗读
        let startOffset: Int
        let textToSpeak: String
        
        if !chapters.isEmpty {
            let chapterIndex = getCurrentChapterIndex()
            if chapterIndex >= 0 && chapterIndex < chapters.count {
                let chapter = chapters[chapterIndex]
                
                // 计算章节内的相对位置
                let relativePosition = (currentPosition - chapter.startPosition) / (chapter.endPosition - chapter.startPosition)
                
                // 计算在章节文本中的字符位置
                let chapterLength = chapter.endIndex - chapter.startIndex
                startOffset = chapter.startIndex + Int(Double(chapterLength) * relativePosition)
                
                // 只读取当前章节剩余部分
                if startOffset < chapter.endIndex {
                    let textStart = fullText.index(fullText.startIndex, offsetBy: startOffset)
                    let textEnd = fullText.index(fullText.startIndex, offsetBy: chapter.endIndex)
                    textToSpeak = String(fullText[textStart..<textEnd])
                } else {
                    // 如果已到章节末尾，准备朗读下一章
                    print("⚠️ 当前章节已读完，准备朗读下一章")
                    if chapterIndex < chapters.count - 1 {
                        nextChapter() // 跳转到下一章
                        return // 结束当前方法，让 nextChapter 中的调用来处理朗读
                    } else {
                        print("⚠️ 已是最后一章且已读完")
                        textToSpeak = ""
                    }
                }
            } else {
                // 章节索引无效
                startOffset = Int(Double(fullText.count) * currentPosition)
                textToSpeak = fullText.count > startOffset ? String(fullText[fullText.index(fullText.startIndex, offsetBy: startOffset)...]) : ""
            }
        } else {
            // 没有章节信息，使用全文比例
            startOffset = Int(Double(fullText.count) * currentPosition)
            textToSpeak = fullText.count > startOffset ? String(fullText[fullText.index(fullText.startIndex, offsetBy: startOffset)...]) : ""
        }
        
        if textToSpeak.isEmpty {
            print("⚠️ 无法朗读：截取的文本为空")
            return
        }
        
        print("🔊 开始朗读，文本长度: \(textToSpeak.count)，起始位置: \(currentPosition)")
        
        // 创建朗读对象
        utterance = AVSpeechUtterance(string: textToSpeak)
        
        // 设置语音和参数
        if let voice = AVSpeechSynthesisVoice(language: "zh-CN") {
            utterance?.voice = voice
            print("✓ 设置语音: \(voice.language)")
        } else {
            print("⚠️ 无法设置中文语音，使用默认语音")
        }
        
        // 调整参数，使声音更明显
        utterance?.rate = min(max(0.4, rate), 0.6) // 调整速率到0.4-0.6之间
        utterance?.volume = 1.0 // 设置最大音量
        utterance?.pitchMultiplier = 1.0 // 默认音调
        
        print("✓ 语音参数: 速率=\(utterance?.rate ?? 0), 音量=\(utterance?.volume ?? 0), 音调=\(utterance?.pitchMultiplier ?? 0)")
        
        // 开始朗读
        if let utterance = utterance {
            synthesizer.speak(utterance)
            isPlaying = true
            print("✓ 已发送朗读命令")
        } else {
            print("⚠️ 创建朗读utterance失败")
        }
        
        updateCurrentTextDisplay()
    }
    
    func pauseSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPlaying = false
            
            // 重置高亮
            currentReadingCharacterIndex = 0
            currentReadingCharacterCount = 0
            objectWillChange.send()
        }
    }
    
    func resumeSpeaking() {
        if synthesizer.isPaused {
            // 先检查当前位置是否与章节匹配
            let currentIndex = getCurrentChapterIndex()
            if currentIndex >= 0 && currentIndex < chapters.count {
                // 获取当前章节
                let chapter = chapters[currentIndex]
                
                // 检查当前位置是否在章节范围内
                let isWithinChapter = currentPosition >= chapter.startPosition && 
                                      currentPosition <= (chapter.endPosition - 0.005)
                
                if !isWithinChapter {
                    // 如果位置不在当前章节范围内，说明切换了章节但位置未更新
                    print("【播放恢复】检测到章节切换但位置未更新，重新定位到章节开始位置")
                    
                    // 更新位置为当前章节的起始位置（加一点偏移避免边界问题）
                    currentPosition = chapter.startPosition + 0.001
                    chapterInternalProgress = 0.001
                    
                    // 使用新位置开始播放
                    startSpeaking(from: currentPosition)
                    return
                }
                
                // 位置在范围内，继续正常播放
                synthesizer.continueSpeaking()
                isPlaying = true
                print("【播放恢复】继续从当前位置播放")
            } else {
                // 章节索引无效，重新开始播放
                startSpeaking(from: currentPosition)
            }
        } else if !isPlaying && !fullText.isEmpty {
            // 如果没有暂停但也没有在播放，而且有内容，则开始播放
            // 确保当前位置对应当前章节
            let currentIndex = getCurrentChapterIndex()
            if currentIndex >= 0 && currentIndex < chapters.count {
                let chapter = chapters[currentIndex]
                
                // 检查当前位置是否在章节范围内
                if currentPosition < chapter.startPosition || currentPosition > (chapter.endPosition - 0.005) {
                    // 如果不在范围内，更新到章节起始位置
                    currentPosition = chapter.startPosition + 0.001
                    chapterInternalProgress = 0.001
                    print("【播放开始】检测到位置不在章节范围内，已调整到章节起始位置")
                }
            }
            
            startSpeaking(from: currentPosition)
            print("【播放开始】从位置 \(currentPosition) 开始播放")
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        
        // 重置高亮
        currentReadingCharacterIndex = 0
        currentReadingCharacterCount = 0
        objectWillChange.send()
        
        // 保存阅读进度
        saveProgress()
    }
    
    func setPlaybackRate(_ rate: Float) {
        self.rate = rate
        // 应用到当前朗读
        if let currentUtterance = utterance {
            currentUtterance.rate = rate
        }
    }
    
    func skipForward() {
        if chapters.isEmpty {
            // 如果没有章节，按全文比例跳转
            currentPosition = min(1.0, currentPosition + 0.01)
            if isPlaying {
                startSpeaking(from: currentPosition)
            } else {
                updateCurrentTextDisplay()
            }
            return
        }
        
        // 获取当前章节
        let chapterIndex = getCurrentChapterIndex()
        if chapterIndex >= 0 && chapterIndex < chapters.count {
            let chapter = chapters[chapterIndex]
            
            // 计算章节内的相对位置
            let relativePosition = (currentPosition - chapter.startPosition) / (chapter.endPosition - chapter.startPosition)
            
            // 前进一点，但不超出当前章节
            let newRelativePosition = min(1.0, relativePosition + 0.05)
            
            // 计算在全文中的绝对位置
            let chapterRange = chapter.endPosition - chapter.startPosition
            let absolutePosition = chapter.startPosition + (chapterRange * newRelativePosition)
            
            // 设置全局位置
            currentPosition = min(chapter.endPosition, absolutePosition)
            chapterInternalProgress = newRelativePosition
            
            print("【跳转】章节内前进: \(relativePosition) -> \(newRelativePosition)")
            
            if isPlaying {
                startSpeaking(from: currentPosition)
            } else {
                updateCurrentTextDisplay()
            }
        }
    }
    
    func skipBackward() {
        if chapters.isEmpty {
            // 如果没有章节，按全文比例跳转
            currentPosition = max(0.0, currentPosition - 0.01)
            if isPlaying {
                startSpeaking(from: currentPosition)
            } else {
                updateCurrentTextDisplay()
            }
            return
        }
        
        // 获取当前章节
        let chapterIndex = getCurrentChapterIndex()
        if chapterIndex >= 0 && chapterIndex < chapters.count {
            let chapter = chapters[chapterIndex]
            
            // 计算章节内的相对位置
            let relativePosition = (currentPosition - chapter.startPosition) / (chapter.endPosition - chapter.startPosition)
            
            // 后退一点，但不超出当前章节
            let newRelativePosition = max(0.0, relativePosition - 0.05)
            
            // 计算在全文中的绝对位置
            let chapterRange = chapter.endPosition - chapter.startPosition
            let absolutePosition = chapter.startPosition + (chapterRange * newRelativePosition)
            
            // 设置全局位置
            currentPosition = max(chapter.startPosition, absolutePosition)
            chapterInternalProgress = newRelativePosition
            
            print("【跳转】章节内后退: \(relativePosition) -> \(newRelativePosition)")
            
            if isPlaying {
                startSpeaking(from: currentPosition)
            } else {
                updateCurrentTextDisplay()
            }
        }
    }
    
    func seekTo(position: Double) {
        // 约束进度为0-1之间
        let safePosition = max(0.0, min(1.0, position))
        
        if chapters.isEmpty {
            // 如果没有章节，则按照全文进度处理
            currentPosition = safePosition
            if isPlaying {
                startSpeaking(from: currentPosition)
            } else {
                updateCurrentTextDisplay()
            }
            return
        }
        
        // 保存当前章节索引，防止在任何情况下切换章节
        let currentIndex = getCurrentChapterIndex()
        if currentIndex >= 0 && currentIndex < chapters.count {
            let chapter = chapters[currentIndex]
            
            // 保存章节内部进度
            chapterInternalProgress = safePosition
            
            // 关键修改：确保位置永远不会超过章节的结束位置减去一个小偏移量
            // 如果是拖到最大值1.0，我们设置为0.95而不是0.999，确保绝对不会触及下一章节边界
            let adjustedPosition = safePosition >= 0.98 ? 0.95 : safePosition
            
            // 计算章节内偏移量
            let chapterRange = chapter.endPosition - chapter.startPosition
            let absolutePosition = chapter.startPosition + (chapterRange * adjustedPosition)
            
            // 额外保护：确保绝对不会超出当前章节
            let safeAbsolutePosition = min(chapter.endPosition - 0.005, absolutePosition)
            
            // 设置全局位置
            currentPosition = safeAbsolutePosition
            
            print("【进度条】章节内调整位置: \(safePosition) -> 全文位置: \(currentPosition)，章节：\(chapter.title)")
            
            // 如果正在播放，停止当前朗读并从新位置开始
            if isPlaying {
                synthesizer.stopSpeaking(at: .immediate)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.startSpeaking(from: self.currentPosition)
                }
            } else {
                // 如果不在播放，只更新文本显示
                updateCurrentTextDisplay()
            }
            
            // 强制UI更新
            objectWillChange.send()
            
            // 再次检查确保章节没有变化，如果变了则修复
            let newIndex = getCurrentChapterIndex()
            if newIndex != currentIndex {
                print("【严重错误】检测到章节切换: \(currentIndex) -> \(newIndex)，正在强制恢复")
                // 直接跳回原章节
                jumpToChapter(currentIndex)
            }
        }
    }
    
    private func saveProgress() {
        if let doc = document, let viewModel = documentViewModel {
            viewModel.updateDocumentProgress(id: doc.id, progress: currentPosition)
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            print("🔊 开始朗读文本")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            print("✓ 朗读完成")
            
            // 标记为已完成
            if utterance.speechString == self.fullText {
                self.currentPosition = 1.0
            }
            
            // 保存阅读进度
            self.saveProgress()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            print("⏸ 朗读暂停")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            print("▶️ 朗读继续")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // 增加高亮范围以使其更明显
            let adjustedLength = min(20, utterance.speechString.count - characterRange.location)
            
            if !self.chapters.isEmpty {
                let chapterIndex = self.getCurrentChapterIndex()
                if chapterIndex >= 0 && chapterIndex < self.chapters.count {
                    let chapter = self.chapters[chapterIndex]
                    
                    // 设置正确的朗读位置，但使用增强的高亮长度
                    self.currentReadingCharacterIndex = characterRange.location
                    self.currentReadingCharacterCount = adjustedLength
                    
                    // 更新章节内部进度 - 这是关键修改
                    if characterRange.location > 0 && utterance.speechString.count > 0 {
                        // 根据朗读位置更新章节内部进度
                        let readingProgress = Double(characterRange.location) / Double(utterance.speechString.count)
                        
                        // 使用加权平均，确保进度更新平滑
                        self.chapterInternalProgress = readingProgress
                        
                        // 更新全局位置
                        let chapterRange = chapter.endPosition - chapter.startPosition
                        self.currentPosition = chapter.startPosition + (chapterRange * readingProgress)
                        
                        // 每10次更新打印一次日志
                        if characterRange.location % 100 == 0 {
                            print("【朗读进度】位置: \(characterRange.location)/\(utterance.speechString.count), 章节进度: \(readingProgress)")
                        }
                    }
                    
                    // 强制发送UI更新通知
                    self.objectWillChange.send()
                }
            } else {
                // 没有章节时的处理
                self.currentReadingCharacterIndex = characterRange.location
                self.currentReadingCharacterCount = adjustedLength
                
                // 更新全局进度
                if utterance.speechString.count > 0 {
                    self.currentPosition = Double(characterRange.location) / Double(utterance.speechString.count)
                }
                
                self.objectWillChange.send()
            }
        }
    }
    
    // 添加章节跳转方法
    private func forceUIUpdate() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            
            // 添加连续的 UI 更新，确保变化被捕获
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.objectWillChange.send()
            }
        }
    }
    
    func jumpToChapter(_ index: Int) {
        guard index >= 0, index < chapters.count else {
            print("【章节跳转】失败: 章节索引超出范围，index=\(index), 总章节数=\(chapters.count)")
            return
        }
        
        let oldIndex = currentChapterIndex
        print("【章节跳转】开始: 从章节\(oldIndex + 1)跳转到章节\(index + 1)")
        
        // 重置内部进度
        chapterInternalProgress = 0.0
        
        // 更新章节索引
        currentChapterIndex = index
        cachedChapterIndex = index // 确保缓存也被更新
        let chapter = chapters[index]
        
        // 跳转到章节开始位置（增加小偏移以避免边界问题）
        let newPosition = chapter.startPosition + 0.001
        currentPosition = newPosition
        
        // 显示整章内容
        if chapter.startIndex < fullText.count && chapter.endIndex <= fullText.count {
            let startIndex = fullText.index(fullText.startIndex, offsetBy: chapter.startIndex)
            let endIndex = fullText.index(fullText.startIndex, offsetBy: chapter.endIndex)
            currentText = String(fullText[startIndex..<endIndex])
            print("【章节跳转】更新显示内容为整章，长度: \(currentText.count)字符")
        }
        
        // 强制更新UI
        forceUIUpdate()
        
        // 如果正在播放，则从新位置开始播放
        if isPlaying {
            print("【章节跳转】正在播放状态下跳转，重启朗读")
            synthesizer.stopSpeaking(at: .immediate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.startSpeaking(from: newPosition)
            }
        } else {
            // 即使暂停状态也更新文本显示和位置标记
            self.updateCurrentTextDisplay()
            
            // 在暂停状态下也保存章节信息
            print("【章节跳转】暂停状态下跳转，已更新位置和文本显示")
            
            // 重置高亮状态
            self.currentReadingCharacterIndex = 0
            self.currentReadingCharacterCount = 0
        }
        
        // 保存当前进度
        saveProgress()
        
        // 打印进度确认日志
        print("【章节跳转】完成: 跳转到章节「\(chapter.title)」，内部进度: \(chapterInternalProgress)，播放状态: \(isPlaying ? "播放中" : "已暂停")")
    }
    
    // 获取章节列表方法
    func getChapters() -> [Chapter] {
        // 如果缓存有效且不为空，直接返回缓存
        if chaptersCacheValid && !chaptersCache.isEmpty {
            return chaptersCache
        }
        
        // 避免短时间内重复调用
        let now = Date()
        if now.timeIntervalSince(lastChapterRequestTime) < 0.5 {
            return chapters
        }
        
        lastChapterRequestTime = now
        
        // 只在特定情况下打印日志
        #if DEBUG
        print("【章节获取-高效版】请求章节列表，当前章节数: \(chapters.count)")
        #endif
        
        // 更新缓存
        chaptersCache = chapters
        chaptersCacheValid = true
        
        // 如果章节列表为空但文本不为空，尝试再次分析章节
        if chapters.isEmpty && !fullText.isEmpty {
            print("【章节获取】章节列表为空但文本不为空，尝试重新分析章节")
            let result = ChapterSegmenter.splitTextIntoParagraphs(fullText)
            self.paragraphs = result.paragraphs
            self.chapters = result.chapters
            
            // 更新缓存
            chaptersCache = chapters
            
            print("【章节获取】重新分析完成，识别到\(chapters.count)个章节")
        }
        
        return chapters
    }
    
    // 获取当前章节索引的优化版本
    func getCurrentChapterIndex() -> Int {
        if chapters.isEmpty {
            return 0
        }
        
        // 使用二分搜索快速找到正确的章节
        var left = 0
        var right = chapters.count - 1
        
        // 先处理边界情况
        if currentPosition <= chapters[0].startPosition {
            return 0
        }
        
        if currentPosition >= chapters[chapters.count - 1].endPosition - 0.001 {
            return chapters.count - 1
        }
        
        while left <= right {
            let mid = (left + right) / 2
            let chapter = chapters[mid]
            
            // 增加安全边界检查
            let nextStartPosition = mid < chapters.count - 1 ? chapters[mid + 1].startPosition : 1.0
            
            // 检查是否在当前章节范围内
            // 关键修改：使用更严格的边界条件，确保不会因为精度问题误判章节
            if currentPosition >= chapter.startPosition && currentPosition < nextStartPosition - 0.001 {
                return mid
            } else if currentPosition >= nextStartPosition - 0.001 {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        
        // 如果二分查找失败，使用线性方法找最近的章节
        var closestIndex = 0
        var closestDistance = 1.0
        
        for (index, chapter) in chapters.enumerated() {
            // 找到位置所在的章节
            let nextStart = index < chapters.count - 1 ? chapters[index + 1].startPosition : 1.0
            if currentPosition >= chapter.startPosition && currentPosition < nextStart - 0.001 {
                return index
            }
            
            // 如果没有精确匹配，找最近的
            let distanceToStart = abs(currentPosition - chapter.startPosition)
            if distanceToStart < closestDistance {
                closestDistance = distanceToStart
                closestIndex = index
            }
        }
        
        return closestIndex
    }
    
    // 添加或修改上一章/下一章方法
    func previousChapter() {
        if currentChapterIndex > 0 {
            print("【章节控制】从章节\(currentChapterIndex + 1)跳转到章节\(currentChapterIndex)")
            
            // 使用 jumpToChapter 而不是直接修改 currentChapterIndex
            jumpToChapter(currentChapterIndex - 1)
            
            // 确保重置完成后打印日志以便于调试
            print("【章节控制】完成跳转，内部进度: \(chapterInternalProgress)")
        } else {
            print("【章节控制】已经是第一章")
        }
    }
    
    func nextChapter() {
        if currentChapterIndex < chapters.count - 1 {
            print("【章节控制】从章节\(currentChapterIndex + 1)跳转到章节\(currentChapterIndex + 2)")
            
            // 使用 jumpToChapter 而不是直接修改 currentChapterIndex
            jumpToChapter(currentChapterIndex + 1)
            
            // 确保重置完成后打印日志以便于调试
            print("【章节控制】完成跳转，内部进度: \(chapterInternalProgress)")
        } else {
            print("【章节控制】已经是最后一章")
        }
    }
    
    // 添加以下两个方法来允许外部更新章节信息
    func setChapters(_ newChapters: [Chapter]) {
        self.chapters = newChapters
        
        // 更新缓存
        chaptersCache = newChapters
        chaptersCacheValid = true
        
        print("【章节设置】章节列表已更新，共\(chapters.count)章")
        objectWillChange.send()
    }
    
    func setParagraphs(_ newParagraphs: [TextParagraph]) {
        self.paragraphs = newParagraphs
        print("【章节设置】段落列表已更新，共\(paragraphs.count)段")
    }
    
    // 添加获取当前章节内容的辅助方法
    public func getCurrentChapterContent() -> String {
        if !fullText.isEmpty && !chapters.isEmpty {
            let chapterIndex = getCurrentChapterIndex()
            if chapterIndex >= 0 && chapterIndex < chapters.count {
                return chapters[chapterIndex].extractContent(from: fullText)
            }
        }
        return currentText
    }
    
    // 确保这个方法返回正确的章节内部进度
    func getCurrentChapterInternalProgress() -> Double {
        // 如果没有章节或章节索引无效，返回全局进度
        if chapters.isEmpty || currentChapterIndex < 0 || currentChapterIndex >= chapters.count {
            return currentPosition
        }
        
        let chapter = chapters[currentChapterIndex]
        // 计算章节内相对进度
        if chapter.endPosition > chapter.startPosition {
            let progress = (currentPosition - chapter.startPosition) / (chapter.endPosition - chapter.startPosition)
            
            // 确保进度在0-1范围内
            let clampedProgress = max(0.0, min(1.0, progress))
            
            // 对于新切换的章节，限制最大进度为5%，除非明确设置了更大的值
            if chapterInternalProgress <= 0.05 && clampedProgress > 0.95 {
                // 检测异常进度跳跃，此时返回接近0的值
                print("【章节进度】检测到异常进度跳跃，限制进度值")
                return 0.01
            }
            
            // 记录日志以协助调试
            print("【章节进度】章节 \(currentChapterIndex+1), 内部进度: \(clampedProgress)")
            
            return clampedProgress
        } else {
            // 如果章节起止位置相同，返回0
            return 0.0
        }
    }
    
    // 强制设置当前章节索引，用于防止意外的章节跳转
    func forceSetCurrentChapterIndex(_ index: Int) {
        guard index >= 0 && index < chapters.count else { return }
        
        // 强制更新缓存和当前索引
        cachedChapterIndex = index
        currentChapterIndex = index
        
        print("【章节控制】强制设置当前章节索引为：\(index)")
    }
    
    // 添加在章节内调整位置的方法
    func seekWithinCurrentChapter(position: Double) {
        // 约束进度为0-1之间
        let safePosition = max(0.0, min(1.0, position))
        
        // 获取当前章节
        let chapterIndex = getCurrentChapterIndex()
        if chapterIndex >= 0 && chapterIndex < chapters.count {
            let chapter = chapters[chapterIndex]
            
            // 更新章节内部进度
            chapterInternalProgress = safePosition
            
            // 计算章节内偏移量
            let chapterRange = chapter.endPosition - chapter.startPosition
            let absolutePosition = chapter.startPosition + (chapterRange * safePosition)
            
            // 确保不会超出章节边界
            let safeAbsolutePosition = min(chapter.endPosition - 0.005, absolutePosition)
            
            // 设置全局位置
            currentPosition = safeAbsolutePosition
            
            print("【进度条】章节内调整位置: \(safePosition), 对应全文位置: \(currentPosition)")
            
            // 如果正在播放，从新位置开始播放
            if isPlaying {
                stopSpeaking()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.startSpeaking(from: safeAbsolutePosition)
                }
            } else {
                // 如果不在播放，只更新文本显示
                updateCurrentTextDisplay()
                
                // 强制UI更新
                objectWillChange.send()
            }
        }
    }
} 