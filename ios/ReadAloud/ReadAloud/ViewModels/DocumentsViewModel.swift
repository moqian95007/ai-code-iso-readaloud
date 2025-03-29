import Foundation
import Combine
import UIKit

class DocumentsViewModel: ObservableObject {
    @Published var documents: [Document] = []
    private var fileHashes: [String: UUID] = [:] // 存储文件哈希和对应的文档ID
    
    private let documentsKey = "savedDocuments"
    
    init() {
        loadDocuments()
    }
    
    func addDocument(from url: URL) throws -> String? {
        // 计算文件的MD5哈希值
        let fileHash: String
        do {
            fileHash = try FileHasher.md5(of: url)
        } catch {
            throw error
        }
        
        // 检查是否已存在相同内容的文件
        if let existingDocId = fileHashes[fileHash],
           let existingDoc = documents.first(where: { $0.id == existingDocId }) {
            return existingDoc.title // 返回重复文件的标题
        }
        
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension
        let fileType = DocumentType.fromFileExtension(fileExtension)
        
        // 从文件名中获取标题 (去掉扩展名)
        var title = fileName
        if let dotRange = fileName.lastIndex(of: ".") {
            title = String(fileName[..<dotRange])
        }
        
        do {
            // 提取封面
            let coverData = CoverExtractor.extractCover(from: url, fileType: fileType)
            
            var newDocument = Document(
                title: title,
                fileName: fileName,
                fileURL: url,
                fileType: fileType,
                fileHash: fileHash
            )
            newDocument.coverImageData = coverData
            
            // 添加文档并保存哈希值
            documents.append(newDocument)
            fileHashes[fileHash] = newDocument.id
            saveDocuments()
            
            return nil // 没有重复文件
        } catch {
            throw error
        }
    }
    
    func removeDocument(at indexSet: IndexSet) {
        for index in indexSet {
            let document = documents[index]
            do {
                try FileManager.default.removeItem(at: document.fileURL)
                // 同时删除哈希记录
                if let hash = document.fileHash {
                    fileHashes.removeValue(forKey: hash)
                }
            } catch {
                print("删除文件失败: \(error.localizedDescription)")
            }
        }
        
        documents.remove(atOffsets: indexSet)
        saveDocuments()
    }
    
    // 批量删除文档
    func removeDocuments(selected: Set<UUID>) {
        for id in selected {
            if let index = documents.firstIndex(where: { $0.id == id }) {
                let document = documents[index]
                do {
                    try FileManager.default.removeItem(at: document.fileURL)
                    // 同时删除哈希记录
                    if let hash = document.fileHash {
                        fileHashes.removeValue(forKey: hash)
                    }
                } catch {
                    print("删除文件失败: \(error.localizedDescription)")
                }
                
                documents.remove(at: index)
            }
        }
        saveDocuments()
    }
    
    func updateDocumentProgress(id: UUID, progress: Double) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].progress = progress
            documents[index].lastReadDate = Date()
            saveDocuments()
        }
    }
    
    private func saveDocuments() {
        if let encoded = try? JSONEncoder().encode(documents) {
            UserDefaults.standard.set(encoded, forKey: documentsKey)
        }
    }
    
    private func loadDocuments() {
        if let savedDocuments = UserDefaults.standard.data(forKey: documentsKey),
           let decodedDocuments = try? JSONDecoder().decode([Document].self, from: savedDocuments) {
            
            // 验证文件是否仍然存在
            var validDocuments: [Document] = []
            for document in decodedDocuments {
                if FileManager.default.fileExists(atPath: document.fileURL.path) {
                    print("找到有效文档: \(document.title), 路径: \(document.fileURL.path)")
                    validDocuments.append(document)
                } else {
                    print("文档文件不存在: \(document.title), 路径: \(document.fileURL.path)")
                }
            }
            
            documents = validDocuments
            
            // 重新构建哈希表
            fileHashes = [:]
            for document in documents {
                if let hash = document.fileHash {
                    fileHashes[hash] = document.id
                }
            }
            
            print("加载了\(documents.count)个有效文档")
        }
    }
} 