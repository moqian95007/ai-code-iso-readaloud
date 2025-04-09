import SwiftUI
import Foundation

struct FileReadView: View {
    @State private var showImportPicker = false
    @State private var showImportSuccess = false
    @State private var showImportError = false
    @State private var errorMessage = ""
    @State private var isEditMode = false // 编辑模式标志
    @State private var selectedDocument: Document? = nil // 选择的文档
    @State private var showDocumentReader = false // 是否显示阅读器
    @State private var isImporting = false // 添加导入中状态
    
    // 必要的管理器
    @ObservedObject private var articleManager: ArticleManager // 移除单例引用
    @ObservedObject private var documentLibrary = DocumentLibraryManager.shared // 使用单例
    @StateObject private var documentManager: DocumentManager // 文档导入管理器
    
    // 初始化
    init(articleManager: ArticleManager) {
        // 注入 ArticleManager
        self.articleManager = articleManager
        
        // 使用 DocumentLibraryManager 的共享实例
        let library = DocumentLibraryManager.shared
        self._documentManager = StateObject(wrappedValue: DocumentManager(documentLibrary: library))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    // 顶部标题栏
                    HeaderView(isEditMode: $isEditMode)
                    
                    // 主内容区域
                    ScrollView {
                        VStack(spacing: 20) {
                            // 本地文件导入按钮
                            if !isEditMode {
                                ImportButton(showImportPicker: $showImportPicker, isImporting: $isImporting)
                            }
                            
                            // 文档列表区域
                            DocumentListView(
                                isEditMode: isEditMode,
                                documentLibrary: documentLibrary,
                                selectedDocument: $selectedDocument,
                                showDocumentReader: $showDocumentReader,
                                showImportError: $showImportError,
                                errorMessage: $errorMessage
                            )
                            
                            // 如果没有导入的文档，显示提示
                            if documentLibrary.documents.isEmpty {
                                Text("尚未导入任何文档")
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                        }
                        .padding(.top)
                    }
                    
                    Spacer()
                }
                .background(Color(.systemBackground))
                
                // 导入中遮罩层
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.7)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(2.0)
                                .padding()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            
                            Text("文档导入中...")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("请稍候，正在处理文件")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(30)
                        .background(Color(.systemBackground).opacity(0.2))
                        .cornerRadius(20)
                        .shadow(radius: 15)
                    }
                    .zIndex(100) // 确保遮罩在最上层
                    .transition(.opacity)
                    .animation(.easeInOut, value: isImporting)
                    .edgesIgnoringSafeArea(.all)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                print("FileReadView出现")
                // 确保文档库完全加载
                DispatchQueue.main.async {
                    print("重新加载文档库以确保数据完整性")
                    documentLibrary.loadDocuments()
                    print("文档库已加载，共 \(documentLibrary.documents.count) 个文档")
                }
            }
            .sheet(isPresented: $showImportPicker) {
                // 文件选择结束后的处理
                print("文件选择器关闭")
            } content: {
                DocumentPickerView(documentManager: documentManager) { success in
                    print("文档选择结果: \(success)")
                    
                    // 隐藏导入中遮罩
                    withAnimation {
                        isImporting = false
                        print("隐藏导入中遮罩层")
                    }
                    
                    if success {
                        // 导入成功，显示成功消息
                        showImportSuccess = true
                    } else {
                        // 导入失败，显示错误消息
                        errorMessage = "导入文档失败，请检查文件格式或权限"
                        showImportError = true
                    }
                }
            }
            .alert("导入成功", isPresented: $showImportSuccess) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("文档已成功导入并转换为可朗读的文本。章节识别正在后台进行中，识别完成前文档暂不可点击。")
            }
            .alert("导入失败", isPresented: $showImportError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: $showDocumentReader) {
                // 关闭阅读器时重置selectedDocument
                selectedDocument = nil
                print("阅读器关闭，重置文档选择状态")
            } content: {
                DocumentReaderView(
                    selectedDocument: $selectedDocument,
                    showDocumentReader: $showDocumentReader,
                    documentLibrary: documentLibrary,
                    articleManager: articleManager
                )
            }
            // 添加对OpenDocument通知的监听
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenDocument"))) { notification in
                print("========= FileReadView收到OpenDocument通知 =========")
                
                // 从通知中获取文档ID
                if let userInfo = notification.userInfo,
                   let documentId = userInfo["documentId"] as? UUID {
                    print("通知中的文档ID: \(documentId), 类型: \(type(of: documentId))")
                    
                    // 确保文档数据已加载
                    documentLibrary.loadDocuments()
                    
                    // 首先确保文档存在于文档库中
                    if let document = documentLibrary.findDocument(by: documentId) {
                        print("找到文档: \(document.title)，准备显示")
                        
                        // 设置最近播放的内容类型为文档
                        UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
                        print("收到OpenDocument通知，设置最近播放内容类型为document")
                        UserDefaults.standard.synchronize()
                        
                        // 检查阅读器是否已经显示，如果是则先关闭再打开
                        if showDocumentReader {
                            print("阅读器已显示，先关闭再重新打开")
                            
                            // 先关闭阅读器
                            DispatchQueue.main.async {
                                showDocumentReader = false
                                
                                // 延迟后再设置文档并显示
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    // 先设置文档，然后显示阅读器
                                    selectedDocument = document
                                    print("选择文档: \(document.title)")
                                    
                                    // 设置最近打开的文档ID
                                    UserDefaults.standard.set(document.id.uuidString, forKey: "lastOpenedDocumentId")
                                    UserDefaults.standard.synchronize()
                                    
                                    // 保存文档打开时间戳
                                    let currentTime = Date().timeIntervalSince1970
                                    UserDefaults.standard.set(currentTime, forKey: "lastDocumentPlayTime_\(document.id.uuidString)")
                                    print("保存文档播放时间戳: \(currentTime)")
                                    UserDefaults.standard.synchronize()
                                    
                                    // 触发全屏展示
                                    showDocumentReader = true
                                    print("已触发文档阅读器显示")
                                }
                            }
                        } else {
                            // 正常设置文档并显示阅读器
                            DispatchQueue.main.async {
                                // 先设置文档，然后显示阅读器
                                selectedDocument = document
                                print("选择文档: \(document.title)")
                                
                                // 设置最近打开的文档ID
                                UserDefaults.standard.set(document.id.uuidString, forKey: "lastOpenedDocumentId")
                                UserDefaults.standard.synchronize()
                                
                                // 保存文档打开时间戳
                                let currentTime = Date().timeIntervalSince1970
                                UserDefaults.standard.set(currentTime, forKey: "lastDocumentPlayTime_\(document.id.uuidString)")
                                print("保存文档播放时间戳: \(currentTime)")
                                UserDefaults.standard.synchronize()
                                
                                // 触发全屏展示
                                showDocumentReader = true
                                print("已触发文档阅读器显示")
                            }
                        }
                    } else {
                        print("错误：找不到ID为 \(documentId) 的文档")
                    }
                } else {
                    print("通知中没有找到有效的文档ID")
                }
                print("==============================================")
            }
        }
    }
}

// 头部视图
struct HeaderView: View {
    @Binding var isEditMode: Bool
    
    var body: some View {
        HStack {
            Text("文件朗读")
                .font(.system(size: 24, weight: .bold))
                .padding(.leading)
            
            Spacer()
            
            Button(action: {
                print("点击了管理按钮")
                // 切换编辑模式
                isEditMode.toggle()
            }) {
                Text(isEditMode ? "完成" : "管理")
                    .foregroundColor(isEditMode ? .blue : .primary)
                    .font(.system(size: 18))
            }
            .padding(.trailing)
        }
        .padding(.top)
    }
}

// 导入按钮视图
struct ImportButton: View {
    @Binding var showImportPicker: Bool
    @Binding var isImporting: Bool  // 添加导入状态绑定
    
    var body: some View {
        Button(action: {
            print("点击了导入按钮")
            // 立即显示导入中遮罩
            withAnimation {
                isImporting = true
                print("显示导入中遮罩层")
            }
            // 立即显示文件选择器
            showImportPicker = true
        }) {
            VStack {
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
                Text("导入本地文档")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                Spacer()
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(10)
            )
            .padding(.horizontal)
        }
    }
}

// 文档列表视图
struct DocumentListView: View {
    let isEditMode: Bool
    let documentLibrary: DocumentLibraryManager
    @Binding var selectedDocument: Document?
    @Binding var showDocumentReader: Bool
    @Binding var showImportError: Bool
    @Binding var errorMessage: String
    @State private var refreshID = UUID() // 添加一个状态变量用于强制刷新
    @State private var showDeleteConfirmation = false
    @State private var documentsToDelete: [Document] = []
    @State private var indexSetToDelete: IndexSet?
    
    var body: some View {
        VStack {
            if isEditMode {
                // 编辑模式下的文档列表
                ForEach(documentLibrary.documents) { document in
                    DocumentEditItem(document: document, documentLibrary: documentLibrary)
                        .id(document.id) // 确保每个项都有唯一ID
                }
                // 替换原有的onDelete处理
                .onDelete { _ in } // 不再直接响应系统的删除操作
            } else {
                // 普通模式下的文档列表
                ForEach(documentLibrary.documents) { document in
                    DocumentItem(
                        document: document,
                        documentLibrary: documentLibrary,
                        selectedDocument: $selectedDocument,
                        showDocumentReader: $showDocumentReader,
                        showImportError: $showImportError,
                        errorMessage: $errorMessage
                    )
                }
            }
        }
        .id(refreshID) // 使用 refreshID 作为视图的 ID
        .onAppear {
            // 不直接调用loadDocuments，而是监听加载完成通知
            print("DocumentListView视图出现")
            // 仅在需要强制刷新视图时调用
            refreshID = UUID()
        }
        .onChange(of: documentLibrary.documents.count) { _ in
            // 当文档数量变化时刷新视图
            print("文档数量发生变化，刷新视图")
            refreshID = UUID() // 强制刷新视图
        }
        // 接收文档库加载完成通知
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DocumentLibraryLoaded"))) { _ in
            print("DocumentListView收到文档库加载完成通知，刷新视图")
            refreshID = UUID() // 强制刷新视图
        }
    }
}

// 单个文档项视图（普通模式）
struct DocumentItem: View {
    let document: Document
    let documentLibrary: DocumentLibraryManager
    @Binding var selectedDocument: Document?
    @Binding var showDocumentReader: Bool
    @Binding var showImportError: Bool
    @Binding var errorMessage: String
    @State private var showLoadingIndicator = false
    @State private var documentProcessingState: DocumentProcessingState = .unknown
    
    // 添加防止短时间内重复点击
    @State private var isSelecting = false
    
    // 用于跟踪已经检查过状态的文档ID，避免重复输出日志
    private static var checkedDocumentIds = Set<UUID>()
    
    // 文档处理状态
    enum DocumentProcessingState {
        case unknown // 未知状态，初始状态
        case processing // 正在处理章节
        case completed // 章节处理完成
        case error // 处理出错
    }
    
    var body: some View {
        ZStack {
            // 文档项按钮
            Button(action: {
                // 防止短时间内重复点击
                if isSelecting {
                    print("防止重复点击文档: \(document.title)")
                    return
                }
                
                // 设置选择状态
                isSelecting = true
                
                // 确保延迟之后才能再次点击
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSelecting = false
                }
                
                handleDocumentSelection()
            }) {
                BookItem(
                    title: document.title,
                    progress: document.progress,
                    fileType: document.fileType
                )
                .overlay(
                    Group {
                        if documentProcessingState == .processing {
                            // 章节处理中的覆盖层
                            ZStack {
                                Color.black.opacity(0.6)
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                    Text("正在识别章节...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .cornerRadius(10)
                        }
                    }
                )
            }
            .disabled(documentProcessingState == .processing)
            
            // 加载指示器覆盖
            if showLoadingIndicator {
                VStack(spacing: 15) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在加载文档...")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding(30)
                .background(Color(.systemBackground).opacity(0.9))
                .cornerRadius(15)
                .shadow(radius: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
            }
        }
        .onAppear {
            // 检查章节是否已处理
            checkDocumentProcessingState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DocumentChapterProcessingCompleted"))) { notification in
            if let userInfo = notification.userInfo,
               let documentId = userInfo["documentId"] as? UUID,
               documentId == document.id {
                print("收到章节处理完成通知，文档ID: \(documentId)")
                documentProcessingState = .completed
            }
        }
    }
    
    // 检查文档处理状态
    private func checkDocumentProcessingState() {
        // 检查该文档是否有章节缓存，如果有则标记为已完成
        let saveKey = "documentChapters_" + document.id.uuidString
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let chapters = try? JSONDecoder().decode([Chapter].self, from: data),
           !chapters.isEmpty {
            // 只有当该文档ID尚未检查过时才输出日志
            if !DocumentItem.checkedDocumentIds.contains(document.id) {
                print("文档已有章节缓存，标记为已完成: \(document.title)")
                // 记录已检查过的文档ID
                DocumentItem.checkedDocumentIds.insert(document.id)
            }
            documentProcessingState = .completed
        } else {
            // 检查是否是新导入的文档
            let timeInterval = Date().timeIntervalSince(document.createdAt)
            if timeInterval < 60 { // 如果是在1分钟内创建的文档，认为可能是处理中
                // 只对新导入的文档输出日志
                print("新导入文档，标记为处理中: \(document.title)")
                documentProcessingState = .processing
            } else {
                // 较老的没有章节缓存的文档，可能是之前处理失败，标记为已完成
                documentProcessingState = .completed
            }
        }
    }
    
    // 清除已检查文档记录的静态方法，用于测试或重置
    static func clearCheckedDocuments() {
        checkedDocumentIds.removeAll()
    }
    
    // 处理文档选择
    private func handleDocumentSelection() {
        // 如果章节正在处理中，不进行操作
        if documentProcessingState == .processing {
            print("文档章节正在处理中，暂不可选择: \(document.title)")
            return
        }
        
        // 立即显示加载指示器
        self.showLoadingIndicator = true
        
        // 检查此文档是否已经在播放中
        let playbackManager = PlaybackManager.shared
        let isSameDocumentPlaying = playbackManager.isPlaying && 
                                   playbackManager.contentType == .document &&
                                   playbackManager.currentContentId == document.id
        print("检查文档播放状态 - 文档ID: \(document.id), 是否在播放: \(isSameDocumentPlaying)")
        
        // 从文档库中获取最新的文档实例
        if let freshDocument = documentLibrary.findDocument(by: document.id) {
            print("找到文档 '\(freshDocument.title)', 内容长度: \(freshDocument.content.count)")
            
            // 确保内容非空才设置并打开
            if !freshDocument.content.isEmpty {
                print("选择文档: \(freshDocument.title), ID: \(freshDocument.id)")
                
                // 创建文档副本并设置
                let docCopy = Document(
                    id: freshDocument.id,
                    title: freshDocument.title,
                    content: freshDocument.content,
                    fileType: freshDocument.fileType,
                    createdAt: freshDocument.createdAt,
                    progress: freshDocument.progress
                )
                
                // 设置为选中文档
                selectedDocument = docCopy
                
                // 设置打开时间
                DispatchQueue.main.async {
                    // 显示文档阅读器
                    showDocumentReader = true
                    self.showLoadingIndicator = false
                }
            } else {
                // 文档内容为空，尝试处理
                handleEmptyDocument(freshDocument)
            }
        } else {
            print("错误: 找不到文档ID \(document.id)")
            errorMessage = "找不到指定的文档"
            showImportError = true
            self.showLoadingIndicator = false
        }
    }
    
    // 处理空文档情况
    private func handleEmptyDocument(_ document: Document) {
        print("警告: 文档内容为空，尝试获取最新版本")
        
        // 尝试重新获取文档，而不是重新加载整个文档库
        if let reloadedDocument = documentLibrary.findDocument(by: document.id),
           !reloadedDocument.content.isEmpty {
            print("获取文档最新版本成功，内容长度: \(reloadedDocument.content.count)")
            
            // 创建文档副本
            let docCopy = Document(
                id: reloadedDocument.id,
                title: reloadedDocument.title,
                content: reloadedDocument.content,
                fileType: reloadedDocument.fileType,
                createdAt: reloadedDocument.createdAt,
                progress: reloadedDocument.progress
            )
            
            // 设置为选中文档
            selectedDocument = docCopy
            print("已设置最新版本文档: \(docCopy.title), 内容长度: \(docCopy.content.count)")
            
            DispatchQueue.main.async {
                showDocumentReader = true
            }
        } else {
            print("错误: 无法获取文档最新版本")
            errorMessage = "无法加载文档内容，请重新导入"
            showImportError = true
        }
    }
}

// 文档编辑项视图
struct DocumentEditItem: View {
    let document: Document
    let documentLibrary: DocumentLibraryManager
    // 添加一个内部状态来控制该项是否应该显示
    @State private var isDeleted = false
    // 添加删除确认弹窗的状态
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        if !isDeleted {
            HStack {
                // 文档类型标签
                Text(document.fileType)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)
                
                // 文档标题
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // 删除按钮
                Button(action: {
                    // 显示确认弹窗
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .padding(8)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
            )
            .padding(.horizontal)
            // 使用confirmationDialog替代alert
            .confirmationDialog("确认删除", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("取消", role: .cancel) {
                    // 取消操作，什么都不做
                }
                
                Button("删除", role: .destructive) {
                    if let index = documentLibrary.documents.firstIndex(where: { $0.id == document.id }) {
                        print("删除文档: \(document.title)")
                        documentLibrary.deleteDocument(at: IndexSet(integer: index))
                        // 标记该项为已删除，从视图中移除
                        withAnimation {
                            isDeleted = true
                        }
                        // 确保删除后刷新文档列表
                        DispatchQueue.main.async {
                            print("删除后刷新文档列表")
                            documentLibrary.loadDocuments()
                        }
                    }
                }
            } message: {
                Text("确定要删除文档\"\(document.title)\"吗？此操作无法撤销。")
            }
        } else {
            // 已删除的项不显示任何内容
            EmptyView()
        }
    }
}

// 书籍视图
struct BookItem: View {
    let title: String
    let progress: Double
    let fileType: String
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 15) {
                // 书籍封面图片 - 如果没有实际图片，可以使用颜色和文字代替
                ZStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 120, height: 160)
                        .cornerRadius(8)
                    
                    Text(fileType)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.blue)
                        .cornerRadius(4)
                        .padding([.top, .trailing], -60)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                    
                    if progress > 0 {
                        Text("已播放\(Int(progress * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        // 进度条
                        ProgressView(value: progress)
                            .accentColor(.blue)
                            .frame(height: 5)
                    } else {
                        Text("点击开始朗读")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
}

// 文档阅读器视图
struct DocumentReaderView: View {
    @Binding var selectedDocument: Document?
    @Binding var showDocumentReader: Bool
    let documentLibrary: DocumentLibraryManager
    let articleManager: ArticleManager
    @State private var isLoading = true
    
    // 添加一个防止重新创建内容的ID
    @State private var contentId = UUID()
    
    var body: some View {
        // 检查文档是否有效
        if let document = selectedDocument, !document.content.isEmpty {
            ZStack {
                // 内容视图
                VStack {
                    // 头部导航栏
                    HStack {
                        Button(action: {
                            print("关闭文档阅读器")
                            // 发送通知，让DocumentArticleReaderView保存进度
                            NotificationCenter.default.post(name: Notification.Name("SaveDocumentProgress"), object: nil)
                            // 给保存操作留出时间
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // 不清除selectedDocument，只关闭阅读器
                                showDocumentReader = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding()
                        }
                        Spacer()
                        Text(document.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        // 使用空间占位符保持布局平衡
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.clear)
                            .padding()
                    }
                    
                    // 使用ID确保DocumentArticleReaderView只被创建一次，避免重复初始化
                    DocumentArticleReaderView(
                        document: document, 
                        isLoading: $isLoading,
                        documentLibrary: documentLibrary,
                        articleManager: articleManager
                    )
                    .id(contentId) // 加上ID保证不会重新创建
                }
                .background(Color(.systemBackground))
                
                // 加载指示器覆盖
                if isLoading {
                    VStack(spacing: 15) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("加载章节中...")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding(30)
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(15)
                    .shadow(radius: 10)
                }
            }
            .onAppear {
                // 记录当前播放内容类型为文档
                UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
                print("文档阅读器出现，设置最近播放内容类型为document")
                UserDefaults.standard.synchronize()
                
                // 保存当前文档ID为最近打开的文档
                UserDefaults.standard.set(document.id.uuidString, forKey: "lastOpenedDocumentId")
                print("文档阅读器出现，设置最近打开文档ID为\(document.id.uuidString)")
                
                // 保存文档打开时间戳
                let currentTime = Date().timeIntervalSince1970
                UserDefaults.standard.set(currentTime, forKey: "lastDocumentPlayTime_\(document.id.uuidString)")
                print("保存文档播放时间戳: \(currentTime)")
                UserDefaults.standard.synchronize()
                
                // 2秒后强制隐藏加载指示器，即使加载没完成也给用户响应
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isLoading = false
                }
            }
            .onDisappear {
                // 在视图消失时强制刷新文档列表以显示最新进度
                print("文档阅读器消失，刷新文档列表")
                // 确保在关闭视图之前保存进度
                NotificationCenter.default.post(name: Notification.Name("SaveDocumentProgress"), object: nil)
                
                // 确保最近播放内容类型设置为document
                UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
                print("文档阅读器视图消失，设置最近播放内容类型为document")
                UserDefaults.standard.synchronize()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    documentLibrary.loadDocuments()
                }
            }
        } else {
            // 如果没有选择文档或文档内容为空，显示错误信息
            ErrorView(
                selectedDocument: $selectedDocument,
                showDocumentReader: $showDocumentReader,
                docCopy: selectedDocument,
                isDocValid: selectedDocument != nil && !(selectedDocument?.content.isEmpty ?? true)
            )
        }
    }
}

// 错误视图
struct ErrorView: View {
    @Binding var selectedDocument: Document?
    @Binding var showDocumentReader: Bool
    let docCopy: Document?
    let isDocValid: Bool
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    print("关闭空文档错误视图")
                    selectedDocument = nil  // 清除选中的文档
                    showDocumentReader = false
                }) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding()
                }
                Spacer()
            }
            
            Spacer()
            
            Text("无法加载文档")
                .font(.headline)
                .foregroundColor(.red)
                .padding()
            
            let errorMsg = isDocValid ? "" : (docCopy == nil ? "文档选择无效" : "文档内容为空")
            Text("文档内容为空或未正确加载 (\(errorMsg))")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding()
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            print("警告: 试图打开空文档")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                selectedDocument = nil
                showDocumentReader = false
            }
        }
    }
}

// 文档阅读器包装视图，用于将Document转换为Article并展示
struct DocumentArticleReaderView: View {
    // 添加静态变量用于防止短时间内重复初始化
    private static var lastInitTime: Date = Date(timeIntervalSince1970: 0)
    private static var lastInitDocumentId: UUID? = nil
    private static var isInitializing: Bool = false
    
    let document: Document
    let documentLibrary: DocumentLibraryManager
    @StateObject private var chapterManager = ChapterManager()
    @ObservedObject private var speechManager = SpeechManager.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var currentArticle: Article
    @State private var isFirstLoad = true
    @State private var hasLoadedChapters = false
    @Binding var isLoading: Bool
    let articleManager: ArticleManager
    
    // 添加防止重复更新currentArticle的变量
    @State private var lastArticleUpdateTime: Date = Date()
    @State private var isUpdatingArticle: Bool = false
    
    init(document: Document, isLoading: Binding<Bool>, documentLibrary: DocumentLibraryManager, articleManager: ArticleManager) {
        // 检查是否短时间内重复初始化相同文档
        let now = Date()
        let isSameDocument = Self.lastInitDocumentId == document.id
        let isRecentInit = now.timeIntervalSince(Self.lastInitTime) < 0.5
        
        if isSameDocument && isRecentInit && Self.isInitializing {
            print("防止重复初始化DocumentArticleReaderView - 相同文档ID: \(document.id)，间隔: \(now.timeIntervalSince(Self.lastInitTime))秒")
            // 继续初始化，但不打印详细日志
            self.document = document
            self._isLoading = isLoading
            self.documentLibrary = documentLibrary
            self.articleManager = articleManager
            
            // 创建简单的默认Article，避免过多日志
            let defaultArticle = Article(
                id: UUID(),
                title: document.title,
                content: "加载中...",
                createdAt: document.createdAt,
                listId: document.id
            )
            self._currentArticle = State(initialValue: defaultArticle)
            return
        }
        
        // 设置初始化标志，防止递归初始化
        Self.isInitializing = true
        Self.lastInitTime = now
        Self.lastInitDocumentId = document.id
        
        print("DocumentArticleReaderView 初始化: \(document.title), 内容长度: \(document.content.count)")
        self.document = document
        self._isLoading = isLoading
        self.documentLibrary = documentLibrary
        self.articleManager = articleManager
        
        // 确保文档内容有效
        let content = document.content.isEmpty ? "(文档内容为空，请重新导入)" : document.content
        
        // 初始化使用上次阅读的章节
        var initialTitle = document.title
        var initialContent = content
        
        // 检查是否已有章节缓存，如果有则使用上次阅读的章节而不是第一章
        var foundValidCache = false
        let saveKey = "documentChapters_" + document.id.uuidString
        let lastChapterKey = "lastChapter_\(document.id.uuidString)"
        var lastChapterIndex = 0
        
        // 检查是否有上次阅读的章节索引记录
        if UserDefaults.standard.object(forKey: lastChapterKey) != nil {
            lastChapterIndex = UserDefaults.standard.integer(forKey: lastChapterKey)
        }
        
        // 用于保存初始章节ID
        var initialChapterId = UUID()
        
        // 首先检查是否有保存的章节ID
        let chapterIdKey = "lastChapterId_\(document.id.uuidString)"
        var savedChapterId: UUID? = nil
        if let savedIdString = UserDefaults.standard.string(forKey: chapterIdKey),
           let savedId = UUID(uuidString: savedIdString) {
            savedChapterId = savedId
            print("找到保存的章节ID: \(savedIdString)")
        }
        
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let chapters = try? JSONDecoder().decode([Chapter].self, from: data),
           !chapters.isEmpty, !chapters[0].content.isEmpty {
            
            // 确保章节按顺序排列
            let sortedChapters = chapters.sorted(by: { $0.startIndex < $1.startIndex })
            
            // 首先尝试按ID查找章节
            if let savedId = savedChapterId,
               let chapterIndex = sortedChapters.firstIndex(where: { $0.id == savedId }) {
                let savedChapter = sortedChapters[chapterIndex]
                initialTitle = savedChapter.title
                initialContent = savedChapter.content
                initialChapterId = savedChapter.id
                print("按ID找到上次阅读的章节: \(savedChapter.title)")
                print("使用章节ID: \(savedChapter.id.uuidString)")
            }
            // 如果没有找到保存的ID，则使用索引
            else if lastChapterIndex >= 0 && lastChapterIndex < sortedChapters.count {
                // 使用上次阅读的章节
                let savedChapter = sortedChapters[lastChapterIndex]
                initialTitle = savedChapter.title
                initialContent = savedChapter.content
                initialChapterId = savedChapter.id // 保存章节ID
                print("初始化使用上次阅读的章节: 第\(lastChapterIndex+1)章 - \(savedChapter.title)")
                print("使用章节ID: \(savedChapter.id.uuidString)")
            } else {
                // 直接使用第一章内容初始化
                initialTitle = sortedChapters[0].title
                initialContent = sortedChapters[0].content
                initialChapterId = sortedChapters[0].id // 保存章节ID
                print("初始化使用第1章: \(sortedChapters[0].title)")
                print("使用章节ID: \(sortedChapters[0].id.uuidString)")
            }
            
            foundValidCache = true
            
            // 仅保存必要的初始状态，不在初始化方法中异步更新播放列表
            // 将在onAppear中处理章节列表的更新
        }
        
        // 创建初始Article
        let initialArticle = Article(
            id: initialChapterId,  // 使用章节ID而不是随机ID，确保与播放列表中的ID一致
            title: initialTitle,
            content: initialContent,
            createdAt: document.createdAt,
            listId: document.id // 保持列表关联
        )
        
        self._currentArticle = State(initialValue: initialArticle)
        
        print("Article初始化完成: \(initialArticle.title), 内容长度: \(initialArticle.content.count), ID: \(initialArticle.id.uuidString)")
        
        // 重置初始化标志
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.isInitializing = false
        }
    }
    
    var body: some View {
        VStack {
            // 使用ArticleReaderView显示文档内容
            ArticleReaderView(
                article: currentArticle,
                articleManager: articleManager
            )
            .onAppear {
                print("DocumentArticleReaderView 出现")
                // 检查文档内容是否为空
                if document.content.isEmpty {
                    print("警告: 文档内容为空，无法继续处理")
                    isLoading = false
                    return
                }
                
                // 更新播放列表（如果有缓存的章节）
                updateChapterList()
                
                // 预加载章节 - 增加延迟确保界面先显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    preloadChapters()
                }
            }
        }
        // 处理章节变化
        .onReceive(chapterManager.$chapters) { chapters in
            print("收到章节更新: \(chapters.count)个")
            if !chapters.isEmpty {
                updateArticleFromChapters(chapters)
                // 当章节更新后，标记加载完成
                isLoading = false
            }
        }
        // 处理加载状态变化
        .onReceive(chapterManager.$isProcessing) { isProcessing in
            print("章节处理状态: \(isProcessing)")
            // 当章节处理完成时，确保加载指示器消失
            if !isProcessing {
                isLoading = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SaveDocumentProgress"))) { _ in
            print("收到保存进度通知")
            saveDocumentProgress()
        }
        .onDisappear {
            saveDocumentProgress()
            
            // 确保最近播放内容类型设置为document
            UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
            print("文档阅读器消失，设置最近播放内容类型为document")
            UserDefaults.standard.synchronize()
        }
    }
    
    // 更新章节列表（如果有缓存）
    private func updateChapterList() {
        // 检查是否已经有章节数据
        let saveKey = "documentChapters_" + self.document.id.uuidString
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let sortedChapters = try? JSONDecoder().decode([Chapter].self, from: data),
           !sortedChapters.isEmpty {
            
            // 创建完整的文章列表供播放器使用
            let articleList = sortedChapters.map { chapter -> Article in
                // 格式化章节标题，与后续处理保持一致
                let title: String
                if chapter.title == "前言" {
                    // 保持前言标题不变
                    title = "前言"
                } else {
                    // 普通章节添加章节编号
                    // 尝试从章节标题中提取编号
                    let chapterNumber = chapter.chapterNumber > 0 ? chapter.chapterNumber : sortedChapters.firstIndex(of: chapter)! + 1
                    title = "第\(chapterNumber)章: \(chapter.title)"
                }
                
                return Article(
                    id: chapter.id,  // 使用章节ID确保唯一性
                    title: title,
                    content: chapter.content,
                    createdAt: document.createdAt,
                    listId: document.id // 保持列表关联
                )
            }
            
            // 预先更新播放列表
            if !articleList.isEmpty {
                SpeechManager.shared.updatePlaylist(articleList)
                print("初始化时预设置播放列表，包含 \(articleList.count) 篇文章")
                if let firstArticle = articleList.first, let lastArticle = articleList.last {
                    print("列表第一篇ID: \(firstArticle.id.uuidString), 最后一篇ID: \(lastArticle.id.uuidString)")
                }
            }
        }
    }
    
    // 预加载章节，迅速加载已有缓存，避免显示加载指示器
    private func preloadChapters() {
        // 避免重复加载
        if self.hasLoadedChapters {
            print("章节已加载，跳过处理")
            isLoading = false
            return
        }
        
        // 检查是否已经有章节数据
        let saveKey = "documentChapters_" + self.document.id.uuidString
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let existingChapters = try? JSONDecoder().decode([Chapter].self, from: data),
           !existingChapters.isEmpty {
            print("找到缓存的章节数据: \(existingChapters.count)个章节")
            
            // 更新章节管理器
            DispatchQueue.main.async {
                self.chapterManager.chapters = existingChapters
                self.chapterManager.isProcessing = false
                self.hasLoadedChapters = true
                self.isLoading = false
                print("已加载缓存的章节数据")
            }
            return
        }
        
        // 如果没有缓存，开始识别章节
        print("没有找到章节缓存，开始识别章节")
        self.chapterManager.isProcessing = true
        self.isLoading = true
        
        // 在后台线程进行章节识别
        DispatchQueue.global(qos: .userInitiated).async {
            let chapters = self.chapterManager.identifyChapters(for: self.document)
            
            // 在主线程更新UI
            DispatchQueue.main.async {
                self.hasLoadedChapters = true
                self.isLoading = false
                print("章节识别完成，共\(chapters.count)个章节")
            }
        }
    }
    
    // 处理文档章节
    private func processChapters() {
        print("开始处理文档章节")
        
        DispatchQueue.main.async {
            // 设置加载状态
            self.isLoading = true
        }
        
        // 重新验证文档内容
        guard !document.content.isEmpty else {
            print("警告: 文档内容为空，创建默认章节")
            
            // 创建默认章节
            let emptyChapter = Chapter(
                title: "内容为空",
                content: "(文档内容为空或未正确加载)",
                startIndex: 0,
                endIndex: 0,
                documentId: document.id
            )
            
            DispatchQueue.main.async { [document = self.document] in
                // 更新章节管理器
                self.chapterManager.chapters = [emptyChapter]
                self.chapterManager.isProcessing = false
                self.chapterManager.progressPercentage = 100
                
                // 更新当前文章
                self.currentArticle = Article(
                    id: emptyChapter.id,  // 使用章节ID而不是随机ID
                    title: "内容为空",
                    content: "(文档内容为空或未正确加载)",
                    createdAt: document.createdAt,
                    listId: document.id
                )
                
                // 设置加载完成标志
                self.hasLoadedChapters = true
                self.isLoading = false
                
                // 设置通知观察者
                self.setupArticleListNotificationObserver()
            }
            return
        }
        
        // 创建本地副本避免潜在的内存问题
        let docCopy = Document(
            id: document.id,
            title: document.title,
            content: document.content,
            fileType: document.fileType,
            createdAt: document.createdAt,
            progress: document.progress
        )
        
        // 静默处理章节，不显示UI指示
        print("在后台线程处理章节，内容长度: \(docCopy.content.count)")
        let chapters = self.chapterManager.identifyChapters(for: docCopy)
        
        DispatchQueue.main.async { [document = self.document] in            
            print("章节处理完成，章节数: \(chapters.count)")
            
            if !chapters.isEmpty {
                // 确保章节按顺序排列（根据在文档中的位置）
                let sortedChapters = chapters.sorted(by: { $0.startIndex < $1.startIndex })
                
                // 更新使用排序后的章节
                self.chapterManager.chapters = sortedChapters
                self.updateArticleFromChapters(sortedChapters)
                
                // 设置加载完成标志
                self.hasLoadedChapters = true
                self.isLoading = false
                
                // 设置通知观察者
                self.setupArticleListNotificationObserver()
            } else {
                print("错误: 没有识别到有效章节，创建默认章节")
                
                // 创建默认章节
                let defaultChapter = Chapter(
                    title: document.title,
                    content: document.content,
                    startIndex: 0,
                    endIndex: document.content.count,
                    documentId: document.id
                )
                
                // 更新章节管理器
                self.chapterManager.chapters = [defaultChapter]
                self.updateArticleFromChapters([defaultChapter])
                self.hasLoadedChapters = true
                self.isLoading = false
                
                // 设置通知观察者
                self.setupArticleListNotificationObserver()
            }
        }
    }
    
    // 从章节更新文章
    private func updateArticleFromChapters(_ chapters: [Chapter]) {
        print("========= 更新文章列表 =========")
        print("更新文章，章节数: \(chapters.count)")
        
        guard !chapters.isEmpty else { 
            print("错误：章节列表为空")
            return 
        }
        
        // 检查防抖：如果距离上次更新不足0.5秒，则跳过
        let now = Date()
        if now.timeIntervalSince(lastArticleUpdateTime) < 0.5 && isUpdatingArticle {
            print("防抖：跳过过于频繁的章节更新")
            return
        }
        
        // 设置正在更新标志
        isUpdatingArticle = true
        lastArticleUpdateTime = now
        
        // 创建文章列表，添加章节编号到标题，特殊处理前言章节
        let articleList = chapters.enumerated().map { (index, chapter) -> Article in
            // 为每个章节创建一个文章对象
            let title: String
            if chapter.title == "前言" {
                // 保持前言标题不变
                title = "前言"
            } else {
                // 普通章节添加章节编号
                // 尝试从章节标题中提取编号
                let chapterNumber = chapter.chapterNumber > 0 ? chapter.chapterNumber : self.chapterManager.chapters.firstIndex(of: chapter)! + 1
                title = "第\(chapterNumber)章: \(chapter.title)"
            }
            
            let article = Article(
                id: chapter.id,  // 使用章节ID确保唯一性
                title: title,
                content: chapter.content,
                createdAt: document.createdAt,
                listId: document.id // 保持列表关联
            )
            
            // print("创建章节文章: \(title), ID: \(chapter.id)")
            return article
        }
        
        // 预先检测第一篇文章的语言 - 移除，只在需要时检测
        
        // 更新播放列表 - 确保包含所有章节
        SpeechManager.shared.updatePlaylist(articleList)
        print("已更新完整播放列表，包含 \(articleList.count) 篇文章")
        if !articleList.isEmpty {
            print("播放列表第一篇ID: \(articleList[0].id)")
            if articleList.count > 1 {
                print("播放列表最后一篇ID: \(articleList[articleList.count-1].id)")
            }
        }
        
        // 查找上次阅读的章节
        var startingChapterIndex = 0
        let overallProgress = document.progress
        let speechManager = SpeechManager.shared
        
        // 0. 首先查找是否有保存的章节ID
        let chapterIdKey = "lastChapterId_\(document.id.uuidString)"
        var foundChapterById = false
        if let savedIdString = UserDefaults.standard.string(forKey: chapterIdKey),
           let savedId = UUID(uuidString: savedIdString) {
            print("加载章节列表时找到保存的章节ID: \(savedIdString)")
            // 在章节列表中查找匹配的ID
            if let chapterIndex = chapters.firstIndex(where: { $0.id == savedId }) {
                startingChapterIndex = chapterIndex
                foundChapterById = true
                print("根据章节ID找到章节索引: \(chapterIndex+1)/\(chapters.count)")
            } else {
                print("警告：找不到匹配保存ID的章节，将尝试使用其他方法")
            }
        }
        
        // 如果没有找到匹配ID的章节，尝试使用之前的方法
        if !foundChapterById {
            // 1. 尝试从UserDefaults中获取上次读到的章节索引
            let lastChapterKey = "lastChapter_\(document.id.uuidString)"
            if UserDefaults.standard.object(forKey: lastChapterKey) != nil {
                let savedIndex = UserDefaults.standard.integer(forKey: lastChapterKey)
                if savedIndex >= 0 && savedIndex < chapters.count {
                    startingChapterIndex = savedIndex
                    print("找到上次保存的章节索引: \(savedIndex+1)/\(chapters.count)")
                }
            }
            // 2. 如果没有找到保存的章节索引，但文档有阅读进度，尝试根据进度计算
            else if overallProgress > 0 {
                print("文档有阅读进度: \(Int(overallProgress * 100))%，尝试找到对应章节")
                
                // 计算文档总字符数
                let totalCharCount = chapters.reduce(0) { $0 + $1.content.count }
                
                // 根据总进度计算应该阅读到的字符位置
                let targetCharPosition = Int(Double(totalCharCount) * overallProgress)
                
                // 查找对应的章节
                var accumulatedChars = 0
                for (index, chapter) in chapters.enumerated() {
                    let nextAccumulatedChars = accumulatedChars + chapter.content.count
                    
                    // 如果目标位置在当前章节内，找到了对应章节
                    if targetCharPosition >= accumulatedChars && targetCharPosition < nextAccumulatedChars {
                        startingChapterIndex = index
                        
                        // 计算章节内的相对位置
                        let relativePosition = targetCharPosition - accumulatedChars
                        let chapterProgress = Double(relativePosition) / Double(chapter.content.count)
                        
                        print("根据总进度计算章节：第\(index+1)章，章节内进度约\(Int(chapterProgress * 100))%")
                        break
                    }
                    
                    accumulatedChars = nextAccumulatedChars
                }
            }
        }
        
        // 确保章节索引有效
        startingChapterIndex = min(startingChapterIndex, chapters.count - 1)
        print("最终选择的章节索引: \(startingChapterIndex+1)/\(chapters.count)")
        
        // 更新当前文章为开始阅读的章节
        if !articleList.isEmpty {
            let selectedArticle = articleList[startingChapterIndex]
            print("选择的文章标题: \(selectedArticle.title), ID: \(selectedArticle.id)")
            
            // 确保不会频繁更新同一篇文章
            if self.currentArticle.id != selectedArticle.id || isFirstLoad {
                // 立即更新UI显示的文章内容
                DispatchQueue.main.async {
                    // 重要：强制更新UI显示
                    withAnimation {
                        self.currentArticle = selectedArticle
                    }
                    print("强制UI显示之前阅读的章节: \(startingChapterIndex+1)/\(chapters.count), ID: \(selectedArticle.id)")
                    
                    // 更新isFirstLoad状态，防止重复初始化
                    if self.isFirstLoad {
                        self.isFirstLoad = false
                    }
                }
                
                // 设置到SpeechManager
                speechManager.setup(for: selectedArticle)
                
                // 设置章节内的精确位置
                var chapterProgress = 0.0
                var position = 0
                
                // 1. 首先尝试根据文章ID查找保存的位置
                let playbackPositionKey = UserDefaultsKeys.lastPlaybackPosition(for: selectedArticle.id)
                if let savedPosition = UserDefaults.standard.object(forKey: playbackPositionKey) as? Int, savedPosition > 0 {
                    position = savedPosition
                    print("根据章节ID找到保存的播放位置: \(position)")
                    
                    // 同时获取进度
                    let progressKey = UserDefaultsKeys.lastProgress(for: selectedArticle.id)
                    if let savedProgress = UserDefaults.standard.object(forKey: progressKey) as? Double {
                        chapterProgress = savedProgress
                        print("根据章节ID找到保存的进度: \(Int(chapterProgress * 100))%")
                    }
                }
                // 2. 如果没有找到特定章节的位置，使用文档级别的位置
                else {
                    let chapterPositionKey = "chapterPosition_\(document.id.uuidString)"
                    if UserDefaults.standard.object(forKey: chapterPositionKey) != nil {
                        chapterProgress = UserDefaults.standard.double(forKey: chapterPositionKey)
                        print("找到保存的章节内进度: \(Int(chapterProgress * 100))%")
                        
                        // 计算文本位置
                        let chapter = chapters[startingChapterIndex]
                        position = Int(Double(chapter.content.count) * chapterProgress)
                    }
                }
                
                // 如果有具体位置，设置SpeechManager的currentPlaybackPosition并立即更新UI
                if position > 0 {
                    speechManager.currentPlaybackPosition = position
                    
                    // 使用forceUpdateUI方法强制更新UI
                    speechManager.forceUpdateUI(position: position)
                    
                    print("设置章节内位置: \(position)/\(selectedArticle.content.count)")
                }
                
                // 检查SpeechManager当前的播放列表状态
                print("检查SpeechManager播放列表状态:")
                let currentPlaylistCount = speechManager.lastPlayedArticles.count
                print("SpeechManager播放列表文章数: \(currentPlaylistCount)")
                if currentPlaylistCount > 0 {
                    print("SpeechManager第一篇文章ID: \(speechManager.lastPlayedArticles.first?.id ?? UUID())")
                    if currentPlaylistCount > 1 {
                        print("SpeechManager最后一篇文章ID: \(speechManager.lastPlayedArticles.last?.id ?? UUID())")
                    }
                }
            } else {
                print("跳过相同文章的重复更新: \(selectedArticle.id)")
            }
        } else {
            print("错误：生成的文章列表为空")
        }
        
        // 重置更新标志
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isUpdatingArticle = false
        }
        
        print("========= 文章列表更新完成 =========")
    }
    
    // 保存文档进度
    private func saveDocumentProgress() {
        // 设置最近播放内容类型为document
        UserDefaults.standard.set("document", forKey: "lastPlayedContentType")
        
        // 更新文档播放时间戳
        let currentTime = Date().timeIntervalSince1970
        UserDefaults.standard.set(currentTime, forKey: "lastDocumentPlayTime_\(document.id.uuidString)")
        print("保存文档进度时更新播放时间戳: \(currentTime)")
        
        // 当前章节的进度
        let currentChapterProgress = SpeechManager.shared.currentProgress
        
        // 获取当前章节及所有章节信息
        let chapters = chapterManager.chapters
        guard !chapters.isEmpty else {
            print("警告：无法计算整体进度，章节列表为空")
            return
        }
        
        // 获取当前文章
        let speechManager = SpeechManager.shared
        
        // 尝试确定当前正在播放的文章
        var currentPlayingArticle: Article?
        var currentIndex: Int = 0
        
        // 方法1：从SpeechManager获取当前文章
        let managerCurrentArticle = speechManager.getCurrentArticle()
        if let article = managerCurrentArticle {
            currentPlayingArticle = article
            print("从SpeechManager获取到当前文章: \(article.title)")
            
            // 尝试根据章节标题直接确定索引
            let titleStr = article.title
            let chapterPattern = "第(\\d+)章"
            if let range = titleStr.range(of: chapterPattern, options: .regularExpression),
               let chapterIndex = titleStr.firstIndex(of: "章") {
                // 确定结束位置，优先使用冒号，否则使用"章"字符后的位置
                let endIndex = titleStr.firstIndex(of: ":") ?? titleStr.index(after: chapterIndex)
                let startIndex = titleStr.index(after: range.lowerBound) // 跳过"第"字符
                let numberString = titleStr[startIndex..<endIndex].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "章", with: "").replacingOccurrences(of: ":", with: "")
                
                if let chapterNumber = Int(numberString), chapterNumber > 0, chapterNumber <= chapters.count {
                    currentIndex = chapterNumber - 1
                    print("根据章节标题直接确定索引: \(currentIndex+1)/\(chapters.count)")
                }
            }
            
            // 如果无法通过标题确定，尝试通过ID查找
            if currentIndex == 0 {
                if let index = chapters.firstIndex(where: { $0.id == article.id }) {
                    currentIndex = index
                    print("根据文章ID找到章节索引: \(currentIndex+1)/\(chapters.count)")
                }
            }
        }
        
        // 保存当前文章ID到UserDefaults，确保下次打开时使用相同的文章
        if let currentArticle = currentPlayingArticle {
            // 保存章节ID到UserDefaults
            let chapterIdKey = "lastChapterId_\(document.id.uuidString)"
            UserDefaults.standard.set(currentArticle.id.uuidString, forKey: chapterIdKey)
            print("保存章节ID: \(currentArticle.id)")
        }
        
        // 计算文档总字符数
        let totalCharCount = chapters.reduce(0) { $0 + $1.content.count }
        if totalCharCount == 0 {
            print("警告：文档总字符数为0，无法计算进度")
            return
        }
        
        // 计算已阅读完成的章节的字符总数
        var readCharCount = 0
        for i in 0..<currentIndex {
            let previousChapter = chapters[i]
            readCharCount += previousChapter.content.count
        }
        
        // 加上当前章节已读字符数
        let currentChapter = chapters[currentIndex]
        let currentChapterReadChars = Int(Double(currentChapter.content.count) * currentChapterProgress)
        readCharCount += currentChapterReadChars
        
        // 计算整体进度
        let overallProgress = Double(readCharCount) / Double(totalCharCount)
        
        print("保存文档进度: 当前章节(\(currentIndex+1)/\(chapters.count))进度\(Int(currentChapterProgress * 100))%, 整体进度\(Int(overallProgress * 100))%")
        
        // 保存上次阅读章节索引到UserDefaults
        let lastChapterKey = "lastChapter_\(document.id.uuidString)"
        UserDefaults.standard.set(currentIndex, forKey: lastChapterKey)
        
        // 保存章节内的相对位置
        let chapterPositionKey = "chapterPosition_\(document.id.uuidString)"
        UserDefaults.standard.set(currentChapterProgress, forKey: chapterPositionKey)
        
        // 保存播放位置信息，确保下次可以从这个位置继续
        if let currentArticle = currentPlayingArticle {
            let playbackPosition = speechManager.currentPlaybackPosition
            UserDefaults.standard.set(playbackPosition, forKey: UserDefaultsKeys.lastPlaybackPosition(for: currentArticle.id))
            UserDefaults.standard.set(currentChapterProgress, forKey: UserDefaultsKeys.lastProgress(for: currentArticle.id))
            
            print("保存章节播放位置: 章节ID=\(currentArticle.id), 位置=\(playbackPosition)")
        }
        
        // 更新文档进度
        if var docToUpdate = documentLibrary.documents.first(where: { $0.id == document.id }) {
            docToUpdate.progress = overallProgress
            documentLibrary.updateDocument(docToUpdate)
            
            // 强制刷新文档列表
            DispatchQueue.main.async {
                documentLibrary.loadDocuments()
            }
        }
    }
    
    // 为通知处理添加观察者
    private func setupArticleListNotificationObserver() {
        // 移除可能的旧观察者
        NotificationCenter.default.removeObserver(self, name: Notification.Name("OpenArticleList"), object: nil)
        
        // 添加OpenArticleList通知观察者
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OpenArticleList"),
            object: nil,
            queue: .main
        ) { _ in
            print("DocumentArticleReaderView接收到OpenArticleList通知")
            
            // 确保章节已加载
            guard !self.chapterManager.chapters.isEmpty else {
                print("警告：章节尚未加载，无法更新播放列表")
                return
            }
            
            // 将章节转换为文章列表，使用与updateArticleFromChapters相同的格式
            let articleList = self.chapterManager.chapters.enumerated().map { (index, chapter) -> Article in
                // 为每个章节创建一个文章对象
                let title: String
                if chapter.title == "前言" {
                    // 保持前言标题不变
                    title = "前言"
                } else {
                    // 普通章节添加章节编号
                    // 尝试从章节标题中提取编号
                    let chapterNumber = chapter.chapterNumber > 0 ? chapter.chapterNumber : self.chapterManager.chapters.firstIndex(of: chapter)! + 1
                    title = "第\(chapterNumber)章: \(chapter.title)"
                }
                
                return Article(
                    id: chapter.id,  // 使用章节ID确保唯一性
                    title: title,
                    content: chapter.content,
                    createdAt: self.document.createdAt,
                    listId: self.document.id // 保持列表关联
                )
            }
            
            // 更新SpeechManager的播放列表
            if !articleList.isEmpty {
                SpeechManager.shared.updatePlaylist(articleList)
                print("DocumentArticleReaderView更新播放列表，包含 \(articleList.count) 篇文章")
            } else {
                print("错误：生成的文章列表为空")
            }
        }
    }
}

struct FileReadView_Previews: PreviewProvider {
    static var previews: some View {
        FileReadView(articleManager: ArticleManager())
    }
} 