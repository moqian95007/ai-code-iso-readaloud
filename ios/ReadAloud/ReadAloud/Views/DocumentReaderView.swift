import SwiftUI

struct DocumentReaderView: View {
    let documentTitle: String
    let document: Document
    let viewModel: DocumentsViewModel
    
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    @State private var selectedVoice: String = "默认"
    @State private var playbackSpeed: Double = 1.0
    @State private var playMode: PlayMode = .sequential
    @State private var showSpeedOptions = false
    @State private var showChapterList = false
    @State private var showFontSizeOptions = false
    @State private var fontSize: FontSize = .medium
    @State private var isDocumentLoaded = false
    @Environment(\.dismiss) var dismiss
    
    // 使用懒加载获取synthesizer，避免在视图初始化时创建
    private var synthesizer: SpeechSynthesizer {
        if playbackManager.currentDocument?.id == document.id,
           let existingSynthesizer = playbackManager.synthesizer {
            return existingSynthesizer
        } else {
            let newSynthesizer = SpeechSynthesizer()
            // 推迟更新playbackManager到onAppear中
            return newSynthesizer
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                Button(action: {
                    // 离开时停止朗读
                    if let synth = playbackManager.synthesizer {
                        synth.stopSpeaking()
                    }
                    dismiss()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                Text(documentTitle)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    // 上传新主播的操作
                }) {
                    Text("新主播上架")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding()
            .background(Color.white)
            
            // 选择语音包区域
            VoiceSelectionView(selectedVoice: $selectedVoice)
                .padding(.vertical, 10)
                .background(Color.white)
            
            // 朗读内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 显示当前朗读的文本
                    if !isDocumentLoaded {
                        // 加载状态
                        ProgressView("正在加载文档...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(50)
                    } else if let synth = playbackManager.synthesizer, synth.currentText.starts(with: "文本提取失败") {
                        // 文本提取失败的提示
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                                .padding(.bottom, 5)
                            
                            Text(synth.currentText)
                                .font(.system(size: 16))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.red)
                            
                            // 解决方案建议
                            VStack(alignment: .leading, spacing: 10) {
                                Text("可能的解决方案:")
                                    .font(.headline)
                                    .padding(.top, 5)
                                
                                ForEach(["确保文件格式正确", "尝试转换为TXT或PDF格式", "重新导入文档"], id: \.self) { suggestion in
                                    HStack(alignment: .top) {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(.green)
                                        Text(suggestion)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(10)
                    } else if let synth = playbackManager.synthesizer {
                        VStack(alignment: .leading) {
                            // 添加调试标记
                            Text("文本已加载-长度: \(synth.currentText.count)字符")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.bottom, 5)
                            
                            if synth.currentText.isEmpty && !synth.fullText.isEmpty {
                                // 有内容但currentText为空的情况，手动显示文本开头
                                let startText = String(synth.fullText.prefix(500))
                                Text(startText)
                                    .font(.system(size: fontSize.size))
                                    .foregroundColor(.black) // 强制黑色文本
                                    .lineSpacing(5)
                                    .background(Color(.systemYellow).opacity(0.1)) // 添加背景色以确认文本框位置
                                    .border(Color.orange, width: 1) // 添加边框以确认文本框大小
                            } else if !synth.currentText.isEmpty {
                                Text(synth.currentText)
                                    .font(.system(size: fontSize.size))
                                    .foregroundColor(.black) // 强制黑色文本
                                    .lineSpacing(5)
                                    .background(Color(.systemYellow).opacity(0.1)) // 添加背景色以确认文本框位置
                                    .border(Color.orange, width: 1) // 添加边框以确认文本框大小
                            } else {
                                Text("请点击播放按钮开始阅读")
                                    .foregroundColor(.gray)
                                    .italic()
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay( // 添加边框以确认整个容器的位置和大小
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    } else {
                        Text("无法加载文档内容")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .background(Color(.systemGray6))
            
            // 底部控制区域
            VStack(spacing: 15) {
                // 进度条
                ProgressSlider(value: Binding(
                    get: { playbackManager.synthesizer?.currentPosition ?? 0 },
                    set: { position in
                        playbackManager.synthesizer?.seekTo(position: position)
                    }
                ))
                    .padding(.horizontal)
                
                // 播放控制
                HStack(spacing: 40) {
                    Button(action: {
                        playbackManager.synthesizer?.skipBackward()
                    }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        if playbackManager.isPlaying {
                            playbackManager.synthesizer?.pauseSpeaking()
                            playbackManager.isPlaying = false
                        } else {
                            if let synth = playbackManager.synthesizer {
                                if synth.fullText.isEmpty {
                                    // 如果文本为空，不执行任何操作
                                    print("无法播放：文本为空")
                                } else {
                                    synth.resumeSpeaking()
                                    if !synth.isPlaying {
                                        synth.startSpeaking(from: synth.currentPosition)
                                    }
                                    playbackManager.isPlaying = true
                                    
                                    // 确保文本显示已更新
                                    if synth.currentText.isEmpty {
                                        synth.updateCurrentTextDisplay()
                                    }
                                }
                            }
                        }
                    }) {
                        Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        playbackManager.synthesizer?.skipForward()
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }
                }
                
                // 其他控制
                HStack(spacing: 30) {
                    Button(action: {
                        showSpeedOptions.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "speedometer")
                            Text("\(String(format: "%.1f", playbackSpeed))x")
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showSpeedOptions) {
                        SpeedOptionsView(playbackSpeed: $playbackSpeed, synthesizer: playbackManager.synthesizer)
                    }
                    
                    Button(action: {
                        showChapterList.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet")
                            Text("章节")
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showChapterList) {
                        ChapterListView()
                    }
                    
                    Button(action: {
                        showFontSizeOptions.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "textformat.size")
                            Text(fontSize.rawValue)
                        }
                        .foregroundColor(.gray)
                    }
                    .popover(isPresented: $showFontSizeOptions) {
                        FontSizeOptionsView(fontSize: $fontSize)
                    }
                    
                    Button(action: {
                        // 循环播放模式切换
                        let allModes = PlayMode.allCases
                        if let currentIndex = allModes.firstIndex(of: playMode),
                           let nextMode = allModes[safe: (currentIndex + 1) % allModes.count] {
                            playMode = nextMode
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: playMode == .sequential ? "repeat" : (playMode == .loop ? "repeat.1" : "1.circle"))
                            Text(playMode.rawValue)
                        }
                        .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 5)
            }
            .padding()
            .background(Color.white)
        }
        .onAppear {
            // 先标记为未加载状态，显示加载指示器
            isDocumentLoaded = false
            
            // 使用DispatchQueue确保视图已完全渲染后再执行这些操作
            DispatchQueue.main.async {
                // 设置当前文档
                playbackManager.currentDocument = document
                playbackManager.synthesizer = synthesizer
                
                // 加载文档
                print("开始加载文档: \(document.title)")
                synthesizer.loadDocument(document, viewModel: viewModel)
                
                // 延迟标记已加载，给予文档内容加载的时间
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // 强制更新UI
                    DispatchQueue.main.async {
                        // 确保文本显示更新
                        synthesizer.updateCurrentTextDisplay()
                        // 标记文档已加载
                        isDocumentLoaded = true
                        
                        // 打印调试信息
                        print("文档加载状态: isDocumentLoaded=\(isDocumentLoaded)")
                        print("文本内容状态: fullText长度=\(synthesizer.fullText.count)")
                        print("文本内容状态: currentText长度=\(synthesizer.currentText.count)")
                        
                        // 显示文本内容的前20个字符用于调试
                        if !synthesizer.currentText.isEmpty {
                            let previewText = String(synthesizer.currentText.prefix(20))
                            print("文本前20个字符: \"\(previewText)\"")
                        }
                    }
                }
            }
        }
        .onDisappear {
            // 只有在当前文档不在播放时才停止朗读
            if !playbackManager.isPlaying {
                DispatchQueue.main.async {
                    playbackManager.synthesizer?.stopSpeaking()
                    playbackManager.synthesizer = nil
                    playbackManager.currentDocument = nil
                }
            }
        }
    }
}

// 进度滑块
struct ProgressSlider: View {
    @Binding var value: Double
    
    var body: some View {
        VStack(spacing: 5) {
            Slider(value: $value, in: 0...1) { editing in
                // 完成拖动后触发朗读定位
            }
            .accentColor(.blue)
            
            HStack {
                Text(formatTime(percent: value))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text(formatProgress(percent: value))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func formatTime(percent: Double) -> String {
        // 假设一篇文章平均阅读时间为1小时
        let estimatedTotalSeconds = 3600.0
        let remainingSeconds = (1 - percent) * estimatedTotalSeconds
        
        let minutes = Int(remainingSeconds / 60)
        let seconds = Int(remainingSeconds) % 60
        
        return String(format: "剩余 %02d:%02d", minutes, seconds)
    }
    
    private func formatProgress(percent: Double) -> String {
        return String(format: "%.1f%%", percent * 100)
    }
}

// 语音选择视图
struct VoiceSelectionView: View {
    @Binding var selectedVoice: String
    
    private let voices = ["默认", "聆小琪", "聆小美", "聆小龙"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(voices, id: \.self) { voice in
                    VoiceOption(
                        voiceName: voice,
                        isSelected: voice == selectedVoice
                    ) {
                        selectedVoice = voice
                    }
                }
                
                Button(action: {
                    // 添加更多语音包的操作
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                        
                        Text("添加")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(width: 70, height: 70)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
        }
    }
}

// 单个语音选项
struct VoiceOption: View {
    let voiceName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                
                Text(voiceName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .black)
            }
            .frame(width: 70, height: 70)
            .background(isSelected ? Color.blue.opacity(0.05) : Color.clear)
            .cornerRadius(10)
        }
    }
}

// 速度选项视图
struct SpeedOptionsView: View {
    @Binding var playbackSpeed: Double
    let synthesizer: SpeechSynthesizer?
    
    private let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var body: some View {
        VStack(spacing: 10) {
            Text("朗读速度")
                .font(.headline)
                .padding(.top)
            
            ForEach(speedOptions, id: \.self) { speed in
                Button(action: {
                    playbackSpeed = speed
                    // 设置朗读速度
                    synthesizer?.setPlaybackRate(Float(speed))
                }) {
                    HStack {
                        Text("\(speed, specifier: "%.2f")x")
                        
                        Spacer()
                        
                        if abs(playbackSpeed - speed) < 0.01 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(abs(playbackSpeed - speed) < 0.01 ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button("取消") {}
                .padding()
        }
        .padding()
        .frame(width: 200)
    }
}

// 章节列表视图（简化版）
struct ChapterListView: View {
    var body: some View {
        VStack {
            Text("章节列表")
                .font(.headline)
                .padding()
            
            // 实际应用中，应从文档中提取章节列表
            Text("该文档未提供章节信息")
                .foregroundColor(.gray)
                .padding()
            
            Button("取消") {}
                .padding()
        }
        .frame(width: 250, height: 300)
    }
}

// 字体大小选项视图
struct FontSizeOptionsView: View {
    @Binding var fontSize: FontSize
    
    var body: some View {
        VStack(spacing: 10) {
            Text("字体大小")
                .font(.headline)
                .padding(.top)
            
            ForEach(FontSize.allCases) { size in
                Button(action: {
                    fontSize = size
                }) {
                    HStack {
                        Text(size.rawValue)
                            .font(.system(size: size.size))
                        
                        Spacer()
                        
                        if size == fontSize {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(size == fontSize ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button("取消") {}
                .padding()
        }
        .padding()
        .frame(width: 200)
    }
}

// 辅助扩展
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// 播放模式枚举
enum PlayMode: String, CaseIterable, Identifiable {
    case sequential = "顺序播放"
    case loop = "循环播放"
    case singleChapter = "单章播放"
    
    var id: String { self.rawValue }
}

// 字体大小枚举
enum FontSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"
    case extraLarge = "特大"
    
    var id: String { self.rawValue }
    
    var size: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 18
        case .large: return 22
        case .extraLarge: return 26
        }
    }
}

// 预览
struct DocumentReaderView_Previews: PreviewProvider {
    static var previews: some View {
        DocumentReaderView(
            documentTitle: "《极品家丁》", 
            document: Document(
                title: "极品家丁", 
                fileName: "极品家丁.txt", 
                fileURL: URL(fileURLWithPath: ""), 
                fileType: .txt,
                fileHash: "dummyHashForPreview"
            ), 
            viewModel: DocumentsViewModel()
        )
    }
} 
