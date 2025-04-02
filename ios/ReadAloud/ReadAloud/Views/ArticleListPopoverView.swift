import SwiftUI

/// 显示当前列表中的所有文章标题的弹出视图
struct ArticleListPopoverView: View {
    let articles: [Article]
    let currentArticleId: UUID
    let onSelectArticle: (Article) -> Void
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
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
                }
            }
            .navigationBarTitle("文章列表", displayMode: .inline)
            .navigationBarItems(trailing: Button("关闭") {
                isPresented = false
            })
        }
    }
} 