import Foundation
import SwiftUI

/// 管理文章列表分类的类
class ArticleListManager: ObservableObject {
    @Published var lists: [ArticleList] = []
    @Published var selectedListId: UUID? = nil
    
    private let saveKey = "savedArticleLists"
    private let selectedListKey = "selectedArticleList"
    
    init() {
        loadLists()
        // 如果没有列表，创建一个默认的"所有文章"列表
        if lists.isEmpty {
            addList(name: "所有文章")
        }
        
        // 加载上次选择的列表
        if let savedSelectedId = UserDefaults.standard.string(forKey: selectedListKey),
           let selectedId = UUID(uuidString: savedSelectedId) {
            selectedListId = selectedId
        } else {
            // 如果没有保存选择，使用第一个列表
            selectedListId = lists.first?.id
        }
    }
    
    // 从本地存储加载文章列表
    func loadLists() {
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            if let decoded = try? JSONDecoder().decode([ArticleList].self, from: data) {
                self.lists = decoded
                return
            }
        }
        // 如果没有数据或解码失败，使用空数组
        self.lists = []
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
    func addList(name: String) {
        let newList = ArticleList(name: name)
        lists.append(newList)
        
        // 如果这是第一个列表，自动选择它
        if lists.count == 1 {
            selectedListId = newList.id
        }
        
        saveLists()
    }
    
    // 更新列表
    func updateList(id: UUID, name: String) {
        if let index = lists.firstIndex(where: { $0.id == id }) {
            lists[index].name = name
            saveLists()
        }
    }
    
    // 删除列表
    func deleteList(at indexSet: IndexSet) {
        // 防止删除最后一个列表
        if lists.count <= 1 {
            return
        }
        
        let idsToDelete = indexSet.map { lists[$0].id }
        lists.remove(atOffsets: indexSet)
        
        // 如果删除了当前选中的列表，切换到第一个列表
        if let selectedId = selectedListId, idsToDelete.contains(selectedId) {
            selectedListId = lists.first?.id
        }
        
        saveLists()
    }
    
    // 将文章添加到列表
    func addArticleToList(articleId: UUID, listId: UUID) {
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
} 