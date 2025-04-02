import Foundation

/*
 后台音频播放配置指南
 
 为了让应用支持后台音频播放，需要在Xcode项目中进行以下配置：
 
 1. 打开项目的Target设置
 2. 选择"Signing & Capabilities"选项卡
 3. 点击"+ Capability"按钮
 4. 添加"Background Modes"功能
 5. 勾选"Audio, AirPlay, and Picture in Picture"选项
 
 或者直接在Info.plist中添加以下配置：
 
 <key>UIBackgroundModes</key>
 <array>
    <string>audio</string>
 </array>
 
 这将允许应用在后台继续播放音频，即使用户切换到其他应用或锁定屏幕。
 
 本文件仅作为配置说明，不包含实际代码。
 实际的后台音频处理逻辑已经在SpeechManager和ReadAloudApp中实现。
 */ 