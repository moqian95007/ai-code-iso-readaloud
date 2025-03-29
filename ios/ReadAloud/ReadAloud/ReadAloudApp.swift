//
//  ReadAloudApp.swift
//  ReadAloud
//
//  Created by moqian on 2025/3/27.
//

import SwiftUI
import AVFoundation

@main
struct ReadAloudApp: App {
    @State private var isAudioSessionConfigured = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    configureAudioSession()
                }
        }
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true)
            print("全局音频会话配置成功")
            isAudioSessionConfigured = true
            
            // 检查语音合成服务是否可用
            if AVSpeechSynthesisVoice.speechVoices().count > 0 {
                print("可用语音: \(AVSpeechSynthesisVoice.speechVoices().count)个")
                
                // 查找中文语音
                let chineseVoices = AVSpeechSynthesisVoice.speechVoices().filter { 
                    $0.language.contains("zh-") 
                }
                
                if !chineseVoices.isEmpty {
                    print("找到\(chineseVoices.count)个中文语音")
                    chineseVoices.forEach { voice in
                        print("- \(voice.name): \(voice.language)")
                    }
                } else {
                    print("⚠️ 未找到中文语音")
                }
            } else {
                print("⚠️ 设备上没有可用的语音")
            }
        } catch {
            print("音频会话配置失败: \(error)")
            isAudioSessionConfigured = false
        }
    }
}
