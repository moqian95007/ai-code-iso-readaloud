import SwiftUI
import MessageUI

/// 开发者菜单视图
struct DeveloperMenuView: View {
    // 显示的日志级别
    @State private var selectedLogLevel: LogLevel? = nil
    
    // 是否显示分享表单
    @State private var isShowingShareSheet = false
    
    // 导出文件URL
    @State private var exportedFileURL: URL? = nil
    
    // 过滤后的日志列表
    private var filteredLogs: [LogEntry] {
        return LogManager.shared.getLogs(level: selectedLogLevel)
    }
    
    // 邮件功能检查
    @State private var isShowingMailView = false
    @State private var canSendMail = MFMailComposeViewController.canSendMail()
    
    var body: some View {
        NavigationView {
            VStack {
                // 日志过滤控件
                Picker("日志级别", selection: $selectedLogLevel) {
                    Text("全部").tag(nil as LogLevel?)
                    ForEach([LogLevel.debug, .info, .warning, .error, .critical], id: \.self) { level in
                        Text("\(level.emoji) \(level.rawValue)").tag(level as LogLevel?)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // 日志列表
                List {
                    ForEach(filteredLogs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.formattedTimestamp)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                Text("[\(entry.category)]")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                let logLevel = LogLevel(rawValue: entry.level) ?? .info
                                Text(logLevel.emoji)
                                
                                Text(entry.message)
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
                
                // 信息栏
                HStack {
                    Text("共\(filteredLogs.count)条日志")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("本地时间: \(formattedCurrentTime())")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("开发者日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: exportLogs) {
                            Label("导出日志", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: sendLogsByEmail) {
                            Label("通过邮件发送", systemImage: "envelope")
                        }
                        .disabled(!canSendMail)
                        
                        Button(action: {
                            LogManager.shared.clearLogs()
                        }) {
                            Label("清除日志", systemImage: "trash")
                        }
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $isShowingMailView) {
                if let url = exportedFileURL {
                    MailView(content: "", attachmentURL: url) { result in
                        isShowingMailView = false
                    }
                }
            }
        }
    }
    
    // 导出日志
    private func exportLogs() {
        if let fileURL = LogManager.shared.exportLogsToFile() {
            exportedFileURL = fileURL
            isShowingShareSheet = true
        }
    }
    
    // 通过邮件发送日志
    private func sendLogsByEmail() {
        if let fileURL = LogManager.shared.exportLogsToFile() {
            exportedFileURL = fileURL
            isShowingMailView = true
        }
    }
    
    // 格式化当前时间
    private func formattedCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

/// 分享表单
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 邮件视图
struct MailView: UIViewControllerRepresentable {
    var content: String
    var attachmentURL: URL?
    var completion: (Result<MFMailComposeResult, Error>) -> Void
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailComposer = MFMailComposeViewController()
        mailComposer.mailComposeDelegate = context.coordinator
        
        // 设置邮件内容
        mailComposer.setSubject("ReadAloud App日志")
        mailComposer.setMessageBody(content, isHTML: false)
        
        // 添加附件
        if let url = attachmentURL {
            if let data = try? Data(contentsOf: url) {
                mailComposer.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
            }
        }
        
        return mailComposer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var completion: (Result<MFMailComposeResult, Error>) -> Void
        
        init(completion: @escaping (Result<MFMailComposeResult, Error>) -> Void) {
            self.completion = completion
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(result))
            }
            controller.dismiss(animated: true)
        }
    }
}

struct DeveloperMenuView_Previews: PreviewProvider {
    static var previews: some View {
        DeveloperMenuView()
    }
} 