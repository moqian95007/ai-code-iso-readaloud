import SwiftUI

/// 定时关闭选择弹窗
struct TimerSheetView: View {
    @ObservedObject private var timerManager = TimerManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var customMinutes: String = "30"
    @State private var showCustomView: Bool = false
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("timer_shutdown".localized)
                .font(.system(size: 18, weight: .bold))
                .padding(.vertical, 12)
            
            Divider()
            
            if showCustomView {
                // 自定义时间设置界面
                VStack(spacing: 16) {
                    Text("enter_minutes".localized)
                        .font(.system(size: 16))
                        .padding(.top, 20)
                    
                    // 自定义分钟数输入框
                    TextField("minutes".localized, text: $customMinutes)
                        .keyboardType(.numberPad)
                        .font(.system(size: 18))
                        .multilineTextAlignment(.center)
                        .frame(width: 100)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                        )
                    
                    // 按钮组
                    HStack(spacing: 16) {
                        // 取消按钮
                        Button("cancel".localized) {
                            showCustomView = false
                        }
                        .frame(width: 100)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        
                        // 确定按钮
                        Button("confirm".localized) {
                            // 处理自定义分钟数
                            if let minutes = Int(customMinutes), minutes > 0, minutes <= 120 {
                                timerManager.setTimer(option: .custom, customValue: minutes)
                                isPresented = false
                            }
                        }
                        .frame(width: 100)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .padding(.vertical, 10)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            } else {
                // 定时选项列表
                ScrollView {
                    VStack(spacing: 0) {
                        // 不开启选项
                        RadioButtonRow(
                            title: TimerOption.off.rawValue.localized,
                            isSelected: timerManager.selectedOption == .off,
                            action: {
                                timerManager.setTimer(option: .off)
                                isPresented = false
                            }
                        )
                        
                        // 播完本章选项
                        RadioButtonRow(
                            title: TimerOption.afterChapter.rawValue.localized,
                            isSelected: timerManager.selectedOption == .afterChapter,
                            action: {
                                timerManager.setTimer(option: .afterChapter)
                                isPresented = false
                            }
                        )
                        
                        // 10分钟后选项
                        RadioButtonRow(
                            title: TimerOption.after10Min.rawValue.localized,
                            isSelected: timerManager.selectedOption == .after10Min,
                            action: {
                                timerManager.setTimer(option: .after10Min)
                                isPresented = false
                            }
                        )
                        
                        // 20分钟后选项
                        RadioButtonRow(
                            title: TimerOption.after20Min.rawValue.localized,
                            isSelected: timerManager.selectedOption == .after20Min,
                            action: {
                                timerManager.setTimer(option: .after20Min)
                                isPresented = false
                            }
                        )
                        
                        // 30分钟后选项
                        RadioButtonRow(
                            title: TimerOption.after30Min.rawValue.localized,
                            isSelected: timerManager.selectedOption == .after30Min,
                            action: {
                                timerManager.setTimer(option: .after30Min)
                                isPresented = false
                            }
                        )
                        
                        // 60分钟后选项
                        RadioButtonRow(
                            title: TimerOption.after60Min.rawValue.localized,
                            isSelected: timerManager.selectedOption == .after60Min,
                            action: {
                                timerManager.setTimer(option: .after60Min)
                                isPresented = false
                            }
                        )
                        
                        // 90分钟后选项
                        RadioButtonRow(
                            title: TimerOption.after90Min.rawValue.localized,
                            isSelected: timerManager.selectedOption == .after90Min,
                            action: {
                                timerManager.setTimer(option: .after90Min)
                                isPresented = false
                            }
                        )
                        
                        // 自定义选项
                        RadioButtonRow(
                            title: TimerOption.custom.rawValue.localized,
                            isSelected: timerManager.selectedOption == .custom,
                            action: {
                                // 显示自定义界面
                                customMinutes = "\(timerManager.customMinutes)"
                                showCustomView = true
                            }
                        )
                    }
                }
                
                // 底部按钮
                Button(action: {
                    isPresented = false
                }) {
                    Text("close".localized)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundColor(themeManager.isDarkMode ? .white : .blue)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .background(themeManager.backgroundColor())
        .foregroundColor(themeManager.foregroundColor())
        .cornerRadius(12)
        .shadow(radius: 5)
        .padding()
    }
}

/// 单选按钮行
struct RadioButtonRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .padding(.vertical, 15)
                
                Spacer()
                
                // 选中状态指示器
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.gray.opacity(0.2) : Color.clear)
    }
}