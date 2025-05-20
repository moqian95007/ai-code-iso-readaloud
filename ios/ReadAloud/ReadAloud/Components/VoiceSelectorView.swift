import SwiftUI
import AVFoundation

/// 语音选择视图
struct VoiceSelectorView: View {
    @Binding var selectedVoiceIdentifier: String
    @Binding var showVoiceSelector: Bool
    var availableVoices: [AVSpeechSynthesisVoice]
    let articleLanguage: String
    
    // 内部状态变量，用于存储实际使用的语音列表
    @State private var voices: [AVSpeechSynthesisVoice] = []
    
    // 按语言分组的语音列表
    private var groupedVoices: [(String, [AVSpeechSynthesisVoice])] {
        // 使用内部状态的语音列表
        if voices.isEmpty {
            print("语音列表为空")
            return []
        }
        
        let grouped = Dictionary(grouping: voices) { voice in
            // 获取语言名称
            let locale = Locale(identifier: voice.language)
            let languageName = locale.localizedString(forLanguageCode: locale.languageCode ?? voice.language) ?? voice.language
            return languageName
        }
        
        let sortedGroups = grouped.sorted { $0.key < $1.key }
        print("总共有 \(sortedGroups.count) 种语言")
        return sortedGroups
    }
    
    // 当前选中的语言
    @State private var selectedLanguage: String?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Group {
                if voices.isEmpty {
                    // 显示加载中或者没有语音的提示
                    VStack {
                        Text("loading_voices".localized)
                        ProgressView()
                    }
                } else if let selectedLanguage = selectedLanguage, 
                          let voices = groupedVoices.first(where: { $0.0 == selectedLanguage })?.1,
                          !voices.isEmpty {
                    // 显示选中语言下的所有主播
                    List {
                        ForEach(voices, id: \.identifier) { voice in
                            Button(action: {
                                // 检查语言是否匹配
                                if isLanguageCompatible(voiceLanguage: voice.language, articleLanguage: articleLanguage) {
                                    selectedVoiceIdentifier = voice.identifier
                                    // 保存选择的语音
                                    UserDefaults.standard.set(selectedVoiceIdentifier, forKey: UserDefaultsKeys.selectedVoiceIdentifier)
                                    showVoiceSelector = false
                                } else {
                                    errorMessage = "select_matching_voice".localized
                                    showErrorAlert = true
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(voiceDisplayName(voice))
                                            .font(.headline)
                                        Text(voice.language)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    if voice.identifier == selectedVoiceIdentifier {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    .navigationTitle(selectedLanguage)
                    .navigationBarItems(
                        leading: Button("back".localized) {
                            self.selectedLanguage = nil
                        }
                    )
                } else {
                    // 显示语言列表
                    List {
                        ForEach(groupedVoices, id: \.0) { language, voices in
                            Button(action: {
                                selectedLanguage = language
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(language)
                                            .font(.headline)
                                        Text("voice_count".localized(with: voices.count))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                    .navigationTitle("select_language".localized)
                    .navigationBarItems(
                        trailing: Button("cancel".localized) {
                            showVoiceSelector = false
                        }
                    )
                }
            }
        }
        .alert("alert_title".localized, isPresented: $showErrorAlert) {
            Button("ok".localized, role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            print("VoiceSelectorView 出现，可用语音数量: \(availableVoices.count)")
            
            // 如果传入的语音列表为空，尝试重新获取
            if availableVoices.isEmpty {
                print("传入的语音列表为空，尝试重新获取")
                let newVoices = AVSpeechSynthesisVoice.speechVoices()
                print("重新获取到 \(newVoices.count) 个语音")
                DispatchQueue.main.async {
                    self.voices = newVoices
                }
            } else {
                // 使用传入的语音列表
                DispatchQueue.main.async {
                    self.voices = availableVoices
                }
            }
            
            // 输出语音信息，用于调试
            for voice in self.voices {
                print("语音: \(voice.name), 语言: \(voice.language)")
            }
        }
    }
    
    // 获取语音的显示名称
    private func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
        // 根据语音名称格式化显示名称
        let name = voice.name
        
        // 常见的中文语音处理
        if name.contains("Tingting") {
            return "婷婷"
        } else if name.contains("Meijia") {
            return "美佳"
        } else if name.contains("Tian-Tian") {
            return "天天"
        } else if name.contains("Li-mu") {
            return "李木"
        } else if name.contains("Yu-shu") {
            return "玉书"
        } else if name.contains("Sinji") {
            return "新吉"
        } else {
            // 如果无法识别特定名称，返回原始名称
            return name
        }
    }
    
    // 检查语音语言是否与文章语言兼容
    private func isLanguageCompatible(voiceLanguage: String, articleLanguage: String) -> Bool {
        // 特殊情况处理
        if voiceLanguage.isEmpty || articleLanguage.isEmpty {
            print("语言代码为空，默认兼容")
            return true // 如果语言代码为空，默认为兼容
        }
        
        // 提取语言代码（如 "zh-CN" 中的 "zh"）
        let voiceMainLanguage = voiceLanguage.split(separator: "-").first?.lowercased() ?? voiceLanguage.lowercased()
        let articleMainLanguage = articleLanguage.split(separator: "-").first?.lowercased() ?? articleLanguage.lowercased()
        
        print("比较语音语言: \(voiceMainLanguage) 与文章语言: \(articleMainLanguage)")
        
        // 特殊处理：部分中文变体兼容性
        if (voiceMainLanguage == "zh" || voiceMainLanguage == "yue" || voiceMainLanguage == "cmn") &&
           (articleMainLanguage == "zh" || articleMainLanguage == "yue" || articleMainLanguage == "cmn") {
            print("中文变体语言，视为兼容")
            return true
        }
        
        // 特殊处理：英文和中文语音的广泛兼容性
        if (voiceMainLanguage == "zh" && articleMainLanguage == "en") ||
           (voiceMainLanguage == "en" && articleMainLanguage == "zh") {
            print("中英文跨语言朗读，允许用户使用")
            return true
        }
        
        // 特殊处理：语音朗读器
        if voiceMainLanguage == "auto" {
            print("语音为自动检测，视为兼容")
            return true // 自动语言检测，总是视为兼容
        }
        
        // 如果主要语言代码相同，则认为兼容
        let isCompatible = voiceMainLanguage == articleMainLanguage
        
        if isCompatible {
            print("语言兼容：\(voiceMainLanguage) 与 \(articleMainLanguage)")
        } else {
            print("语言不兼容：\(voiceMainLanguage) 与 \(articleMainLanguage)")
        }
        
        return isCompatible
    }
}