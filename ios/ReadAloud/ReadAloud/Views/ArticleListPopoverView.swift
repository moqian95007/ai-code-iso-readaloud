import SwiftUI

/// 显示当前列表中的所有文章标题的弹出视图
struct ArticleListPopoverView: View {
    let articles: [Article]
    let currentArticleId: UUID
    let onSelectArticle: (Article) -> Void
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            ScrollViewReader { scrollProxy in
                List {
                    ForEach(articles) { article in
                        Button(action: {
                            onSelectArticle(article)
                            isPresented = false
                        }) {
                            HStack {
                                Text(article.title)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                // 显示当前正在播放的文章的标记
                                if article.id == currentArticleId {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .id(article.id) // 为每个章节设置唯一ID
                        .background(article.id == currentArticleId ? Color.blue.opacity(0.1) : Color.clear) // 高亮当前章节
                        .cornerRadius(5)
                        .padding(.vertical, 2)
                    }
                }
                .onAppear {
                    // 打印当前章节ID和列表中各章节ID的信息
                    print("ArticleListPopoverView显示 - 当前章节ID: \(currentArticleId)")
                    print("列表中的章节总数: \(articles.count)")
                    
                    // 检查当前ID是否在列表中
                    if let index = articles.firstIndex(where: { $0.id == currentArticleId }) {
                        print("当前章节在列表中的位置: \(index + 1)")
                    } else {
                        print("⚠️ 警告: 当前章节ID不在列表中!")
                    }
                    
                    // 延长等待时间，让视图完全加载
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("尝试滚动到章节ID: \(currentArticleId)")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            // 先检查ID是否在列表中存在
                            if articles.contains(where: { $0.id == currentArticleId }) {
                                scrollProxy.scrollTo(currentArticleId, anchor: .center)
                                print("滚动到当前章节完成")
                            } else {
                                print("⚠️ 无法滚动: 列表中不存在ID为 \(currentArticleId) 的章节")
                            }
                        }
                    }
                }
                .navigationBarTitle("章节列表（共\(articles.count)章）", displayMode: .inline)
                .navigationBarItems(trailing: Button("关闭") {
                    isPresented = false
                })
            }
        }
    }
} 