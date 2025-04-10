import SwiftUI
import UIKit

/// 支持拖拽和点击的进度条组件
struct SliderWithTapHandler: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onTap: (Double) -> Void = { _ in }
    var accentColor: Color = .blue
    
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.tintColor = UIColor(accentColor)
        
        // 添加点击手势识别器
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.sliderTapped(_:)))
        slider.addGestureRecognizer(tapGesture)
        
        // 设置值变化和拖动事件处理
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchUp(_:)), for: [.touchUpInside, .touchUpOutside])
        
        return slider
    }
    
    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.value = Float(value)
        uiView.tintColor = UIColor(accentColor)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: SliderWithTapHandler
        var isDragging = false
        
        init(_ parent: SliderWithTapHandler) {
            self.parent = parent
        }
        
        @objc func sliderTapped(_ gesture: UITapGestureRecognizer) {
            guard let slider = gesture.view as? UISlider else { return }
            
            // 点击位置转换为滑块值
            let point = gesture.location(in: slider)
            let width = slider.bounds.width
            let percent = point.x / width
            let newValue = Double(slider.minimumValue) + percent * Double(slider.maximumValue - slider.minimumValue)
            
            // 更新值并调用回调函数
            parent.value = newValue
            parent.onTap(newValue)
        }
        
        @objc func valueChanged(_ sender: UISlider) {
            parent.value = Double(sender.value)
        }
        
        @objc func touchDown(_ sender: UISlider) {
            isDragging = true
            parent.onEditingChanged(true)
        }
        
        @objc func touchUp(_ sender: UISlider) {
            isDragging = false
            parent.onEditingChanged(false)
        }
    }
} 