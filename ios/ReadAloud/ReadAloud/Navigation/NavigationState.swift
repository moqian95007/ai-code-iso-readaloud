import Foundation
import Combine

class ReadAloudNavigationState: ObservableObject {
    static let shared = ReadAloudNavigationState()
    
    @Published var isInReaderView: Bool = false
    @Published var shouldNavigateToReader: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 当导航到阅读器时，自动设置状态为正在阅读器中
        $shouldNavigateToReader
            .sink { [weak self] shouldNavigate in
                if shouldNavigate {
                    self?.isInReaderView = true
                }
            }
            .store(in: &cancellables)
    }
} 