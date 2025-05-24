import Foundation

/// 日志级别
enum LogLevel: String {
    case debug = "调试"
    case info = "信息"
    case warning = "警告" 
    case error = "错误"
    case critical = "严重"
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
}

/// 日志条目
struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: String
    let message: String
    let category: String
    
    init(level: LogLevel, message: String, category: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level.rawValue
        self.message = message
        self.category = category
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    var formattedMessage: String {
        let levelEmoji = LogLevel(rawValue: level)?.emoji ?? "ℹ️"
        return "\(formattedTimestamp) \(levelEmoji) [\(category)] \(message)"
    }
}

/// 日志管理器
class LogManager {
    // 单例模式
    static let shared = LogManager()
    
    // 最大日志条数
    private let maxLogEntries = 5000
    
    // 日志存储
    private var logs: [LogEntry] = []
    
    // 文件管理器
    private let fileManager = FileManager.default
    
    // 日志文件URL
    private var logFileURL: URL? {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("app_logs.json")
    }
    
    // 开发者日志文件URL
    private var devLogFileURL: URL? {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("dev_logs.txt")
    }
    
    // 私有初始化方法
    private init() {
        loadLogsFromDisk()
        // 创建或清空开发者日志文件
        createOrClearDevLog()
    }
    
    // 创建或清空开发者日志文件
    private func createOrClearDevLog() {
        guard let fileURL = devLogFileURL else { return }
        
        do {
            // 如果文件已存在，清空内容
            if fileManager.fileExists(atPath: fileURL.path) {
                try "".write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                // 创建新文件
                try "开发者日志开始记录时间: \(Date())\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            print("🔄 开发者日志文件已准备就绪: \(fileURL.path)")
        } catch {
            print("❌ 创建或清空开发者日志文件失败: \(error.localizedDescription)")
        }
    }
    
    /// 设置日志系统
    static func setup() {
        // 覆盖print函数进行全局日志捕获
        // 这里只初始化单例实例
        _ = LogManager.shared
        
        print("日志系统已初始化")
    }
    
    /// 记录日志
    /// - Parameters:
    ///   - message: 日志消息
    ///   - level: 日志级别
    ///   - category: 日志类别
    func log(_ message: String, level: LogLevel = .info, category: String = "App") {
        let entry = LogEntry(level: level, message: message, category: category)
        
        // 添加到内存中
        logs.append(entry)
        
        // 如果超过最大数量，移除最旧的
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
        
        // 在控制台打印
        print("\(level.emoji) \(entry.formattedMessage)")
        
        // 写入开发者日志文件
        appendToDevLog("\(entry.formattedTimestamp) \(level.emoji) [\(category)] \(message)")
        
        // 定期保存到磁盘 (每10条日志保存一次)
        if logs.count % 10 == 0 {
            saveToDisk()
        }
    }
    
    /// 记录内购相关日志（特殊处理，便于排查）
    /// - Parameters:
    ///   - message: 日志消息
    ///   - level: 日志级别
    ///   - details: 详细信息（如果有）
    func logIAP(_ message: String, level: LogLevel = .info, details: String? = nil) {
        // 记录标准日志
        log(message, level: level, category: "内购")
        
        // 构建详细日志文本
        var detailText = "[\(Date())] [\(level.rawValue)] \(message)"
        if let details = details {
            // 如果详情非常长，截断以防止UserDefaults存储过大
            let maxDetailsLength = 1000
            let truncatedDetails = details.count > maxDetailsLength 
                ? details.prefix(maxDetailsLength) + "... (截断了\(details.count - maxDetailsLength)个字符)"
                : details
            detailText += "\n详情: \(truncatedDetails)"
        }
        detailText += "\n------------------------\n"
        
        // 写入开发者日志文件
        appendToDevLog(detailText)
    }
    
    /// 将文本追加到开发者日志文件
    private func appendToDevLog(_ text: String) {
        guard let fileURL = devLogFileURL else { return }
        
        do {
            // 获取文件句柄
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            
            // 移动到文件末尾
            fileHandle.seekToEndOfFile()
            
            // 写入新内容
            if let data = "\(text)\n".data(using: .utf8) {
                fileHandle.write(data)
            }
            
            // 关闭文件
            fileHandle.closeFile()
        } catch {
            print("❌ 追加开发者日志失败: \(error.localizedDescription)")
        }
    }
    
    /// 清空日志
    func clearLogs() {
        logs.removeAll()
        saveToDisk()
    }
    
    /// 获取所有日志
    func getAllLogs() -> [LogEntry] {
        return logs
    }
    
    /// 获取指定级别的日志
    func getLogs(level: LogLevel? = nil) -> [LogEntry] {
        if let level = level {
            return logs.filter { $0.level == level.rawValue }
        }
        return logs
    }
    
    /// 导出日志内容为字符串
    func exportLogsAsString() -> String {
        return logs.map { $0.formattedMessage }.joined(separator: "\n")
    }
    
    /// 导出日志到文件并返回文件URL
    func exportLogsToFile() -> URL? {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        
        let exportFileURL = documentsDirectory.appendingPathComponent("ReadAloud_logs_\(dateString).txt")
        
        do {
            let logsString = exportLogsAsString()
            try logsString.write(to: exportFileURL, atomically: true, encoding: .utf8)
            return exportFileURL
        } catch {
            log("导出日志失败: \(error.localizedDescription)", level: .error, category: "LogManager")
            return nil
        }
    }
    
    /// 获取开发者日志文件URL
    func getDevLogFileURL() -> URL? {
        return devLogFileURL
    }
    
    /// 保存日志到磁盘
    private func saveToDisk() {
        guard let fileURL = logFileURL else { return }
        
        // 如果日志数量超过限制，只保留最新的
        let logsToSave = logs.count > maxLogEntries ? Array(logs.suffix(maxLogEntries)) : logs
        
        do {
            let jsonEncoder = JSONEncoder()
            let jsonData = try jsonEncoder.encode(logsToSave)
            
            // 检查日志大小，如果超过2MB，清理旧日志
            if jsonData.count > 2 * 1024 * 1024 {
                print("⚠️ 日志数据过大(\(jsonData.count / 1024)KB)，只保留最新的500条记录")
                if logsToSave.count > 500 {
                    let truncatedLogs = Array(logsToSave.suffix(500))
                    let truncatedData = try jsonEncoder.encode(truncatedLogs)
                    try truncatedData.write(to: fileURL)
                    logs = truncatedLogs
                    return
                }
            }
            
            try jsonData.write(to: fileURL)
        } catch {
            print("❌ 保存日志到磁盘失败: \(error.localizedDescription)")
        }
    }
    
    /// 从磁盘加载日志
    private func loadLogsFromDisk() {
        guard let fileURL = logFileURL,
              fileManager.fileExists(atPath: fileURL.path) else { return }
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let jsonDecoder = JSONDecoder()
            logs = try jsonDecoder.decode([LogEntry].self, from: jsonData)
        } catch {
            print("❌ 从磁盘加载日志失败: \(error.localizedDescription)")
        }
    }
} 