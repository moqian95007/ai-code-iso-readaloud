import SwiftUI

// 添加新文章的视图
struct AddArticleView: View {
    @ObservedObject var articleManager: ArticleManager
    @ObservedObject var listManager: ArticleListManager
    @Binding var isPresented: Bool
    
    @State private var content = ""
    @State private var selectedListId: UUID? = nil
    
    init(articleManager: ArticleManager = ArticleManager(),
         listManager: ArticleListManager = ArticleListManager.shared,
         isPresented: Binding<Bool>) {
        self.articleManager = articleManager
        self.listManager = listManager
        self._isPresented = isPresented
        
        // 初始化时使用当前选择的列表
        self._selectedListId = State(initialValue: listManager.selectedListId)
    }
    
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
                
                // 列表选择
                Section(header: Text("添加到列表")) {
                    Picker("选择列表", selection: $selectedListId) {
                        ForEach(listManager.userLists) { list in
                            Text(list.name).tag(list.id as UUID?)
                        }
                    }
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
                        let newArticle = articleManager.addArticle(
                            title: extractedTitle,
                            content: content,
                            listId: selectedListId
                        )
                        
                        isPresented = false
                    }
                }
                .disabled(content.isEmpty)
            )
        }
    }
} 