import SwiftUI

/// 语速选择视图
struct SpeedSelectorView: View {
    @Binding var selectedRate: Double
    @Binding var showSpeedSelector: Bool
    
    // 预设的语速选项
    let availableRates: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
    
    // 临时存储用户选择的语速值，确认后再更新到主视图
    @State private var tempRate: Double
    
    init(selectedRate: Binding<Double>, showSpeedSelector: Binding<Bool>) {
        self._selectedRate = selectedRate
        self._showSpeedSelector = showSpeedSelector
        self._tempRate = State(initialValue: selectedRate.wrappedValue)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("调语速")
                .font(.headline)
                .padding(.top, 20)
            
            // 显示当前选择的语速值
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 60, height: 60)
                
                Text("\(String(format: "%.1f", tempRate))x")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 10)
            
            // 语速滑块
            HStack {
                ForEach(availableRates, id: \.self) { rate in
                    VStack {
                        Circle()
                            .fill(tempRate == rate ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 15, height: 15)
                        
                        Text("\(String(format: "%.1f", rate))x")
                            .font(.caption)
                            .foregroundColor(tempRate == rate ? .red : .gray)
                    }
                    .onTapGesture {
                        tempRate = rate
                    }
                    
                    if rate != availableRates.last {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 滑块控件
            Slider(value: $tempRate, in: 0.5...4.0, step: 0.1)
                .accentColor(.red)
                .padding(.horizontal, 20)
            
            // 确认按钮
            Button("关闭") {
                // 更新选中的语速值
                selectedRate = tempRate
                // 保存设置
                UserDefaults.standard.set(selectedRate, forKey: UserDefaultsKeys.selectedRate)
                // 关闭弹窗
                showSpeedSelector = false
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 40)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .padding()
    }
}