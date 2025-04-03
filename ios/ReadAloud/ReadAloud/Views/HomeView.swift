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
                    
                    // 处理从浮动球发起的导航请求，使用专用的NavigationLink
                    Group {
                        if isNavigatingFromBall, 
                           let articleId = navigationLinkTag, 
                           let article = articleManager.findArticle(by: articleId) {
                            NavigationLink(
                                destination: ArticleReaderView(
                                    article: article,
                                    selectedListId: listManager.selectedListId,
                                    useLastPlaylist: shouldUseLastPlaylist
                                ),
                                isActive: Binding<Bool>(
                                    get: { isNavigatingFromBall },
                                    set: { if !$0 { isNavigatingFromBall = false } }
                                )
                            ) {
                                EmptyView()
                            }
                            .hidden()
                        }
                    }
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
        // 添加监听浮动球的通知
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenArticle"))) { notification in
            print("========= HomeView收到OpenArticle通知 =========")
            
            // 如果已经在导航中，忽略新的导航请求
            if isNavigating {
                print("已经在导航过程中，忽略此次请求")
                return
            }
            
            // 从通知中获取文章ID
            if let userInfo = notification.userInfo,
               let articleId = userInfo["articleId"] as? UUID {
                print("通知中的文章ID: \(articleId)")
                
                // 首先确保文章存在于文章管理器中
                if articleManager.findArticle(by: articleId) == nil {
                    print("错误：找不到ID为 \(articleId) 的文章")
                    return
                }
                
                // 如果通知中包含列表ID，则更新当前选中的列表
                if let selectedListId = userInfo["selectedListId"] as? UUID {
                    print("通知中的列表ID: \(selectedListId)")
                    listManager.selectedListId = selectedListId
                }
                
                // 检查是否应该使用上一次的播放列表
                let isUsingLastPlaylist = UserDefaults.standard.bool(forKey: "isUsingLastPlaylist")
                
                // 处理播放列表设置
                if let useLastPlaylist = userInfo["useLastPlaylist"] as? Bool, useLastPlaylist || isUsingLastPlaylist {
                    print("检测到浮动球点击，使用上一次的播放列表")
                    // 从SpeechManager中获取上一次的播放列表
                    let lastPlayedArticles = speechManager.lastPlayedArticles
                    if !lastPlayedArticles.isEmpty {
                        // 在导航前更新SpeechManager中的播放列表，确保使用的是上一次的列表
                        speechManager.updatePlaylist(lastPlayedArticles)
                        print("更新播放列表为上一次播放的列表，包含 \(lastPlayedArticles.count) 篇文章")
                        shouldUseLastPlaylist = true
                    }
                } else {
                    shouldUseLastPlaylist = false
                }
                
                // 设置防导航循环标志
                isNavigating = true
                
                // 重要修复：简化导航状态设置
                if let useLastPlaylist = userInfo["useLastPlaylist"] as? Bool, useLastPlaylist || isUsingLastPlaylist {
                    // 浮动球点击的场景，使用全局导航链接
                    DispatchQueue.main.async {
                        // 先重置导航状态，再设置新状态
                        navigationLinkTag = nil
                        
                        // 设置为浮动球导航模式
                        isNavigatingFromBall = true
                        
                        // 然后设置导航目标
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            navigationLinkTag = articleId
                            print("浮动球跳转: 设置导航状态 navigationLinkTag=\(articleId), 使用全局导航")
                        }
                    }
                } else {
                    // 其他场景，使用普通导航链接
                    DispatchQueue.main.async {
                        // 先重置导航状态，再设置新状态
                        navigationLinkTag = nil
                        
                        // 设置为普通导航模式
                        isNavigatingFromBall = false
                        
                        // 然后设置导航目标
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            navigationLinkTag = articleId
                            print("普通跳转: 设置导航状态 navigationLinkTag=\(articleId), 使用普通导航")
                        }
                    }
                }
                
                // 延迟重置导航锁定状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isNavigating = false
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
                        // 更新播放列表为当前筛选的文章
                        speechManager.updatePlaylist(filteredArticles)
                        
                        // 设置不使用上次播放列表标志
                        UserDefaults.standard.set(false, forKey: "isUsingLastPlaylist")
                        shouldUseLastPlaylist = false
                        
                        // 确保不使用浮动球导航
                        isNavigatingFromBall = false
                        
                        // 先重置导航状态，再设置
                        DispatchQueue.main.async {
                            navigationLinkTag = nil
                            
                            // 延迟设置，避免SwiftUI导航栈冲突
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // 激活导航
                                navigationLinkTag = firstArticle.id
                                print("播放全部按钮: 导航到首篇文章 \(firstArticle.title)")
                            }
                        }
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
            // 隐藏的 NavigationLink，只有在非浮动球导航时才显示
            Group {
                if !isNavigatingFromBall {
                    NavigationLink(
                        destination: ArticleReaderView(
                            article: article,
                            selectedListId: listManager.selectedListId,
                            useLastPlaylist: shouldUseLastPlaylist
                        ), 
                        tag: article.id, 
                        selection: $navigationLinkTag
                    ) {
                        EmptyView()
                    }
                    .id(article.id)  // 添加唯一标识，避免SwiftUI重用视图导致的问题
                    .opacity(0)
                }
            }
            
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
                    
                    // 确保不使用浮动球导航模式
                    isNavigatingFromBall = false
                    
                    // 先重置导航状态，再设置
                    DispatchQueue.main.async {
                        navigationLinkTag = nil
                        
                        // 延迟设置，避免SwiftUI导航栈冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // 激活导航
                            navigationLinkTag = article.id
                            print("文章播放按钮: 导航到文章 \(article.title)")
                        }
                    }
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