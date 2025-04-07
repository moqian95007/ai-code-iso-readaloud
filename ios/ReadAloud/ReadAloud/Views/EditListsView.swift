import SwiftUI

/// 编辑列表的视图
struct EditListsView: View {
    @ObservedObject var listManager: ArticleListManager
    @Binding var isPresented: Bool
    
    @State private var editingListId: UUID? = nil
    @State private var editingListName = ""
    @State private var showingRenameSheet = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(listManager.userLists) { list in
                    HStack {
                        Text(list.name)
                        Spacer()
                        
                        // 编辑按钮
                        if list.id != listManager.userLists.first?.id { // 不允许编辑"所有文章"列表
                            Button(action: {
                                editingListId = list.id
                                editingListName = list.name
                                showingRenameSheet = true
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .onDelete { indexSet in
                    // 防止删除第一个列表（"所有文章"）
                    if !indexSet.contains(0) {
                        // 对于每个索引，删除对应的列表ID
                        for index in indexSet {
                            if index < listManager.userLists.count {
                                let listId = listManager.userLists[index].id
                                listManager.deleteList(id: listId)
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("编辑列表", displayMode: .inline)
            .navigationBarItems(
                leading: Button("完成") {
                    isPresented = false
                },
                trailing: Button(action: {
                    isPresented = false
                    // 添加一个短暂延迟，确保当前视图已关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        // 然后再显示添加列表视图
                        NotificationCenter.default.post(name: Notification.Name("ShowAddListView"), object: nil)
                    }
                }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(isPresented: $showingRenameSheet) {
                RenameListView(
                    listName: $editingListName,
                    isPresented: $showingRenameSheet,
                    onSave: {
                        if let id = editingListId, !editingListName.isEmpty {
                            // 获取当前列表
                            if let currentList = listManager.findList(by: id) {
                                // 创建更新后的列表
                                var updatedList = currentList
                                updatedList.name = editingListName
                                
                                // 更新列表
                                listManager.updateList(updatedList)
                            }
                        }
                    }
                )
            }
        }
    }
}

/// 重命名列表的视图
struct RenameListView: View {
    @Binding var listName: String
    @Binding var isPresented: Bool
    var onSave: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("列表信息")) {
                    TextField("列表名称", text: $listName)
                }
            }
            .navigationBarTitle("重命名列表", displayMode: .inline)
            .navigationBarItems(
                leading: Button("取消") {
                    isPresented = false
                },
                trailing: Button("保存") {
                    onSave()
                    isPresented = false
                }
                .disabled(listName.isEmpty)
            )
        }
    }
} 