import Foundation

/// 文章列表管理接口协议
protocol ArticleListManaging {
    /// 获取所有列表
    var lists: [ArticleList] { get }
    
    /// 获取当前选中的列表
    var selectedList: ArticleList? { get }
    
    /// 获取当前选中的列表ID
    var selectedListId: UUID? { get set }
    
    /// 获取用户创建的列表
    var userLists: [ArticleList] { get }
    
    /// 添加新列表
    /// - Parameters:
    ///   - name: 列表名称
    ///   - createdAt: 创建时间
    /// - Returns: 新创建的列表
    func addList(name: String, createdAt: Date) -> ArticleList
    
    /// 更新列表
    /// - Parameter list: 要更新的列表
    func updateList(_ list: ArticleList)
    
    /// 删除列表
    /// - Parameter id: 要删除的列表ID
    func deleteList(id: UUID)
    
    /// 根据ID查找列表
    /// - Parameter id: 列表ID
    /// - Returns: 找到的列表，如果不存在则返回nil
    func findList(by id: UUID) -> ArticleList?
    
    /// 将文章添加到列表
    /// - Parameters:
    ///   - articleId: 文章ID
    ///   - listId: 列表ID
    func addArticleToList(articleId: UUID, listId: UUID)
    
    /// 从列表中移除文章
    /// - Parameters:
    ///   - articleId: 文章ID
    ///   - listId: 列表ID
    func removeArticleFromList(articleId: UUID, listId: UUID)
    
    /// 检查文章是否在列表中
    /// - Parameters:
    ///   - articleId: 文章ID
    ///   - listId: 列表ID
    /// - Returns: 如果文章在列表中返回true，否则返回false
    func isArticleInList(articleId: UUID, listId: UUID) -> Bool
    
    /// 加载列表数据
    func loadLists()
    
    /// 保存列表数据
    func saveLists()
} 