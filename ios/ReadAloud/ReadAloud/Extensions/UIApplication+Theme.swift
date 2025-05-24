import UIKit
import SwiftUI

extension UIApplication {
    /// 更新应用主题外观设置
    /// - Parameter colorScheme: 颜色方案(深色或浅色模式)
    static func updateTheme(with colorScheme: ColorScheme) {
        let isDarkMode = colorScheme == .dark
        
        // 设置状态栏样式
        if #available(iOS 15.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.windows.forEach { window in
                window.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
            }
        } else {
            UIApplication.shared.windows.forEach { window in
                window.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
            }
        }
        
        // 设置导航栏外观
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        }
        
        // 设置TabBar外观
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
        
        // 记录日志
        LogManager.shared.log("应用主题已更新: \(isDarkMode ? "深色模式" : "浅色模式")", level: .info, category: "主题")
    }
} 