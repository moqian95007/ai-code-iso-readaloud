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
        
        // 检查是否在短时间内已经加载过
        let now = Date()
        let lastLoadKey = "lastDocLibraryLoadTime"
        if let lastLoadTime = UserDefaults.standard.object(forKey: lastLoadKey) as? Date {
            let timeSinceLastLoad = now.timeIntervalSince(lastLoadTime)
            // 如果在最近1秒内已经加载过，跳过此次加载
            if timeSinceLastLoad < 1.0 {
                print("文档库在最近1秒内已加载过，跳过重复加载 (间隔: \(timeSinceLastLoad)秒)")
                return
            }
        }
        
        // 设置加载状态和时间戳
        isLoading = true
        UserDefaults.standard.set(now, forKey: lastLoadKey)
        
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
                    }
                }
                
                // 在主线程更新文档数组
                DispatchQueue.main.async {
                    self.documents = validDocuments
                    print("成功加载\(validDocuments.count)个有效文档")
                    
                    if needsSave {
                        // 如果存在空文档并已过滤，重新保存
                        self.saveDocuments()
                    } else if !validDocuments.isEmpty {
                        // 只有在不需要重新保存且有文档时，才执行ArticleList检查
                        // 这里直接调用saveDocuments方法，它现在包含了ArticleList的创建和更新逻辑
                        self.saveDocuments()
                    }
                    
                    // 通知观察者文档集合已更改
                    self.objectWillChange.send()
                    
                    // 发送文档库加载完成通知
                    NotificationCenter.default.post(
                        name: Notification.Name("DocumentLibraryLoaded"),
                        object: nil
                    )
                    
                    // 最后重置加载状态
                    self.isLoading = false
                }
                
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
            
            // 发送文档库加载完成通知
            NotificationCenter.default.post(
                name: Notification.Name("DocumentLibraryLoaded"),
                object: nil
            )
            
            // 重置加载状态
            self.isLoading = false
        }
    }
    
    // 保存文档到本地存储
    func saveDocuments() {
        // 准备要保存的数据
        var validDocuments: [Document] = []
        var needsValidation = false
        
        // 这部分在当前线程进行数据准备
        do {
            // 验证没有空内容文档
            validDocuments = documents.filter { !$0.content.isEmpty }
            needsValidation = validDocuments.count != documents.count
            
            // 编码数据可以在当前线程进行
            let encoded = try JSONEncoder().encode(validDocuments)
            
            // UserDefaults操作线程安全
            UserDefaults.standard.set(encoded, forKey: saveKey)
            
            // 接下来的所有可能修改ObservableObject的操作必须在主线程上
            DispatchQueue.main.async {
                if needsValidation {
                    print("警告: 过滤了 \(self.documents.count - validDocuments.count) 个空内容文档")
                    // 在主线程上更新文档列表
                    self.documents = validDocuments
                }
                
                // 只输出文档数量，避免过多日志
                print("保存了\(validDocuments.count)个文档")
                
                // 批量处理ArticleList关联，避免为每个文档单独输出日志
                let listManager = ArticleListManager.shared
                var createdCount = 0
                var updatedCount = 0
                
                for document in validDocuments {
                    // 检查ArticleListManager中是否有对应ID的列表
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
                        createdCount += 1
                    } else {
                        // 如果已有，更新列表信息
                        if let index = listManager.lists.firstIndex(where: { $0.id == document.id }) {
                            listManager.lists[index].name = document.title
                            listManager.lists[index].articleIds = document.chapterIds
                            updatedCount += 1
                        }
                    }
                }
                
                // 只保存一次ArticleList，减少IO操作
                if createdCount > 0 || updatedCount > 0 {
                    listManager.saveLists()
                    if createdCount > 0 {
                        print("为\(createdCount)个文档创建了对应的ArticleList")
                    }
                    if updatedCount > 0 {
                        print("更新了\(updatedCount)个文档对应的ArticleList")
                    }
                }
                
                // 通知观察者文档集合已更改
                self.objectWillChange.send()
            }
        } catch {
            print("编码文档时出错: \(error.localizedDescription)")
        }
    }
    
    // 用于兼容旧代码的方法
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
        
        // 创建新文档对象
        let newDocument = Document(
            title: title,
            content: content,
            fileType: fileType,
            createdAt: Date()
        )
        
        // 所有修改ObservableObject的操作在主线程执行
        DispatchQueue.main.async {
            // 添加到文档数组
            self.documents.append(newDocument)
            
            // 保存文档（saveDocuments方法已修改为在主线程更新）
            self.saveDocuments()
            
            // 显式通知观察者文档集合已更改
            self.objectWillChange.send()
            print("添加了新文档: \(title), 类型: \(fileType), 内容长度: \(content.count)")
        }
    }
    
    // 删除文档
    func deleteDocument(at indexSet: IndexSet) {
        // 获取要删除的文档ID
        let documentsToDelete = indexSet.map { self.documents[$0] }
        
        // 所有修改ObservableObject的操作在主线程执行
        DispatchQueue.main.async {
            // 从文档列表中移除
            self.documents.remove(atOffsets: indexSet)
            self.saveDocuments()
            
            // 从ArticleListManager中移除对应的列表
            let listManager = ArticleListManager.shared
            for document in documentsToDelete {
                if let index = listManager.lists.firstIndex(where: { $0.id == document.id }) {
                    listManager.lists.remove(at: index)
                }
            }
            listManager.saveLists()
            
            // 显式通知观察者文档集合已更改
            self.objectWillChange.send()
            print("删除了文档")
        }
    }
    
    // 更新文档进度
    func updateProgress(for id: UUID, progress: Double) {
        // 查找要更新的文档
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        // 所有修改ObservableObject的操作在主线程执行
        DispatchQueue.main.async {
            self.documents[index].progress = progress
            self.saveDocuments()
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
        
        // 查找要更新的文档
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else {
            return
        }
        
        // 所有修改ObservableObject的操作在主线程执行
        DispatchQueue.main.async {
            self.documents[index] = document
            self.saveDocuments()
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
    
    // 强制刷新文档列表视图
    func refreshDocumentList() {
        // 通知观察者文档集合已更改，强制UI刷新
        DispatchQueue.main.async {
            print("强制刷新文档列表视图")
            self.objectWillChange.send()
        }
    }
} 