import SwiftUI

struct ArticleListView: View {
    @ObservedObject private var articleManager = ArticleManager.shared
    @ObservedObject private var listManager = ArticleListManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @State private var showingAddSheet = false
    @State private var editingArticle: Article? = nil
    @State private var navigationLinkTag: UUID? = nil
    @State private var showingAddListSheet = false
    @State private var showingEditListSheet = false
    @State private var selectedArticle: Article? = nil
    @State private var isShowingArticleReader = false
    @State private var shouldUseLastPlaylist = false
    
    // 添加一个专门用于浮动球跳转的状态变量
    @State private var isNavigatingFromBall = false
    // 添加一个防止重复导航的标志
    @State private var isNavigating = false
    
    var body: some View {
        Group {
            if articleManager.articles.isEmpty {
                emptyStateView
            } else {
                ZStack {
                    articleListView
                }
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
        // 全屏显示文章阅读器
        .fullScreenCover(isPresented: $isShowingArticleReader) {
            if let article = selectedArticle {
                VStack {
                    HStack {
                        Button(action: {
                            isShowingArticleReader = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding()
                        }
                        Spacer()
                        Text(article.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        // 使用空间占位符保持布局平衡
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.clear)
                            .padding()
                    }
                    
                    ArticleReaderView(
                        article: article,
                        selectedListId: listManager.selectedListId,
                        useLastPlaylist: shouldUseLastPlaylist
                    )
                }
                .background(Color(.systemBackground))
            }
        }
        // 只保留添加列表的通知监听
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
                        // 更新播放列表为当前筛选的文章
                        speechManager.updatePlaylist(filteredArticles)
                        
                        // 设置不使用上次播放列表标志
                        UserDefaults.standard.set(false, forKey: "isUsingLastPlaylist")
                        shouldUseLastPlaylist = false
                        
                        // 使用全屏覆盖展示
                        selectedArticle = firstArticle
                        isShowingArticleReader = true
                        print("播放全部按钮: 展示首篇文章 \(firstArticle.title)")
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
            // 背景
            Color(.systemBackground)
            
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
                    // 设置播放上下文
                    let filteredArticles = filterArticles(articleManager.articles)
                    speechManager.updatePlaylist(filteredArticles)
                    
                    // 不使用上次播放列表
                    UserDefaults.standard.set(false, forKey: "isUsingLastPlaylist")
                    shouldUseLastPlaylist = false
                    
                    // 使用全屏覆盖展示
                    selectedArticle = article
                    isShowingArticleReader = true
                    print("文章播放按钮: 展示文章 \(article.title)")
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