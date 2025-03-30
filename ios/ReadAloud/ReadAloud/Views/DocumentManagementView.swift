import SwiftUI

struct DocumentManagementView: View {
    @ObservedObject var viewModel: DocumentsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isEditMode: EditMode = .inactive
    @State private var selectedDocuments: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isEditMode.isEditing && !viewModel.documents.isEmpty {
                    selectionControlBar
                }
                
                if isEditMode.isEditing {
                    editModeDocumentsList
                } else {
                    normalDocumentsList
                }
            }
            .navigationTitle("文档管理")
            .navigationBarItems(
                leading: Button(isEditMode.isEditing ? "完成" : "完成") {
                    if isEditMode.isEditing {
                        isEditMode = .inactive
                        selectedDocuments.removeAll()
                    } else {
                        dismiss()
                    }
                },
                trailing: trailingButtons
            )
            .alert(isPresented: $showingDeleteConfirmation) {
                deleteConfirmationAlert
            }
        }
    }
    
    // 选择控制栏
    private var selectionControlBar: some View {
        HStack {
            Button(action: {
                if selectedDocuments.count == viewModel.documents.count {
                    selectedDocuments.removeAll()
                } else {
                    selectedDocuments = Set(viewModel.documents.map { $0.id })
                }
            }) {
                Text(selectedDocuments.count == viewModel.documents.count ? "取消全选" : "全选")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 15)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            if !selectedDocuments.isEmpty {
                Text("已选中\(selectedDocuments.count)项")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
    
    // 编辑模式文档列表
    private var editModeDocumentsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.documents) { document in
                    DocumentRow(document: document, isSelected: selectedDocuments.contains(document.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedDocuments.contains(document.id) {
                                selectedDocuments.remove(document.id)
                            } else {
                                selectedDocuments.insert(document.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(selectedDocuments.contains(document.id) ? Color.blue.opacity(0.1) : Color(.systemBackground))
                }
            }
            .padding(.vertical, 1)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // 普通文档列表
    private var normalDocumentsList: some View {
        List {
            ForEach(viewModel.documents) { document in
                DocumentRow(document: document, isSelected: false)
            }
            .onDelete { indexSet in
                viewModel.removeDocument(at: indexSet)
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    // 导航栏右侧按钮
    private var trailingButtons: some View {
        HStack {
            if isEditMode.isEditing {
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Text("删除选中")
                        .foregroundColor(.red)
                }
                .disabled(selectedDocuments.isEmpty)
            }
            
            Button(action: {
                isEditMode = isEditMode.isEditing ? .inactive : .active
                if !isEditMode.isEditing {
                    selectedDocuments.removeAll()
                }
            }) {
                Text(isEditMode.isEditing ? "取消" : "编辑")
            }
        }
    }
    
    // 删除确认提示
    private var deleteConfirmationAlert: Alert {
        Alert(
            title: Text("确认删除"),
            message: Text("确定要删除选中的\(selectedDocuments.count)个文档吗？此操作不可撤销。"),
            primaryButton: .destructive(Text("删除")) {
                viewModel.removeDocuments(selected: selectedDocuments)
                selectedDocuments.removeAll()
                isEditMode = .inactive
            },
            secondaryButton: .cancel(Text("取消"))
        )
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
} 