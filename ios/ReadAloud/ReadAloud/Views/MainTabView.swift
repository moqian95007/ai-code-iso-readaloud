import SwiftUI
import Combine

/// 主标签视图，管理应用程序的主要导航和标签栏
struct MainTabView: View {
    // MARK: - 属性
    @State private var selectedTab = 0
    @State private var navigationLinkTag: UUID? = nil
    @State private var isShowingArticleReader = false
    @State private var selectedArticle: Article? = nil
    @State private var shouldUseLastPlaylist = false
    @State private var selectedListId: UUID? = nil
    
    // 防止重复导航
    @State private var isNavigating = false
    
    // 所需的管理器
    @StateObject private var articleManager: ArticleManager
    @ObservedObject private var listManager = ArticleListManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    
    // 初始化方法
    init() {
        // 创建 ArticleManager 实例
        self._articleManager = StateObject(wrappedValue: ArticleManager())
    }
    
    // MARK: - 视图主体
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // 文件朗读页面作为首页
                FileReadView(articleManager: articleManager)
                .tabItem {
                    VStack {
                        Image(systemName: "house.fill")
                        Text("tab_home".localized)
                    }
                }
                .tag(0)
                // 存储当前选中标签，供子视图使用
                .onAppear {
                    UserDefaults.standard.set(0, forKey: "currentSelectedTab")
                }
                
                // 文章列表页面
                NavigationView {
                    ArticleListView(articleManager: articleManager)
                        .navigationBarTitleDisplayMode(.inline) // 确保标题紧凑显示
                        .edgesIgnoringSafeArea(.top) // 忽略顶部安全区域
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    VStack {
                        Image(systemName: "doc.text.fill")
                        Text("tab_list".localized)
                    }
                }
                .tag(1)
                // 存储当前选中标签，供子视图使用
                .onAppear {
                    UserDefaults.standard.set(1, forKey: "currentSelectedTab")
                }
                
                // 个人页面
                ProfileView()
                    .tabItem {
                        VStack {
                            Image(systemName: "person.fill")
                            Text("tab_profile".localized)
                        }
                    }
                    .tag(2)
                    // 存储当前选中标签，供子视图使用
                    .onAppear {
                        UserDefaults.standard.set(2, forKey: "currentSelectedTab")
                    }
            }
            // 当标签页变化时同步到UserDefaults
            .onChange(of: selectedTab) { newValue in
                UserDefaults.standard.set(newValue, forKey: "currentSelectedTab")
                print("标签页切换到: \(newValue)")
            }
        }
        .fullScreenCover(isPresented: $isShowingArticleReader, onDismiss: {
            // 重置导航状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                selectedArticle = nil
                print("重置selectedArticle为nil")
            }
        }) {
            if let article = selectedArticle {
                VStack {
                    HStack {
                        Button(action: {
                            print("点击关闭全屏阅读视图")
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
                        selectedListId: selectedListId,
                        useLastPlaylist: shouldUseLastPlaylist,
                        articleManager: articleManager
                    )
                }
                .id(article.id) // 使用文章ID作为视图的ID，确保在文章变化时视图会刷新
                .edgesIgnoringSafeArea(.bottom) // 忽略底部安全区域
                .background(Color(.systemBackground))
                .onAppear {
                    print("全屏覆盖视图已出现，显示文章: \(article.title)")
                }
            } else {
                // 如果没有选中文章，显示加载视图或错误提示
                VStack {
                    Text("加载中...")
                        .font(.headline)
                    ProgressView()
                        .padding()
                    Button("返回") {
                        isShowingArticleReader = false
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .onAppear {
                    print("警告：全屏视图出现但selectedArticle为nil")
                }
            }
        }
        // 监听文章清空通知，重新加载文章
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ArticlesCleared"))) { _ in
            print("接收到文章清空通知，重新加载文章数据")
            // 重新从UserDefaults加载文章（现在应该是空的）
            articleManager.loadArticles()
        }
        // 监听文章数据重新加载通知
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReloadArticlesData"))) { _ in
            print("MainTabView收到ReloadArticlesData通知，重新加载文章数据")
            // 重新从UserDefaults加载文章
            articleManager.loadArticles()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenArticle"))) { notification in
            print("========= MainTabView收到OpenArticle通知 =========")
            
            // 如果已经在导航中，忽略新的导航请求
            if isNavigating {
                print("已经在导航过程中，忽略此次请求")
                return
            }
            
            // 从通知中获取文章ID
            if let userInfo = notification.userInfo,
               let articleId = userInfo["articleId"] as? UUID {
                print("通知中的文章ID: \(articleId)")
                
                // 确保文章数据已加载
                articleManager.loadArticles()
                
                // 首先确保文章存在于文章管理器中
                if let article = articleManager.findArticle(by: articleId) {
                    // 如果通知中包含列表ID，则更新当前选中的列表
                    if let listId = userInfo["selectedListId"] as? UUID {
                        print("通知中的列表ID: \(listId)")
                        selectedListId = listId
                    } else {
                        selectedListId = nil
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
                    
                    // 先将文章设置为选中状态
                    selectedArticle = article
                    print("设置文章: \(article.title)")
                    
                    // 强制当前视图刷新
                    DispatchQueue.main.async {
                        print("准备显示全屏阅读视图...")
                        // 确保主线程更新UI
                        isShowingArticleReader = true
                        print("已触发全屏显示")
                        
                        // 延迟重置导航锁定状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isNavigating = false
                            print("重置导航状态")
                        }
                    }
                } else {
                    print("错误：找不到ID为 \(articleId) 的文章")
                }
            } else {
                print("通知中没有找到有效的文章ID")
            }
            print("==============================================")
        }
    }
}

// MARK: - 预览
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
} 