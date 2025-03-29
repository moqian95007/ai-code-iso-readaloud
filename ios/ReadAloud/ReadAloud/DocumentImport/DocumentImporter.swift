import SwiftUI
import UniformTypeIdentifiers

struct DocumentImporter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 支持的文档类型
        let supportedTypes: [UTType] = [
            .plainText,       // txt
            .epub,            // epub
            .pdf,             // pdf
            .data             // 支持其他类型如mobi等
        ]
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentImporter
        
        init(_ parent: DocumentImporter) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // 给文档授予安全访问权限
            let securityScoped = url.startAccessingSecurityScopedResource()
            
            do {
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fileName = url.lastPathComponent
                let destinationURL = documentsDirectory.appendingPathComponent(fileName)
                
                // 如果文件已存在，先删除
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                // 确保在复制完成后再调用回调
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                // 复制成功后再停止访问源文件
                if securityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
                
                // 调用回调
                parent.onDocumentPicked(destinationURL)
            } catch {
                print("导入文档失败: \(error.localizedDescription)")
                // 确保在出错时也停止访问源文件
                if securityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            parent.isPresented = false
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
} 