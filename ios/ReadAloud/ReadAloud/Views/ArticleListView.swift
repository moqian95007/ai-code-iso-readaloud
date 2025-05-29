import SwiftUI
import Combine

struct ArticleListView: View {
    @StateObject private var articleManager: ArticleManager
    @StateObject private var listManager: ArticleListManager
    @StateObject private var speechManager: SpeechManager
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var showingAddSheet = false
    @State private var editingArticle: Article? = nil
    @State private var navigationLinkTag: UUID? = nil
    @State private var showingAddListSheet = false
    @State private var showingEditListSheet = false
    @State private var selectedArticle: Article? = nil
    @State private var isShowingArticleReader = false
    @State private var shouldUseLastPlaylist = false
    @State private var isEditMode = false  // 添加编辑模式状态变量
    
    // 添加删除确认相关状态
    @State private var articleToDelete: Article? = nil
    @State private var showDeleteConfirmation = false
    
    // 添加一个专门用于浮动球跳转的状态变量
    @State private var isNavigatingFromBall = false
    // 添加一个防止重复导航的标志
    @State private var isNavigating = false
    
    init(articleManager: ArticleManager = ArticleManager(),
         listManager: ArticleListManager = ArticleListManager.shared,
         speechManager: SpeechManager = SpeechManager.shared) {
        _articleManager = StateObject(wrappedValue: articleManager)
        _listManager = StateObject(wrappedValue: listManager)
        _speechManager = StateObject(wrappedValue: speechManager)
    }
    
    var body: some View {
        Group {
            if articleManager.articles.isEmpty {
                emptyStateView
            } else {
                articleListView
            }
        }
        .navigationBarItems(
            leading: managementButton,
            trailing: addButton
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                listSelectorMenu
            }
        }
        // 减少navigationTitle的影响，确保内容从顶部开始
        .navigationBarTitleDisplayMode(.inline)
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
                        // 显示文章所属列表的名称而不是章节名称
                        Text(listManager.selectedList?.name ?? "阅读列表")
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
                        useLastPlaylist: shouldUseLastPlaylist,
                        articleManager: articleManager
                    )
                }
                .background(Color(.systemBackground))
            }
        }
        // 只保留添加列表的通知监听
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddListView"))) { _ in
            showingAddListSheet = true
        }
        // 添加全局确认对话框
        .confirmationDialog(
            "confirm_delete".localized,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("cancel".localized, role: .cancel) {
                // 取消删除操作
                print("取消删除")
                articleToDelete = nil
            }
            
            Button("delete".localized, role: .destructive) {
                // 确认删除文章
                if let article = articleToDelete {
                    print("确认删除文章: \(article.title)")
                    // 找到文章在原始数组中的索引
                    if let originalIndex = articleManager.articles.firstIndex(where: { $0.id == article.id }) {
                        let originalIndexSet = IndexSet(integer: originalIndex)
                        articleManager.deleteArticle(at: originalIndexSet)
                        print("已删除文章，索引: \(originalIndex)")
                    }
                }
                // 重置状态
                articleToDelete = nil
            }
        } message: {
            if let article = articleToDelete {
                Text("confirm_delete_message".localized(with: article.title))
            } else {
                Text("confirm_delete_message".localized(with: ""))
            }
        }
    }
    
    // 列表选择器下拉菜单
    private var listSelectorMenu: some View {
        Menu {
            ForEach(listManager.userLists) { list in
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
                Label("add_list".localized, systemImage: "plus")
            }
            
            Button(action: {
                showingEditListSheet = true
            }) {
                Label("edit_list".localized, systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 8) {
                Text(listManager.selectedList?.name ?? "reading_list".localized)
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
            Text("no_articles_in_list".localized(with: listManager.selectedList?.name ?? "reading_list".localized))
                .font(.headline)
                .foregroundColor(.gray)
            Text("tap_to_add_article".localized)
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
            // 文章列表
            List {
                // 在列表顶部添加文章数量信息，而不是作为单独的视图
                Section(header: 
                    HStack {
                        Text("articles_count".localized(with: listManager.selectedList?.name ?? "reading_list".localized, filteredArticles.count))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .listRowInsets(EdgeInsets())
                    .background(Color.clear)
                ) {
                    ForEach(filteredArticles) { article in
                        // 根据是否处于编辑模式显示不同的行
                        if isEditMode {
                            articleEditRow(for: article)
                        } else {
                            articleRow(for: article)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
            
            // 播放全部按钮，仅在非编辑模式下显示
            if !filteredArticles.isEmpty && !isEditMode {
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
                        Text("play_all".localized)
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
        if listManager.userLists.first?.id == selectedList.id {
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
    
    // 管理按钮
    private var managementButton: some View {
        Button(action: {
            // 切换编辑模式
            isEditMode.toggle()
        }) {
            Text(isEditMode ? "done".localized : "manage".localized)
                .foregroundColor(isEditMode ? .blue : .primary)
                .font(.system(size: 20, weight: .medium))
        }
    }
    
    // 编辑模式下的文章行
    private func articleEditRow(for article: Article) -> some View {
        HStack {
            // 文章信息部分
            articleInfoView(for: article)
            
            Spacer()
            
            // 删除按钮及其确认对话框
            Button(action: {
                print("点击删除按钮，文章: \(article.title)")
                // 显示删除确认对话框
                articleToDelete = article
                showDeleteConfirmation = true
                print("显示删除确认对话框")
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .contentShape(Rectangle())
    }
} 