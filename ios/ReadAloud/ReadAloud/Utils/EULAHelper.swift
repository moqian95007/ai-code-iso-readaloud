import Foundation

/// 帮助类，提供访问EULA的功能
struct EULAHelper {
    /// 获取苹果标准EULA的URL
    static var standardAppleEULAURL: URL {
        return URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }
    
    /// 获取苹果标准EULA的URL字符串
    static var standardAppleEULAURLString: String {
        return "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    }
} 