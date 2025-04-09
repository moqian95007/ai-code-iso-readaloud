import Foundation
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

class DocumentManager: ObservableObject {
    // 支持的文档类型
    static let supportedTypes: [UTType] = [
        .plainText,      // txt
        .pdf,            // pdf
        .rtf,            // rtf
        .epub,           // epub
        UTType(filenameExtension: "mobi") ?? .data // mobi
    ]
    
    @Published var documentLibrary: DocumentLibraryManager
    
    init(documentLibrary: DocumentLibraryManager) {
        self.documentLibrary = documentLibrary
        print("DocumentManager 初始化成功")
    }
    
    // 处理导入的文档
    func importDocument(url: URL) -> Bool {
        do {
            print("开始导入文档: \(url.lastPathComponent)")
            
            // 根据文件类型进行处理
            let fileType = try url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
            print("文件类型: \(fileType ?? "未知")")
            
            var content: String
            var title = url.lastPathComponent
            var actualFileType = "txt" // 默认文件类型
            
            // 读取文件内容
            if let type = fileType {
                switch type {
                case "public.plain-text", "public.text":
                    // TXT文件
                    content = try importTextFile(url: url)
                    actualFileType = "txt"
                    
                case "com.adobe.pdf", "public.pdf":
                    // PDF文件
                    content = try importPDFFile(url: url)
                    actualFileType = "pdf"
                    
                case "public.rtf", "com.apple.rtf", "com.apple.rtfd":
                    // RTF文件
                    content = try importRTFFile(url: url)
                    actualFileType = "rtf"
                    
                case "org.idpf.epub-container", "com.apple.ibooks.epub":
                    // EPUB文件
                    content = try importEPUBFile(url: url)
                    actualFileType = "epub"
                    
                default:
                    if type.contains("mobi") {
                        // MOBI文件
                        content = try importMOBIFile(url: url)
                        actualFileType = "mobi"
                    } else {
                        // 尝试作为文本文件处理
                        content = try importTextFile(url: url)
                        actualFileType = "txt"
                    }
                }
            } else {
                // 尝试作为文本文件处理
                content = try importTextFile(url: url)
                actualFileType = "txt"
            }
            
            // 安全检查：确保内容非空
            if content.isEmpty {
                content = "（导入的文档内容为空）"
            }
            
            // 提取文件名作为标题
            let fileNameWithoutExtension = url.deletingPathExtension().lastPathComponent
            print("文件名: \(fileNameWithoutExtension)")
            
            // 第一阶段：在主线程上快速添加文档到库中，确保UI可以立即更新
            let newDocument = Document(
                title: fileNameWithoutExtension,
                content: content,
                fileType: actualFileType,
                createdAt: Date()
            )
            
            DispatchQueue.main.async {
                // 添加文档到数组（不调用saveDocuments以避免额外开销）
                self.documentLibrary.documents.append(newDocument)
                
                // 立即通知UI更新
                self.documentLibrary.refreshDocumentList()
                print("第一阶段：文档已添加到库中并通知UI刷新")
                
                // 第二阶段：在后台处理保存和章节识别等耗时操作
                DispatchQueue.global(qos: .userInitiated).async {
                    // 读取数据并准备信息（此处不修改任何发布属性）
                    // 保存到UserDefaults - 这需要移到主线程
                    DispatchQueue.main.async {
                        self.documentLibrary.saveDocuments()
                        print("第二阶段：保存文档到UserDefaults完成")
                    }
                    
                    print("获取到最新添加的文档: \(newDocument.title), ID=\(newDocument.id.uuidString)")
                    
                    // 添加文档的章节识别功能
                    DispatchQueue.global(qos: .userInitiated).async {
                        print("开始识别文档章节: \(newDocument.title)")
                        let chapterManager = ChapterManager()
                        let chapters = chapterManager.identifyChapters(for: newDocument)
                        print("文档章节识别完成")
                        
                        // 标记文档为已处理 - 通知必须在主线程发送
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: Notification.Name("DocumentChapterProcessingCompleted"),
                                object: nil,
                                userInfo: ["documentId": newDocument.id]
                            )
                        }
                    }
                }
            }
            
            return true
        } catch {
            print("导入文档失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // 导入文本文件
    private func importTextFile(url: URL) throws -> String {
        // 尝试常见的编码类型
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .ascii,
            .isoLatin1,
            .isoLatin2,
            .macOSRoman,
            .windowsCP1250,
            .windowsCP1251,
            .windowsCP1252,
            .japaneseEUC,
            .iso2022JP
        ]
        
        for encoding in encodings {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                print("成功使用\(encoding)编码读取文本")
                return text
            }
        }
        
        // 如果所有尝试都失败，尝试直接读取数据
        if let data = try? Data(contentsOf: url) {
            // 尝试UTF-8
            if let text = String(data: data, encoding: .utf8) {
                print("成功使用Data+UTF8方法读取文本")
                return text
            }
            
            // 返回前200个字节的十六进制表示（用于调试）
            let previewSize = min(200, data.count)
            let hexPreview = data.prefix(previewSize).map { String(format: "%02hhx", $0) }.joined(separator: " ")
            print("文件前\(previewSize)字节: \(hexPreview)")
            
            // 创建一个基本的文本
            return "【文件导入提示】\n\n该文件内容无法正确识别编码。文件大小为\(data.count)字节。\n可能需要使用专用编辑器打开此文件。"
        }
        
        // 如果还是失败，抛出错误
        throw NSError(domain: "DocumentManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法识别文件编码"])
    }
    
    // 导入PDF文件
    private func importPDFFile(url: URL) throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw NSError(domain: "DocumentManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法打开PDF文件"])
        }
        
        print("PDF文件页数: \(pdfDocument.pageCount)")
        var fullText = ""
        
        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex),
               let pageText = page.string {
                fullText += "【第\(pageIndex+1)页】\n\n" + pageText + "\n\n"
            }
        }
        
        return fullText
    }
    
    // 导入RTF文件
    private func importRTFFile(url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else {
            throw NSError(domain: "DocumentManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法读取RTF文件数据"])
        }
        
        // 尝试作为RTF解析
        if let attributedString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            print("成功解析RTF文件")
            return attributedString.string
        }
        
        // 尝试作为HTML解析
        if let attributedString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            print("将RTF作为HTML解析成功")
            return attributedString.string
        }
        
        throw NSError(domain: "DocumentManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法解析RTF文件内容"])
    }
    
    // 导入EPUB文件
    private func importEPUBFile(url: URL) throws -> String {
        do {
            // 使用新的EBookParser解析EPUB文件
            print("开始使用EBookParser解析EPUB文件")
            let content = try EBookParser.parseEPUB(url: url)
            return content
        } catch {
            print("EPUB解析错误: \(error.localizedDescription)")
            
            // 返回错误信息
            return """
            【EPUB文件导入错误】
            
            文件名: \(url.lastPathComponent)
            
            无法解析此EPUB文件: \(error.localizedDescription)
            
            请确保文件格式正确，或尝试将EPUB转换为TXT或PDF格式后再导入。
            """
        }
    }
    
    // 导入MOBI文件
    private func importMOBIFile(url: URL) throws -> String {
        do {
            // 使用新的EBookParser解析MOBI文件
            print("开始使用EBookParser解析MOBI文件")
            let content = try EBookParser.parseMOBI(url: url)
            return content
        } catch {
            print("MOBI解析错误: \(error.localizedDescription)")
            
            // 返回错误信息
            return """
            【MOBI文件导入错误】
            
            文件名: \(url.lastPathComponent)
            
            无法解析此MOBI文件: \(error.localizedDescription)
            
            请确保文件格式正确，或尝试将MOBI转换为EPUB、TXT或PDF格式后再导入。
            """
        }
    }
}

// 文档选择器视图
struct DocumentPickerView: UIViewControllerRepresentable {
    @ObservedObject var documentManager: DocumentManager
    var completion: (Bool) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        print("创建文档选择器界面")
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: DocumentManager.supportedTypes)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
            super.init()
            print("文档选择器协调器初始化")
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            print("用户选择了文档")
            guard let url = urls.first else {
                print("没有选择任何文档")
                parent.completion(false)
                return
            }
            
            print("选择的文档路径: \(url.path)")
            
            // 获取文件的安全访问权限
            let success = url.startAccessingSecurityScopedResource()
            
            // 在同一线程处理文件导入，保持安全访问范围有效
            let result = parent.documentManager.importDocument(url: url)
            
            // 释放安全访问范围
            if success {
                url.stopAccessingSecurityScopedResource()
            }
            
            print("文档导入结果: \(result ? "成功" : "失败")")
            parent.completion(result)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("用户取消了文档选择")
            parent.completion(false)
        }
    }
} 