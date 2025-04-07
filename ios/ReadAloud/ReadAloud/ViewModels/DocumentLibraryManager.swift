import Foundation
import SwiftUI

class DocumentLibraryManager: ObservableObject {
    // 单例模式，确保整个应用只有一个文档库实例
    static let shared = DocumentLibraryManager()
    
    @Published var documents: [Document] = []
    private let saveKey = "savedDocuments"
    private var isLoading = false
    
    // 私有初始化方法，防止外部直接创建实例
    private init() {
        loadDocuments()
    }
    
    // 从本地存储加载文档
    func loadDocuments() {
        // 防止重复加载
        if isLoading {
            print("文档库正在加载中，跳过重复加载")
            return
        }
        
        isLoading = true
        print("开始加载文档库...")
        
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            do {
                let decoded = try JSONDecoder().decode([Document].self, from: data)
                
                // 验证文档内容
                var validDocuments: [Document] = []
                var needsSave = false
                
                for document in decoded {
                    if document.content.isEmpty {
                        print("警告: 文档 '\(document.title)' (ID: \(document.id)) 内容为空，跳过")
                        needsSave = true
                    } else {
                        print("文档 '\(document.title)' 内容长度: \(document.content.count)")
                        validDocuments.append(document)
                        
                        // 确保该文档在ArticleListManager中有对应的记录
                        ensureDocumentInListManager(document)
                    }
                }
                
                // 在主线程更新文档数组
                DispatchQueue.main.async {
                    self.documents = validDocuments
                    print("成功加载\(validDocuments.count)个有效文档")
                    
                    if needsSave {
                        // 如果存在空文档并已过滤，重新保存
                        self.saveDocuments()
                    }
                    
                    // 通知观察者文档集合已更改
                    self.objectWillChange.send()
                }
                
                isLoading = false
                return
            } catch {
                print("解码文档时出错: \(error.localizedDescription)")
            }
        }
        
        // 如果没有数据或解码失败，使用空数组
        DispatchQueue.main.async {
            self.documents = []
            print("没有找到保存的文档或解码失败")
            // 通知观察者文档集合已更改
            self.objectWillChange.send()
        }
        isLoading = false
    }
    
    // 保存文档到本地存储
    func saveDocuments() {
        do {
            // 验证没有空内容文档
            let validDocuments = documents.filter { !$0.content.isEmpty }
            if validDocuments.count != documents.count {
                print("警告: 过滤了 \(documents.count - validDocuments.count) 个空内容文档")
                self.documents = validDocuments
            }
            
            let encoded = try JSONEncoder().encode(documents)
            UserDefaults.standard.set(encoded, forKey: saveKey)
            print("保存了\(documents.count)个文档")
            
            // 确保所有文档在ArticleListManager中有对应的记录
            for document in documents {
                ensureDocumentInListManager(document)
            }
        } catch {
            print("编码文档时出错: \(error.localizedDescription)")
        }
    }
    
    // 确保文档在ArticleListManager中有对应的列表
    private func ensureDocumentInListManager(_ document: Document) {
        // 检查ArticleListManager中是否有对应ID的列表
        let listManager = ArticleListManager.shared
        if !listManager.lists.contains(where: { $0.id == document.id }) {
            // 如果没有，创建一个新的列表
            let newList = ArticleList(
                id: document.id,
                name: document.title,
                createdAt: document.createdAt,
                articleIds: document.chapterIds,
                isDocument: true
            )
            
            // 将新列表添加到ArticleListManager
            listManager.lists.append(newList)
            listManager.saveLists()
            print("为文档 '\(document.title)' 创建了对应的ArticleList")
        } else {
            // 如果已有，更新列表信息
            if let index = listManager.lists.firstIndex(where: { $0.id == document.id }) {
                listManager.lists[index].name = document.title
                listManager.lists[index].articleIds = document.chapterIds
                listManager.saveLists()
                print("更新了文档 '\(document.title)' 对应的ArticleList")
            }
        }
    }
    
    // 添加新文档
    func addDocument(title: String, content: String, fileType: String) {
        // 验证内容不为空
        guard !content.isEmpty else {
            print("错误: 尝试添加空内容文档，已拒绝")
            return
        }
        
        let newDocument = Document(
            title: title,
            content: content,
            fileType: fileType,
            createdAt: Date()
        )
        documents.append(newDocument)
        saveDocuments()
        
        // 确保新文档在ArticleListManager中有对应的列表
        ensureDocumentInListManager(newDocument)
        
        // 显式通知观察者文档集合已更改
        objectWillChange.send()
        print("添加了新文档: \(title), 类型: \(fileType), 内容长度: \(content.count)")
    }
    
    // 删除文档
    func deleteDocument(at indexSet: IndexSet) {
        // 获取要删除的文档ID
        let documentsToDelete = indexSet.map { self.documents[$0] }
        
        // 从文档列表中移除
        documents.remove(atOffsets: indexSet)
        saveDocuments()
        
        // 从ArticleListManager中移除对应的列表
        let listManager = ArticleListManager.shared
        for document in documentsToDelete {
            if let index = listManager.lists.firstIndex(where: { $0.id == document.id }) {
                listManager.lists.remove(at: index)
            }
        }
        listManager.saveLists()
        
        // 显式通知观察者文档集合已更改
        objectWillChange.send()
        print("删除了文档")
    }
    
    // 更新文档进度
    func updateProgress(for id: UUID, progress: Double) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].progress = progress
            saveDocuments()
            print("更新了文档进度: \(progress)")
        }
    }
    
    // 添加章节ID到文档
    func addChapterToDocument(documentId: UUID, chapterId: UUID) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            if !documents[index].chapterIds.contains(chapterId) {
                documents[index].chapterIds.append(chapterId)
                saveDocuments()
                
                // 同时更新ArticleListManager中的记录
                let listManager = ArticleListManager.shared
                if let listIndex = listManager.lists.firstIndex(where: { $0.id == documentId }) {
                    if !listManager.lists[listIndex].articleIds.contains(chapterId) {
                        listManager.lists[listIndex].articleIds.append(chapterId)
                        listManager.saveLists()
                    }
                }
            }
        }
    }
    
    // 更新文档
    func updateDocument(_ document: Document) {
        // 验证内容不为空
        guard !document.content.isEmpty else {
            print("错误: 尝试更新为空内容文档，已拒绝")
            return
        }
        
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
            saveDocuments()
            
            // 更新ArticleListManager中的对应记录
            ensureDocumentInListManager(document)
            
            print("更新了文档: \(document.title), 内容长度: \(document.content.count)")
        }
    }
    
    // 根据ID查找文档
    func findDocument(by id: UUID) -> Document? {
        let doc = documents.first { $0.id == id }
        if let document = doc {
            if document.content.isEmpty {
                print("警告: 找到的文档 '\(document.title)' 内容为空")
            } else {
                print("找到文档 '\(document.title)', 内容长度: \(document.content.count)")
            }
        }
        return doc
    }
} 