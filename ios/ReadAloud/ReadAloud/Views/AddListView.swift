import SwiftUI

/// 添加新列表的视图
struct AddListView: View {
    @ObservedObject var listManager: ArticleListManager
    @Binding var isPresented: Bool
    
    @State private var listName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("列表信息")) {
                    TextField("列表名称", text: $listName)
                }
            }
            .navigationBarTitle("添加新列表", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") {
                    isPresented = false
                },
                trailing: Button("保存") {
                    if !listName.isEmpty {
                        listManager.addList(name: listName)
                        isPresented = false
                    }
                }
                .disabled(listName.isEmpty)
            )
        }
    }
} 