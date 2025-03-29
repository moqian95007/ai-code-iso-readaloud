import SwiftUI
import Combine

class NavigationState: ObservableObject {
    static let shared = NavigationState()
    
    @Published var isInReaderView: Bool = false
    @Published var shouldNavigateToReader: Bool = false
    
    private init() {}
} 