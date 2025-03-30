import Foundation
import Combine
import SwiftUI

class GlobalPlaybackManager: ObservableObject {
    static let shared = GlobalPlaybackManager()
    
    @Published var isPlaying: Bool = false
    @Published var currentDocument: Document? = nil
    @Published var currentPosition: Double = 0.0
    @Published var currentSynthesizer: Any? = nil // 由于类型可能会变化，使用Any
    
    private init() {}
    
    func startPlayback(document: Document, synthesizer: Any) {
        currentDocument = document
        currentSynthesizer = synthesizer
        isPlaying = true
    }
    
    func pausePlayback() {
        isPlaying = false
    }
    
    func resumePlayback() {
        isPlaying = true
    }
    
    func stopPlayback() {
        isPlaying = false
        currentDocument = nil
        currentSynthesizer = nil
        currentPosition = 0.0
    }
    
    func updatePosition(_ position: Double) {
        currentPosition = position
    }
} 