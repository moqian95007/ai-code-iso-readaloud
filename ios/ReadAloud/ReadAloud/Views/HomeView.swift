import SwiftUI

struct HomeView: View {
    @StateObject private var articleManager = ArticleManager()
    @StateObject private var listManager = ArticleListManager()
    @StateObject private var speechManager = SpeechManager.shared
    @State private var showingAddSheet = false
    @State private var editingArticle: Article? = nil
    @State private var navigationLinkTag: UUID? = nil
    @State private var showingAddListSheet = false
    @State private var showingEditListSheet = false
    @State private var selectedArticle: Article? = nil
    @State private var isShowingArticleReader = false
    
    var body: some View {
        Group {
            if articleManager.articles.isEmpty {
                emptyStateView
            } else {
                articleListView
            }
        }
        .navigationBarItems(
            trailing: addButton
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                listSelectorMenu
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddArticleView(articleManager: articleManager, listManager: listManager, isPresented: $showingAddSheet)
        }
        .sheet(item: $editingArticle) { article in
            EditArticleView(articleManager: articleManager, listManager: listManager, article: article, isPresented: $editingArticle)
        }
        .sheet(isPresented: $showingAddListSheet) {
            AddListView(listManager: listManager, isPresented: $showingAddListSheet)
        }
        .sheet(isPresented: $showingEditListSheet) {
            EditListsView(listManager: listManager, isPresented: $showingEditListSheet)
        }
        // 添加监听浮动球的通知
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenArticle"))) { notification in
            print("========= HomeView收到OpenArticle通知 =========")
            // 从通知中获取文章ID
            if let userInfo = notification.userInfo,
               let articleId = userInfo["articleId"] as? UUID {
                print("通知中的文章ID: \(articleId)")
                
                // 如果通知中包含列表ID，则更新当前选中的列表
                if let selectedListId = userInfo["selectedListId"] as? UUID {
                    print("通知中的列表ID: \(selectedListId)")
                    listManager.selectedListId = selectedListId
                }
                
                // 激活对应的NavigationLink
                DispatchQueue.main.async {
                    navigationLinkTag = articleId
                    print("设置navigationLinkTag: \(articleId)")
                }
            } else {
                print("通知中没有找到有效的文章ID")
            }
            print("==============================================")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddListView"))) { _ in
            showingAddListSheet = true
        }
    }
    
    // 列表选择器下拉菜单
    private var listSelectorMenu: some View {
        Menu {
            ForEach(listManager.lists) { list in
                Button(action: {
                    listManager.selectedListId = list.id
                }) {
                    if listManager.selectedListId == list.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
            
            Divider()
            
            Button(action: {
                showingAddListSheet = true
            }) {
                Label("新增列表", systemImage: "plus")
            }
            
            Button(action: {
                showingEditListSheet = true
            }) {
                Label("编辑列表", systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 8) {
                Text(listManager.selectedList?.name ?? "阅读列表")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(height: 30)  // 固定高度
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("\(listManager.selectedList?.name ?? "阅读列表")中没有文章")
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
        let filteredArticles = filterArticles(articleManager.articles)
        
        return VStack(spacing: 0) {
            // 显示当前选中列表的名称和文章数量
            HStack {
                Text("\(listManager.selectedList?.name ?? "阅读列表") · \(filteredArticles.count)篇文章")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 2)
            .padding(.bottom, 5)
            
            // 文章列表
            List {
                ForEach(filteredArticles) { article in
                    articleRow(for: article)
                }
                .onDelete(perform: articleManager.deleteArticle)
            }
            .listStyle(PlainListStyle())
            
            // 播放全部按钮
            if !filteredArticles.isEmpty {
                Button(action: {
                    if let firstArticle = filteredArticles.first {
                        navigationLinkTag = firstArticle.id
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 30))
                        Text("播放全部")
                            .font(.system(size: 30, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                }
                .buttonStyle(PlainButtonStyle())
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(.systemGray5)),
                    alignment: .top
                )
            }
        }
        
    }
    
    // 根据当前选择的列表过滤文章
    private func filterArticles(_ articles: [Article]) -> [Article] {
        guard let selectedList = listManager.selectedList else {
            return articles
        }
        
        // 如果是第一个列表（默认的"所有文章"），显示所有文章
        if listManager.lists.first?.id == selectedList.id {
            return articles
        }
        
        // 否则只显示属于当前列表的文章
        return articles.filter { article in
            selectedList.articleIds.contains(article.id)
        }
    }
    
    // 单个文章行
    private func articleRow(for article: Article) -> some View {
        ZStack {
            // 隐藏的 NavigationLink，不显示任何内容（包括箭头）
            NavigationLink(
                destination: ArticleReaderView(
                    article: article,
                    selectedListId: listManager.selectedListId
                ), 
                tag: article.id, 
                selection: $navigationLinkTag
            ) {
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
    
    private func handleArticleSelection(_ article: Article) {
        selectedArticle = article
        isShowingArticleReader = true
        // 更新播放列表
        let filteredArticles = filterArticles(articleManager.articles)
        speechManager.updatePlaylist(filteredArticles)
    }
} 