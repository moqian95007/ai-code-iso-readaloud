import Foundation
import SwiftUI

// 管理文章数据的类
class ArticleManager: ObservableObject {
    // 单例模式，确保全局只有一个文章管理器实例
    static let shared = ArticleManager()
    
    @Published var articles: [Article] = []
    private let saveKey = "savedArticles"
    
    // 私有初始化方法，防止外部直接创建实例
    private init() {
        loadArticles()
    }
    
    // 从本地存储加载文章
    func loadArticles() {
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            if let decoded = try? JSONDecoder().decode([Article].self, from: data) {
                self.articles = decoded
                return
            }
        }
        // 如果没有数据或解码失败，使用空数组
        self.articles = []
    }
    
    // 保存文章到本地存储
    func saveArticles() {
        if let encoded = try? JSONEncoder().encode(articles) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    // 添加新文章
    func addArticle(title: String, content: String) {
        // 如果标题为空，使用"新文章"作为默认标题
        let articleTitle = title.isEmpty ? "新文章" : title
        let newArticle = Article(title: articleTitle, content: content, createdAt: Date())
        articles.append(newArticle)
        saveArticles()
    }
    
    // 添加新文章并返回创建的文章对象
    func addArticleAndReturn(title: String, content: String) -> Article? {
        // 如果标题为空，使用"新文章"作为默认标题
        let articleTitle = title.isEmpty ? "新文章" : title
        let newArticle = Article(title: articleTitle, content: content, createdAt: Date())
        articles.append(newArticle)
        saveArticles()
        return newArticle
    }
    
    // 删除文章
    func deleteArticle(at indexSet: IndexSet) {
        articles.remove(atOffsets: indexSet)
        saveArticles()
    }
    
    // 更新现有文章
    func updateArticle(id: UUID, title: String, content: String) {
        if let index = articles.firstIndex(where: { $0.id == id }) {
            // 如果标题为空，使用"新文章"作为默认标题
            let articleTitle = title.isEmpty ? "新文章" : title
            articles[index].title = articleTitle
            articles[index].content = content
            // 不更新创建时间
            saveArticles()
        }
    }
    
    // 根据ID查找文章
    func findArticle(by id: UUID) -> Article? {
        return articles.first { $0.id == id }
    }
} 