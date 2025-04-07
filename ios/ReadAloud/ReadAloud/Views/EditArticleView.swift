import SwiftUI

// 编辑文章的视图
struct EditArticleView: View {
    @ObservedObject var articleManager: ArticleManager
    @ObservedObject var listManager: ArticleListManager
    let article: Article
    @Binding var isPresented: Article?
    
    @State private var content: String
    @State private var articleLists: [ArticleList] = []
    
    // 从内容中自动提取标题
    private var extractedTitle: String {
        // 获取内容的第一行
        let firstLine = content.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // 如果第一行过长，截取前20个字符并添加省略号
        if firstLine.count > 20 {
            let endIndex = firstLine.index(firstLine.startIndex, offsetBy: 20)
            return String(firstLine[..<endIndex]) + "..."
        }
        
        // 如果内容为空或只有空白字符，返回默认标题
        return firstLine.isEmpty ? "新文章" : firstLine
    }
    
    init(articleManager: ArticleManager,
         listManager: ArticleListManager = ArticleListManager.shared,
         article: Article,
         isPresented: Binding<Article?>) {
        self.articleManager = articleManager
        self.listManager = listManager
        self.article = article
        self._isPresented = isPresented
        self._content = State(initialValue: article.content)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("文章内容")) {
                    TextEditor(text: $content)
                        .frame(minHeight: 300)
                }
                
                // 显示自动提取的标题（仅供参考）
                Section(header: Text("预览标题")) {
                    Text(extractedTitle)
                        .foregroundColor(.secondary)
                }
                
                // 所属列表
                Section(header: Text("所属列表")) {
                    ForEach(listManager.userLists) { list in
                        // 不显示"所有文章"列表的选项
                        if list.id != listManager.userLists.first?.id {
                            Toggle(list.name, isOn: Binding(
                                get: { listManager.isArticleInList(articleId: article.id, listId: list.id) },
                                set: { isOn in
                                    if isOn {
                                        listManager.addArticleToList(articleId: article.id, listId: list.id)
                                    } else {
                                        listManager.removeArticleFromList(articleId: article.id, listId: list.id)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationBarTitle("编辑文章", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") {
                    isPresented = nil
                },
                trailing: Button("保存") {
                    if !content.isEmpty {
                        // 创建更新后的文章对象
                        var updatedArticle = article
                        updatedArticle.title = extractedTitle
                        updatedArticle.content = content
                        
                        // 更新文章
                        articleManager.updateArticle(updatedArticle)
                        isPresented = nil
                    }
                }
                .disabled(content.isEmpty)
            )
        }
    }
} 