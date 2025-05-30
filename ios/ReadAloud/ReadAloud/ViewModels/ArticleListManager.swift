import Foundation
import SwiftUI
import Combine

/// 管理文章列表分类的类
class ArticleListManager: ObservableObject, ArticleListManaging {
    // 单例实例
    static let shared = ArticleListManager()
    
    @Published var lists: [ArticleList] = []
    @Published var selectedListId: UUID? = nil
    
    private let saveKey = "savedArticleLists"
    private let selectedListKey = "selectedArticleList"
    
    // 用于存储订阅
    private var cancellables = Set<AnyCancellable>()
    
    // 仅获取用户创建的列表（过滤掉文档创建的列表）
    var userLists: [ArticleList] {
        return lists.filter { !$0.isDocument }
    }
    
    // 私有初始化方法
    private init() {
        loadLists()
        // 如果没有列表，创建一个默认的"所有文章"列表
        if userLists.isEmpty {
            _ = addList(name: "所有文章", createdAt: Date())
        }
        
        // 加载上次选择的列表
        if let savedSelectedId = UserDefaults.standard.string(forKey: selectedListKey),
           let selectedId = UUID(uuidString: savedSelectedId) {
            // 确保选择的列表存在且不是文档列表
            if lists.contains(where: { $0.id == selectedId && !$0.isDocument }) {
                selectedListId = selectedId
            } else {
                // 如果选择的是文档列表或不存在，使用第一个用户列表
                selectedListId = userLists.first?.id
            }
        } else {
            // 如果没有保存选择，使用第一个用户列表
            selectedListId = userLists.first?.id
        }
        
        // 订阅ReloadArticlesData通知
        NotificationCenter.default.publisher(for: Notification.Name("ReloadArticlesData"))
            .sink { [weak self] _ in
                print("ArticleListManager收到ReloadArticlesData通知，重新加载列表数据")
                self?.loadLists()
            }
            .store(in: &cancellables)
    }
    
    // 从本地存储加载文章列表
    func loadLists() {
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            if let decoded = try? JSONDecoder().decode([ArticleList].self, from: data) {
                self.lists = decoded
                print("成功从本地加载\(decoded.count)个文章列表")
                return
            }
        }
        // 如果没有数据或解码失败，使用空数组
        self.lists = []
        print("本地没有列表数据或解码失败，使用空数组")
    }
    
    // 保存文章列表到本地存储
    func saveLists() {
        if let encoded = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
        
        // 保存当前选择的列表
        if let selectedId = selectedListId {
            UserDefaults.standard.set(selectedId.uuidString, forKey: selectedListKey)
        }
    }
    
    // 添加新列表
    func addList(name: String, createdAt: Date = Date()) -> ArticleList {
        let newList = ArticleList(id: UUID(), name: name, createdAt: createdAt, articleIds: [], isDocument: false)
        lists.append(newList)
        
        // 如果这是第一个用户列表，自动选择它
        if userLists.count == 1 {
            selectedListId = newList.id
        }
        
        saveLists()
        return newList
    }
    
    // 更新列表
    func updateList(_ list: ArticleList) {
        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            lists[index] = list
            saveLists()
        }
    }
    
    // 删除列表
    func deleteList(id: UUID) {
        // 防止删除最后一个用户列表
        if userLists.count <= 1 {
            return
        }
        
        // 从完整列表中移除
        if let index = lists.firstIndex(where: { $0.id == id }) {
            lists.remove(at: index)
        }
        
        // 如果删除了当前选中的列表，切换到第一个用户列表
        if selectedListId == id {
            selectedListId = userLists.first?.id
        }
        
        saveLists()
    }
    
    // 根据ID查找列表
    func findList(by id: UUID) -> ArticleList? {
        return lists.first { $0.id == id }
    }
    
    // 将文章添加到列表
    func addArticleToList(articleId: UUID, listId: UUID) {
        // 确保在主线程上执行UI更新操作
        if Thread.isMainThread {
            self.performAddArticleToList(articleId: articleId, listId: listId)
        } else {
            DispatchQueue.main.async {
                self.performAddArticleToList(articleId: articleId, listId: listId)
            }
        }
    }
    
    // 实际执行添加文章到列表的操作（在主线程上调用）
    private func performAddArticleToList(articleId: UUID, listId: UUID) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            // 确保不重复添加
            if !lists[index].articleIds.contains(articleId) {
                lists[index].articleIds.append(articleId)
                saveLists()
            }
        }
    }
    
    // 从列表中移除文章
    func removeArticleFromList(articleId: UUID, listId: UUID) {
        // 确保在主线程上执行UI更新操作
        if Thread.isMainThread {
            self.performRemoveArticleFromList(articleId: articleId, listId: listId)
        } else {
            DispatchQueue.main.async {
                self.performRemoveArticleFromList(articleId: articleId, listId: listId)
            }
        }
    }
    
    // 实际执行从列表中移除文章的操作（在主线程上调用）
    private func performRemoveArticleFromList(articleId: UUID, listId: UUID) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].articleIds.removeAll(where: { $0 == articleId })
            saveLists()
        }
    }
    
    // 获取当前选择的列表
    var selectedList: ArticleList? {
        guard let selectedId = selectedListId else { return nil }
        return lists.first(where: { $0.id == selectedId })
    }
    
    // 检查文章是否在列表中
    func isArticleInList(articleId: UUID, listId: UUID) -> Bool {
        guard let list = lists.first(where: { $0.id == listId }) else { return false }
        return list.articleIds.contains(articleId)
    }
    
    // 获取包含指定文章的所有列表
    func listsContainingArticle(articleId: UUID) -> [ArticleList] {
        return lists.filter { $0.articleIds.contains(articleId) }
    }
    
    // 获取包含指定文章的用户列表（过滤掉文档列表）
    func userListsContainingArticle(articleId: UUID) -> [ArticleList] {
        return lists.filter { !$0.isDocument && $0.articleIds.contains(articleId) }
    }
} 