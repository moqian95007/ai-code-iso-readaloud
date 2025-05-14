import Foundation
import SwiftUI
import Combine

// 管理文章数据的类
class ArticleManager: ObservableObject, ArticleManaging {
    // 移除单例模式
    // static let shared = ArticleManager()
    
    @Published var articles: [Article] = []
    private let saveKey = "savedArticles"
    private let listManager: ArticleListManaging
    
    // 用于存储订阅
    private var cancellables = Set<AnyCancellable>()
    
    // 修改初始化方法，接受依赖注入
    init(listManager: ArticleListManaging = ArticleListManager.shared) {
        self.listManager = listManager
        loadArticles()
        
        // 订阅ReloadArticlesData通知
        NotificationCenter.default.publisher(for: Notification.Name("ReloadArticlesData"))
            .sink { [weak self] _ in
                print("ArticleManager收到ReloadArticlesData通知，重新加载文章数据")
                self?.loadArticles()
            }
            .store(in: &cancellables)
    }
    
    // 从本地存储加载文章
    func loadArticles() {
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            if let decoded = try? JSONDecoder().decode([Article].self, from: data) {
                self.articles = decoded
                print("成功从本地加载\(decoded.count)篇文章")
                return
            }
        }
        // 如果没有数据或解码失败，使用空数组
        self.articles = []
        print("本地没有文章数据或解码失败，使用空数组")
    }
    
    // 保存文章到本地存储
    func saveArticles() {
        if let encoded = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    // 添加新文章
    func addArticle(title: String, content: String, listId: UUID? = nil) -> Article {
        // 如果标题为空，使用"新文章"作为默认标题
        let articleTitle = title.isEmpty ? "新文章" : title
        let newArticle = Article(title: articleTitle, content: content, createdAt: Date(), listId: listId)
        articles.append(newArticle)
        
        // 如果提供了列表ID，将文章添加到列表中
        if let listId = listId {
            listManager.addArticleToList(articleId: newArticle.id, listId: listId)
        }
        
        saveArticles()
        return newArticle
    }
    
    // 删除文章
    func deleteArticle(at indexSet: IndexSet) {
        // 从所有列表中移除这些文章
        for index in indexSet {
            let article = articles[index]
            
            // 先从文章可能所属的列表中移除
            if let listId = article.listId {
                listManager.removeArticleFromList(articleId: article.id, listId: listId)
            }
            
            // 同时从所有可能包含该文章的列表中移除
            for list in listManager.lists {
                if list.articleIds.contains(article.id) {
                    listManager.removeArticleFromList(articleId: article.id, listId: list.id)
                }
            }
        }
        
        articles.remove(atOffsets: indexSet)
        saveArticles()
    }
    
    // 更新现有文章
    func updateArticle(_ article: Article) {
        if let index = articles.firstIndex(where: { $0.id == article.id }) {
            // 保存原来的列表ID
            let oldListId = articles[index].listId
            
            // 更新文章内容
            articles[index] = article
            
            // 处理列表更改
            if oldListId != article.listId {
                // 如果原来有列表，从原列表中移除
                if let oldId = oldListId {
                    listManager.removeArticleFromList(articleId: article.id, listId: oldId)
                }
                
                // 如果新指定了列表，添加到新列表
                if let newId = article.listId {
                    listManager.addArticleToList(articleId: article.id, listId: newId)
                }
            }
            
            saveArticles()
        }
    }
    
    // 根据ID查找文章
    func findArticle(by id: UUID) -> Article? {
        return articles.first { $0.id == id }
    }
    
    // 获取指定列表中的所有文章
    func articlesInList(listId: UUID) -> [Article] {
        return articles.filter { $0.listId == listId || listManager.isArticleInList(articleId: $0.id, listId: listId) }
    }
} 