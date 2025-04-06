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
            
            if let fileTypeString = fileType {
                let documentText: String
                let fileExtension: String
                
                // 处理不同格式的文档
                if fileTypeString == UTType.plainText.identifier {
                    // 处理纯文本文件
                    print("处理TXT文件")
                    documentText = try importTextFile(url: url)
                    fileExtension = "txt"
                } else if fileTypeString == UTType.pdf.identifier {
                    // 处理PDF文件
                    print("处理PDF文件")
                    documentText = try importPDFFile(url: url)
                    fileExtension = "pdf"
                } else if fileTypeString == UTType.rtf.identifier {
                    // 处理RTF文件
                    print("处理RTF文件")
                    documentText = try importRTFFile(url: url)
                    fileExtension = "rtf"
                } else if fileTypeString == UTType.epub.identifier || fileTypeString == "org.idpf.epub-container" {
                    // 处理EPUB文件
                    print("处理EPUB文件")
                    documentText = try importEPUBFile(url: url)
                    fileExtension = "epub"
                } else if let mobiType = UTType(filenameExtension: "mobi")?.identifier, fileTypeString == mobiType {
                    // 处理MOBI文件
                    print("处理MOBI文件")
                    documentText = try importMOBIFile(url: url)
                    fileExtension = "mobi"
                } else {
                    print("不支持的文件类型: \(fileTypeString)")
                    throw NSError(domain: "DocumentManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "不支持的文件类型"])
                }
                
                // 提取文件名作为标题
                let fileNameWithoutExtension = url.deletingPathExtension().lastPathComponent
                print("文件名: \(fileNameWithoutExtension)")
                
                // 检查是否成功获取文本
                if documentText.isEmpty {
                    print("警告: 提取的文本内容为空")
                } else {
                    print("成功提取文本内容，长度: \(documentText.count)字符")
                }
                
                // 添加到文档库
                documentLibrary.addDocument(
                    title: fileNameWithoutExtension,
                    content: documentText,
                    fileType: fileExtension
                )
                
                print("文档已添加到文档库")
                
                // 直接刷新文档列表而不是发送通知
                DispatchQueue.main.async {
                    // 确保在添加后刷新文档列表，这样就能立即显示
                    print("导入成功后直接刷新文档列表")
                    self.documentLibrary.loadDocuments()
                }
                
                return true
            }
            return false
        } catch {
            print("文档导入错误: \(error.localizedDescription)")
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
    
    // 导入EPUB文件 (基础实现，可能需要第三方库扩展功能)
    private func importEPUBFile(url: URL) throws -> String {
        // 由于Swift标准库没有直接支持EPUB的解析，这里提供一个基础实现
        // 实际应用中可能需要引入第三方库如FolioReaderKit或自行解析EPUB文件
        
        // EPUB本质上是一个ZIP文件，包含HTML，CSS和其他资源
        // 这里简化处理，提示用户需要进一步处理
        return "【EPUB文件导入说明】\n\n文件名: \(url.lastPathComponent)\n\nEPUB文件导入支持正在开发中，暂时无法自动解析此文件内容。\n建议先将EPUB转换为TXT或PDF格式再导入。\n\n如果您继续使用此文件，应用将只显示此提示信息而非实际内容。"
    }
    
    // 导入MOBI文件 (同样需要第三方库)
    private func importMOBIFile(url: URL) throws -> String {
        // MOBI格式更复杂，同样需要专门的解析库
        return "【MOBI文件导入说明】\n\n文件名: \(url.lastPathComponent)\n\nMOBI文件导入支持正在开发中，暂时无法自动解析此文件内容。\n建议先将MOBI转换为TXT或PDF格式再导入。\n\n如果您继续使用此文件，应用将只显示此提示信息而非实际内容。"
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
            
            // 先获取文件的访问权限
            let success = url.startAccessingSecurityScopedResource()
            defer {
                if success {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // 导入文档
            let result = parent.documentManager.importDocument(url: url)
            print("文档导入结果: \(result ? "成功" : "失败")")
            parent.completion(result)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("用户取消了文档选择")
            parent.completion(false)
        }
    }
} 