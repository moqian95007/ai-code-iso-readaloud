//
//  GoogleSignInHandler.swift
//  ReadAloud
//
//  Created by moqian on 2025/4/24.
//

import Foundation
import UIKit
import AuthenticationServices

/// 处理Google登录的类，使用ASWebAuthenticationSession进行安全的OAuth流程
class GoogleSignInHandler: NSObject {
    // 单例实例
    static let shared = GoogleSignInHandler()
    
    // 成功和失败的回调
    private var onSuccess: ((String, String, String) -> Void)?
    private var onError: ((String) -> Void)?
    
    // 认证会话
    private var authSession: ASWebAuthenticationSession?
    
    // Google认证相关常量
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    let redirectURI = "top.ai-toolkit.ReadAloud:/oauth2callback"
    private let clientID = "288107963117-ou7rmervp8r9ajm6p0uedte2pnkku69h.apps.googleusercontent.com"
    private let scope = "email profile"
    
    // 私有初始化方法
    private override init() {
        super.init()
    }
    
    /// 开始Google登录流程
    /// - Parameters:
    ///   - onSuccess: 成功回调，返回(idToken, email, name)
    ///   - onError: 失败回调，返回错误信息
    func startSignInWithGoogleFlow(onSuccess: @escaping (String, String, String) -> Void,
                                   onError: @escaping (String) -> Void) {
        self.onSuccess = onSuccess
        self.onError = onError
        
        // 创建授权URL
        guard let authURL = buildAuthorizationURL() else {
            onError("无法创建授权URL")
            return
        }
        
        // 创建认证会话
        let authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "top.ai-toolkit.ReadAloud",
            completionHandler: { [weak self] callbackURL, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("认证会话错误: \(error.localizedDescription)")
                    if let authError = error as? ASWebAuthenticationSessionError {
                        switch authError.code {
                        case .canceledLogin:
                            self.onError?("用户取消了登录")
                        default:
                            self.onError?("认证错误: \(error.localizedDescription)")
                        }
                    } else {
                        self.onError?("认证错误: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    self.onError?("未收到回调URL")
                    return
                }
                
                self.handleRedirectURL(callbackURL)
            }
        )
        
        // 设置表现锚点
        if #available(iOS 13.0, *) {
            authSession.presentationContextProvider = self
        }
        
        // 开始认证会话
        authSession.start()
        
        // 保存引用以避免过早释放
        self.authSession = authSession
    }
    
    /// 构建授权URL
    private func buildAuthorizationURL() -> URL? {
        // 创建URL参数
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "access_type", value: "offline")
        ]
        
        return components?.url
    }
    
    /// 处理重定向URL
    /// - Parameter url: 重定向URL
    func handleRedirectURL(_ url: URL) {
        print("处理重定向URL: \(url)")
        
        // 从URL中提取授权码
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            onError?("无效的重定向URL")
            return
        }
        
        // 获取授权码
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            // 如果没有授权码，检查是否有错误
            if let errorMessage = components.queryItems?.first(where: { $0.name == "error" })?.value {
                onError?("Google登录错误: \(errorMessage)")
            } else {
                onError?("无法获取授权码")
            }
            return
        }
        
        // 使用授权码生成用户名，类似Apple登录
        let userName = "GoogleUser_\(code.prefix(5))"
        // 不传递邮箱，与Apple登录保持一致
        let email = ""
        
        print("Google登录成功，获取到授权码，生成用户名: \(userName)")
        onSuccess?(code, email, userName)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

@available(iOS 13.0, *)
extension GoogleSignInHandler: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 获取当前窗口
        guard let window = UIApplication.shared.windows.first else {
            // 如果没有窗口，则创建一个新窗口（这种情况几乎不会发生）
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.makeKeyAndVisible()
            return window
        }
        return window
    }
} 