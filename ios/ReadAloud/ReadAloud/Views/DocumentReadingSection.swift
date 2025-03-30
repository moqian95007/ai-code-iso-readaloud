import SwiftUI

struct DocumentReadingSection: View {
    @StateObject private var viewModel = DocumentsViewModel()
    @State private var showingDocumentPicker = false
    @State private var showingDocumentManagement = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue)
                    .cornerRadius(8)
                Text("文件朗读")
                    .font(.headline)
                Spacer()
                
                Button(action: {
                    showingDocumentManagement = true
                }) {
                    Text("管理")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            if viewModel.documents.isEmpty {
                // 没有文档时显示空状态
                emptyStateView
            } else {
                documentsGridView
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentImporter(isPresented: $showingDocumentPicker) { url in
                importDocument(from: url)
            }
        }
        .sheet(isPresented: $showingDocumentManagement) {
            DocumentManagementView(viewModel: viewModel)
        }
        .alert("导入失败", isPresented: $showingError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Text("还没有导入文档")
                .foregroundColor(.gray)
            
            Button(action: {
                showingDocumentPicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("导入文档")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // 文档网格视图
    private var documentsGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                // 第一行：导入按钮 + 最多2本书
                HStack(alignment: .top, spacing: 15) {
                    // 导入本地文档按钮
                    importButton
                    
                    // 显示前两本书（如果有的话）
                    ForEach(Array(viewModel.documents.prefix(2).enumerated()), id: \.element.id) { _, document in
                        DocumentItem(document: document, viewModel: viewModel)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                // 如果有更多书，显示更多行
                if viewModel.documents.count > 2 {
                    // 第二行开始：每行最多显示3本书
                    ForEach(0..<(viewModel.documents.count - 2 + 2) / 3, id: \.self) { rowIndex in
                        HStack(spacing: 15) {
                            ForEach(0..<min(3, viewModel.documents.count - 2 - rowIndex * 3), id: \.self) { columnIndex in
                                let index = 2 + rowIndex * 3 + columnIndex
                                DocumentItem(document: viewModel.documents[index], viewModel: viewModel)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }
    
    // 导入按钮
    private var importButton: some View {
        Button(action: {
            showingDocumentPicker = true
        }) {
            VStack {
                Image(systemName: "plus")
                    .font(.system(size: 30))
                    .foregroundColor(.gray)
                Text("导入本地文档")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(width: 120, height: 180)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
        }
    }
    
    // 导入文档方法
    private func importDocument(from url: URL) {
        do {
            if let duplicateTitle = try viewModel.addDocument(from: url) {
                errorMessage = "文件内容与 \(duplicateTitle) 重复"
                showingError = true
            }
        } catch FileHasher.HashError.fileNotFound {
            errorMessage = "找不到文件"
            showingError = true
        } catch FileHasher.HashError.readingFailed {
            errorMessage = "读取文件失败"
            showingError = true
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
            showingError = true
        }
    }
} 