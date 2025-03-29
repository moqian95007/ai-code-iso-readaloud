import Foundation
import Combine
import SwiftUI

class GlobalPlaybackManager: ObservableObject {
    static let shared = GlobalPlaybackManager()
    
    @Published var currentDocument: Document?
    @Published var isPlaying: Bool = false
    @Published var synthesizer: SpeechSynthesizer?
    
    private init() {}
    
    func startPlayback(document: Document, viewModel: DocumentsViewModel) {
        // 确保在主线程进行UI更新
        DispatchQueue.main.async {
            // 停止当前播放
            self.stopPlayback()
            
            // 创建新的合成器
            let synth = SpeechSynthesizer()
            
            // 先设置属性，再加载文档
            self.synthesizer = synth
            self.currentDocument = document
            
            // 加载文档（异步）
            synth.loadDocument(document, viewModel: viewModel)
            
            // 延迟开始播放，确保文档加载完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !synth.fullText.isEmpty {
                    synth.startSpeaking(from: document.progress)
                    self.isPlaying = true
                }
            }
        }
    }
    
    func pausePlayback() {
        DispatchQueue.main.async {
            self.synthesizer?.pauseSpeaking()
            self.isPlaying = false
        }
    }
    
    func resumePlayback() {
        DispatchQueue.main.async {
            if let synth = self.synthesizer, !synth.fullText.isEmpty {
                synth.resumeSpeaking()
                self.isPlaying = true
            }
        }
    }
    
    func stopPlayback() {
        DispatchQueue.main.async {
            self.synthesizer?.stopSpeaking()
            self.synthesizer = nil
            self.currentDocument = nil
            self.isPlaying = false
        }
    }
} 