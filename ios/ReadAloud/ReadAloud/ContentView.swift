//
//  ContentView.swift
//  ReadAloud
//
//  Created by moqian on 2025/3/27.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var navigationState = NavigationState.shared
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    @State private var selectedDocument: Document? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部搜索框
                SearchBar()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 文件朗读区域
                        DocumentReadingSection()
                    }
                    .padding(.top, 10)
                }
                
                // 底部导航栏
                BottomTabBar()
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            // 添加导航目标 - 这是关键部分
            .navigationDestination(isPresented: $navigationState.shouldNavigateToReader) {
                if let doc = playbackManager.currentDocument {
                    DocumentReaderView(
                        documentTitle: doc.title,
                        document: doc,
                        viewModel: DocumentsViewModel()
                    )
                }
            }
        }
        // 添加右下角的浮动球（当有内容在播放且不在朗读界面时显示）
        .overlay(
            Group {
                if !navigationState.isInReaderView && playbackManager.isPlaying {
                    FloatingPlayerButton()
                        .padding(.bottom, 120)
                        .padding(.trailing, 30)
                }
            },
            alignment: .bottomTrailing
        )
        .onChange(of: navigationState.isInReaderView) { newValue in
            print("Navigation state changed: isInReaderView = \(newValue)")
        }
        .onChange(of: playbackManager.isPlaying) { newValue in
            print("Playback state changed: isPlaying = \(newValue)")
        }
    }
}

// 搜索栏组件
struct SearchBar: View {
    @State private var searchText = ""
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("搜索历史听单/文档", text: $searchText)
                .font(.system(size: 16))
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }
}

// 文件朗读区域
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
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        // 第一行：导入按钮 + 最多2本书
                        HStack(alignment: .top, spacing: 15) {
                            // 导入本地文档按钮
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
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentImporter(isPresented: $showingDocumentPicker) { url in
                do {
                    if let duplicateTitle = try viewModel.addDocument(from: url) {
                        errorMessage = "文件内容与 \(duplicateTitle) 重复"
                        showingError = true
                    }
                } catch FileHasher.HashError.fileNotFound {
                    errorMessage = "找不到文件";
                    showingError = true
                } catch FileHasher.HashError.readingFailed {
                    errorMessage = "读取文件失败";
                    showingError = true
                } catch {
                    errorMessage = "导入失败：\(error.localizedDescription)";
                    errorMessage = "导入失败：\(error.localizedDescription)"
                    showingError = true
                }
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
}

// 单个文档项
struct DocumentItem: View {
    let document: Document
    let viewModel: DocumentsViewModel
    
    var body: some View {
        NavigationLink(destination: DocumentReaderView(documentTitle: document.title, document: document, viewModel: viewModel)) {
            VStack {
                // 文档封面图
                ZStack {
                    if let coverData = document.coverImageData, 
                       let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 150)
                    } else {
                        // 默认封面背景
                        Color.orange.opacity(0.2)
                    }
                    
                    // 在右上角显示文件类型
                    Text(document.fileType.rawValue.uppercased())
                        .padding(5)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(5)
                        .padding(5)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .alignmentGuide(.top) { d in d[.top] }
                        .alignmentGuide(.trailing) { d in d[.trailing] }
                }
                .frame(width: 120, height: 150)
                .cornerRadius(10)
                .overlay(
                    Text("已播\(Int(document.progress * 100))%")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(4),
                    alignment: .bottom
                )
                
                Text(document.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .center)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// 自定义无选择指示器的列表
struct CustomSelectionList<Content: View, T: Hashable>: View {
    @Binding var selection: Set<T>
    @Binding var isEditMode: EditMode
    let content: Content
    
    init(selection: Binding<Set<T>>, isEditMode: Binding<EditMode>, @ViewBuilder content: () -> Content) {
        self._selection = selection
        self._isEditMode = isEditMode
        self.content = content()
    }
    
    var body: some View {
        if isEditMode.isEditing {
            ScrollView {
                LazyVStack(spacing: 0) {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
        } else {
            List {
                content
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
}

// 文档管理视图
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
                    // 全选/取消全选按钮 - 更显眼
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
                
                if isEditMode.isEditing {
                    // 自定义编辑模式视图 - 没有左侧选择指示器
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
                } else {
                    // 普通列表视图
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
                trailing: HStack {
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
            )
            .alert(isPresented: $showingDeleteConfirmation) {
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
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

// 文档行视图组件
struct DocumentRow: View {
    let document: Document
    let isSelected: Bool
    
    var body: some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .imageScale(.large)
            }
            
            ZStack {
                if let coverData = document.coverImageData, 
                   let uiImage = UIImage(data: coverData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Text(document.fileType.rawValue)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            VStack(alignment: .leading) {
                Text(document.title)
                    .font(.headline)
                
                Text("上次阅读: \(document.lastReadDate, formatter: dateFormatter)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("\(Int(document.progress * 100))%")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

// 底部标签栏
struct BottomTabBar: View {
    var body: some View {
        HStack {
            Spacer()
            
            VStack {
                Image(systemName: "house.fill")
                    .font(.system(size: 22))
                Text("首页")
                    .font(.caption)
            }
            .foregroundColor(.red)
            
            Spacer()
            
            VStack {
                Image(systemName: "person")
                    .font(.system(size: 22))
                Text("我的")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            Spacer()
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray4)),
            alignment: .top
        )
    }
}

// 浮动播放按钮（当有内容在播放时显示）
struct FloatingPlayerButton: View {
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    @ObservedObject private var navigationState = NavigationState.shared
    @State private var animationAmount = 1.0
    
    var body: some View {
        if playbackManager.currentDocument != nil && playbackManager.isPlaying {
            Button(action: {
                // 激活导航标志，触发导航
                navigationState.shouldNavigateToReader = true
            }) {
                // 增大浮动球并添加动态效果
                ZStack {
                    // 外层脉冲圆 - 增大波纹效果
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 70, height: 70)
                        .scaleEffect(animationAmount)
                        .opacity(2 - animationAmount)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: false),
                            value: animationAmount
                        )
                    
                    // 主背景圆
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 70, height: 70)
                    
                    // 动态音波图标
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
            .contentShape(Circle())
            .onAppear {
                // 启动动画 - 增大动画幅度
                animationAmount = 1.8
            }
        } else {
            EmptyView()
        }
    }
}

#Preview {
    ContentView()
}
