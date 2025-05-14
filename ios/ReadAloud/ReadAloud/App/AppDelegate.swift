//
//  AppDelegate.swift
//  ReadAloud
//
//  Created by moqian on 2025/4/24.
//

import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    // 实现URL回调处理方法
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // 处理Google登录回调
        if url.scheme == "top.ai-toolkit.ReadAloud" {
            // 检查URL是否是Google OAuth回调
            if url.absoluteString.contains("oauth2callback") {
                // 将URL传递给GoogleSignInHandler处理
                GoogleSignInHandler.shared.handleRedirectURL(url)
                return true
            }
        }
        return false
    }
} 