import SwiftUI

struct FloatingPlayerButton: View {
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    @ObservedObject private var navigationState = ReadAloudNavigationState.shared
    @State private var animationAmount = 1.0
    
    var body: some View {
        if playbackManager.currentDocument != nil && playbackManager.isPlaying {
            Button(action: {
                // 激活导航标志，触发导航
                navigationState.shouldNavigateToReader = true
            }) {
                // 增大浮动球并添加动态效果
                ZStack {
                    // 外层脉冲圆 - 增大波纹效果
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 70, height: 70)
                        .scaleEffect(animationAmount)
                        .opacity(2 - animationAmount)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: false),
                            value: animationAmount
                        )
                    
                    // 主背景圆
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 70, height: 70)
                    
                    // 动态音波图标
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
            .contentShape(Circle())
            .onAppear {
                // 启动动画 - 增大动画幅度
                animationAmount = 1.8
            }
        } else {
            EmptyView()
        }
    }
} 