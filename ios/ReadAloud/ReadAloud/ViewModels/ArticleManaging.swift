import Foundation

/// 文章管理接口协议
protocol ArticleManaging {
    /// 获取所有文章
    var articles: [Article] { get }
    
    /// 添加新文章
    /// - Parameters:
    ///   - title: 文章标题
    ///   - content: 文章内容
    ///   - listId: 所属列表ID，可选
    /// - Returns: 新创建的文章
    func addArticle(title: String, content: String, listId: UUID?) -> Article
    
    /// 更新文章
    /// - Parameter article: 要更新的文章
    func updateArticle(_ article: Article)
    
    /// 删除文章
    /// - Parameter indexSet: 要删除的文章索引集合
    func deleteArticle(at indexSet: IndexSet)
    
    /// 根据ID查找文章
    /// - Parameter id: 文章ID
    /// - Returns: 找到的文章，如果不存在则返回nil
    func findArticle(by id: UUID) -> Article?
    
    /// 获取指定列表中的所有文章
    /// - Parameter listId: 列表ID
    /// - Returns: 属于该列表的所有文章
    func articlesInList(listId: UUID) -> [Article]
    
    /// 加载文章数据
    func loadArticles()
    
    /// 保存文章数据
    func saveArticles()
} 