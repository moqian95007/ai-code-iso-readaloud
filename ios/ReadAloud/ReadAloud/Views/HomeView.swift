import SwiftUI

struct HomeView: View {
    @StateObject private var articleManager = ArticleManager()
    @State private var showingAddSheet = false
    @State private var editingArticle: Article? = nil
    @State private var navigationLinkTag: UUID? = nil
    
    var body: some View {
        Group {
            if articleManager.articles.isEmpty {
                emptyStateView
            } else {
                articleListView
            }
        }
        .navigationBarTitle("阅读列表", displayMode: .large)
        .navigationBarItems(trailing: addButton)
        .sheet(isPresented: $showingAddSheet) {
            AddArticleView(articleManager: articleManager, isPresented: $showingAddSheet)
        }
        .sheet(item: $editingArticle) { article in
            EditArticleView(articleManager: articleManager, article: article, isPresented: $editingArticle)
        }
        // 添加监听浮动球的通知
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenArticle"))) { notification in
            // 从通知中获取文章ID
            if let userInfo = notification.userInfo,
               let articleId = userInfo["articleId"] as? UUID {
                // 激活对应的NavigationLink
                navigationLinkTag = articleId
            }
        }
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("还没有添加任何文章")
                .font(.headline)
                .foregroundColor(.gray)
            Text("点击右上角的+按钮添加新文章")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.top, 5)
            Spacer()
        }
    }
    
    // 添加按钮
    private var addButton: some View {
        Button(action: {
            showingAddSheet = true
        }) {
            Image(systemName: "plus")
                .font(.title2)
        }
    }
    
    // 文章列表视图
    private var articleListView: some View {
        List {
            ForEach(articleManager.articles) { article in
                articleRow(for: article)
            }
            .onDelete(perform: articleManager.deleteArticle)
        }
        .listStyle(PlainListStyle())
    }
    
    // 单个文章行
    private func articleRow(for article: Article) -> some View {
        ZStack {
            // 隐藏的 NavigationLink，不显示任何内容（包括箭头）
            NavigationLink(destination: ArticleReaderView(article: article), tag: article.id, selection: $navigationLinkTag) {
                EmptyView()
            }
            .opacity(0)
            
            // 实际显示的内容
            HStack {
                // 文章信息部分
                articleInfoView(for: article)
                    .onTapGesture {
                        editingArticle = article
                    }
                
                Spacer()
                
                // 自定义播放按钮（不使用NavigationLink作为按钮）
                Button(action: {
                    navigationLinkTag = article.id  // 激活导航
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 38))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // 整行的点击事件也是进入编辑页面
                editingArticle = article
            }
        }
    }
    
    // 文章信息视图
    private func articleInfoView(for article: Article) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title)
                .font(.headline)
            Text(article.formattedDate)
                .font(.caption)
                .foregroundColor(.gray)
            // 显示内容预览
            Text(article.contentPreview())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
    }
}

// 编辑文章的视图
struct EditArticleView: View {
    @ObservedObject var articleManager: ArticleManager
    let article: Article
    @Binding var isPresented: Article?
    
    @State private var content: String
    
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
    
    init(articleManager: ArticleManager, article: Article, isPresented: Binding<Article?>) {
        self.articleManager = articleManager
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
            }
            .navigationBarTitle("编辑文章", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") {
                    isPresented = nil
                },
                trailing: Button("保存") {
                    if !content.isEmpty {
                        // 更新文章内容和标题
                        articleManager.updateArticle(id: article.id, title: extractedTitle, content: content)
                        isPresented = nil
                    }
                }
                .disabled(content.isEmpty)
            )
        }
    }
}

// 添加新文章的视图
struct AddArticleView: View {
    @ObservedObject var articleManager: ArticleManager
    @Binding var isPresented: Bool
    
    @State private var content = ""
    
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
            }
            .navigationBarTitle("添加新文章", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") {
                    isPresented = false
                },
                trailing: Button("保存") {
                    if !content.isEmpty {
                        // 使用提取的标题和内容添加文章
                        articleManager.addArticle(title: extractedTitle, content: content)
                        isPresented = false
                    }
                }
                .disabled(content.isEmpty)
            )
        }
    }
} 