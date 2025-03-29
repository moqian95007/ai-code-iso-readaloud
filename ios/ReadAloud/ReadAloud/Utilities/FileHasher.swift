import Foundation
import CommonCrypto

struct FileHasher {
    enum HashError: Error {
        case fileNotFound
        case readingFailed
    }
    
    static func md5(of url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HashError.fileNotFound
        }
        
        do {
            let data = try Data(contentsOf: url)
            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            
            _ = data.withUnsafeBytes {
                CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
            }
            
            let hexString = digest.map { String(format: "%02hhx", $0) }.joined()
            return hexString
        } catch {
            throw HashError.readingFailed
        }
    }
} 