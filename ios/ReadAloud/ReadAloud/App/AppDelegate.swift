//
//  AppDelegate.swift
//  ReadAloud
//
//  Created by moqian on 2025/4/24.
//

import UIKit
import SwiftUI
import StoreKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 将应用ID注册进IAP沙盒环境检测
        if #available(iOS 15.0, *) {
            if let receipt = Bundle.main.appStoreReceiptURL, let data = try? Data(contentsOf: receipt) {
                let receiptString = data.base64EncodedString()
                print("收据数据长度：\(receiptString.count)")
            }
            
            // 使用StoreKit 2.0 API检查产品环境
            Task {
                // StoreKit环境检测
                if #available(iOS 15.0, *) {
                    let isSandbox = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
                    print("应用IAP环境判断：\(isSandbox ? "沙盒测试环境" : "生产环境")")
                    
                    // 查看是否安装了StoreKit测试配置
                    let hasTestConfiguration = UserDefaults.standard.bool(forKey: "com.apple.configuration.managed.SKTestSessionConfiguration")
                    print("是否检测到StoreKit测试配置：\(hasTestConfiguration)")
                }
            }
        } else {
            // iOS 14及以下使用StoreKit 1.0
            print("使用StoreKit 1.0，不支持环境检测")
        }
        
        // 记录应用启动日志
        LogManager.shared.log("应用启动", level: .info, category: "应用生命周期")
        
        // 启动时恢复所有交易
        print("应用启动，开始恢复订阅和购买次数")
        Task {
            // 延迟一小段时间启动恢复，确保其他初始化已完成
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 延迟1秒
            
            // 在主线程执行恢复操作
            await MainActor.run {
                StoreKitManager.shared.restoreTransactionsAtLaunch { success in
                    if success {
                        print("启动时恢复交易成功")
                        LogManager.shared.log("启动时恢复交易成功", level: .info, category: "StoreKit")
                    } else {
                        print("启动时恢复交易未成功完成")
                        LogManager.shared.log("启动时恢复交易未成功完成", level: .warning, category: "StoreKit")
                    }
                }
            }
        }
        
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