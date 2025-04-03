import SwiftUI
import Combine

/// 定时关闭选项
enum TimerOption: String, CaseIterable, Identifiable {
    case off = "不开启"
    case afterChapter = "播完本章"
    case after10Min = "10分钟后"
    case after20Min = "20分钟后"
    case after30Min = "30分钟后"
    case after60Min = "60分钟后"
    case after90Min = "90分钟后"
    case custom = "自定义"
    
    var id: String { self.rawValue }
    
    var minutes: Int? {
        switch self {
        case .off, .afterChapter, .custom:
            return nil
        case .after10Min:
            return 10
        case .after20Min:
            return 20
        case .after30Min:
            return 30
        case .after60Min:
            return 60
        case .after90Min:
            return 90
        }
    }
}

/// 管理定时关闭功能
class TimerManager: ObservableObject {
    // 共享实例
    static let shared = TimerManager()
    
    // 定时器设置
    @Published var isTimerActive: Bool = false
    @Published var selectedOption: TimerOption = .off
    @Published var customMinutes: Int = 30
    @Published var remainingSeconds: Int = 0
    @Published var showTimerSheet: Bool = false
    
    // 定时器
    private var timer: AnyCancellable?
    
    private init() {
        // 从 UserDefaults 读取设置 (如果有)
        let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.timerOption) ?? TimerOption.off.rawValue
        selectedOption = TimerOption(rawValue: rawValue) ?? .off
        customMinutes = UserDefaults.standard.integer(forKey: UserDefaultsKeys.customTimerMinutes)
        if customMinutes == 0 {
            customMinutes = 30 // 默认值
        }
    }
    
    /// 设置定时关闭
    func setTimer(option: TimerOption, customValue: Int? = nil) {
        // 取消现有定时器
        cancelTimer()
        
        selectedOption = option
        
        // 如果是自定义且提供了值，更新自定义分钟数
        if option == .custom, let value = customValue, value > 0 {
            customMinutes = value
            UserDefaults.standard.set(customMinutes, forKey: UserDefaultsKeys.customTimerMinutes)
        }
        
        // 保存选择的选项
        UserDefaults.standard.set(option.rawValue, forKey: UserDefaultsKeys.timerOption)
        
        // 根据选项类型启动定时器
        switch option {
        case .off:
            // 不做任何事
            isTimerActive = false
            remainingSeconds = 0
            
        case .afterChapter:
            // 播完本章后停止，不需要启动倒计时
            isTimerActive = true
            remainingSeconds = 0
            
        case .after10Min, .after20Min, .after30Min, .after60Min, .after90Min, .custom:
            // 计算剩余秒数
            let minutes = option == .custom ? customMinutes : (option.minutes ?? 0)
            remainingSeconds = minutes * 60
            isTimerActive = true
            
            // 启动倒计时
            startCountdown()
        }
    }
    
    /// 启动倒计时
    private func startCountdown() {
        // 取消现有定时器
        timer?.cancel()
        
        // 创建新定时器，每秒更新一次
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // 减少剩余时间
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                }
                
                // 时间到，停止播放
                if self.remainingSeconds <= 0 && self.isTimerActive {
                    self.stopPlayback()
                }
            }
    }
    
    /// 取消定时器
    func cancelTimer() {
        timer?.cancel()
        timer = nil
        isTimerActive = false
        remainingSeconds = 0
        selectedOption = .off
        UserDefaults.standard.set(TimerOption.off.rawValue, forKey: UserDefaultsKeys.timerOption)
    }
    
    /// 停止播放
    private func stopPlayback() {
        // 设置手动暂停标志，防止被识别为自然播放结束
        SpeechDelegate.shared.wasManuallyPaused = true
        
        // 停止播放
        SpeechManager.shared.pauseSpeaking()
        
        // 重置定时器状态
        cancelTimer()
        
        // 发送通知
        NotificationCenter.default.post(name: Notification.Name("TimerCompleted"), object: nil)
    }
    
    /// 格式化剩余时间为 mm:ss
    func formattedRemainingTime() -> String {
        if !isTimerActive || remainingSeconds <= 0 {
            return ""
        }
        
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
} 