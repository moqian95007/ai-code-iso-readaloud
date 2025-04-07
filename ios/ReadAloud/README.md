# ReadAloud 应用程序重构

本文档详细说明了ReadAloud应用程序的重构过程，重点关注文档朗读和文章朗读两个主要模块的整合。

## 重构背景

应用程序主要有两大模块：文档朗读和文章朗读。在原有实现中，这两个模块存在逻辑混乱的问题：

1. 文档和文章被视为同一层级的内容
2. 文档中的章节与文章虽然概念相似，但实现不统一
3. 数据模型之间的关系不明确，特别是在ID处理方面存在问题

## 重构目标

1. 统一文档和文章列表的数据结构
2. 建立清晰的数据关系：文章属于列表，文章中存储所属列表ID
3. 将文档视为特殊的文章列表，共享相同的数据结构
4. 保持UI简洁，在界面上不把文档显示为文章列表

## 数据模型修改

### Article 模型

```swift
struct Article: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var createdAt: Date
    var listId: UUID? // 添加所属列表ID
    
    // 其他方法...
}
```

### Chapter 模型

```swift
struct Chapter: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var content: String
    var startIndex: Int
    var endIndex: Int
    var documentId: UUID
    var listId: UUID? // 添加所属列表ID，与文章保持一致
    
    // 添加与Article一致的contentPreview方法
    func contentPreview() -> String {
        if content.count > 50 {
            return String(content.prefix(50)) + "..."
        } else {
            return content
        }
    }
    
    // 其他方法...
}
```

### Document 模型

```swift
struct Document: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var fileType: String
    var createdAt: Date
    var progress: Double = 0.0
    var chapterIds: [UUID] = [] // 存储文档中的章节ID，与ArticleList中的articleIds类似
    
    // 将文档转换为ArticleList
    func toArticleList() -> ArticleList {
        return ArticleList(
            id: self.id,
            name: self.title,
            createdAt: self.createdAt,
            articleIds: self.chapterIds,
            isDocument: true
        )
    }
    
    // 其他方法...
}
```

### ArticleList 模型

```swift
struct ArticleList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var articleIds: [UUID] = []
    var isDocument: Bool = false // 标记该列表是否为文档转换而来
    
    // 自定义初始化方法，支持从Document创建
    init(id: UUID, name: String, createdAt: Date, articleIds: [UUID], isDocument: Bool = true) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.articleIds = articleIds
        self.isDocument = isDocument
    }
    
    // 将列表转换为Document
    func toDocument(content: String = "", fileType: String = "txt", progress: Double = 0.0) -> Document? {
        return Document(
            id: self.id,
            title: self.name,
            content: content,
            fileType: fileType,
            createdAt: self.createdAt,
            progress: progress,
            chapterIds: self.articleIds
        )
    }
    
    // 其他方法...
}
```

## 管理类修改

### ArticleListManager

1. 添加`userLists`计算属性，过滤掉文档创建的列表：

```swift
var userLists: [ArticleList] {
    return lists.filter { !$0.isDocument }
}
```

2. 修改初始化和列表操作方法，确保只对用户列表进行操作：

```swift
// 初始化时使用userLists
if userLists.isEmpty {
    addList(name: "所有文章")
}

// 加载选择的列表时确保它是用户列表
if lists.contains(where: { $0.id == selectedId && !$0.isDocument }) {
    selectedListId = selectedId
} else {
    selectedListId = userLists.first?.id
}
```

3. 添加新方法获取包含指定文章的用户列表：

```swift
func userListsContainingArticle(articleId: UUID) -> [ArticleList] {
    return lists.filter { !$0.isDocument && $0.articleIds.contains(articleId) }
}
```

### ArticleManager

1. 更新方法以支持列表ID：

```swift
func addArticle(title: String, content: String, listId: UUID? = nil) {
    // 如果标题为空，使用"新文章"作为默认标题
    let articleTitle = title.isEmpty ? "新文章" : title
    let newArticle = Article(title: articleTitle, content: content, createdAt: Date(), listId: listId)
    articles.append(newArticle)
    
    // 如果提供了列表ID，将文章添加到列表中
    if let listId = listId {
        ArticleListManager.shared.addArticleToList(articleId: newArticle.id, listId: listId)
    }
    
    saveArticles()
}
```

2. 增强删除文章逻辑，确保从所有列表中移除：

```swift
func deleteArticle(at indexSet: IndexSet) {
    // 从所有列表中移除这些文章
    for index in indexSet {
        let article = articles[index]
        
        // 先从文章可能所属的列表中移除
        if let listId = article.listId {
            ArticleListManager.shared.removeArticleFromList(articleId: article.id, listId: listId)
        }
        
        // 同时从所有可能包含该文章的列表中移除
        for list in ArticleListManager.shared.lists {
            if list.articleIds.contains(article.id) {
                ArticleListManager.shared.removeArticleFromList(articleId: article.id, listId: list.id)
            }
        }
    }
    
    articles.remove(atOffsets: indexSet)
    saveArticles()
}
```

3. 添加获取指定列表中所有文章的方法：

```swift
func articlesInList(listId: UUID) -> [Article] {
    return articles.filter { $0.listId == listId || ArticleListManager.shared.isArticleInList(articleId: $0.id, listId: listId) }
}
```

### DocumentLibraryManager

1. 确保每个文档在ArticleListManager中有对应记录：

```swift
private func ensureDocumentInListManager(_ document: Document) {
    // 检查ArticleListManager中是否有对应ID的列表
    let listManager = ArticleListManager.shared
    if !listManager.lists.contains(where: { $0.id == document.id }) {
        // 如果没有，创建一个新的列表
        let newList = ArticleList(
            id: document.id,
            name: document.title,
            createdAt: document.createdAt,
            articleIds: document.chapterIds,
            isDocument: true
        )
        
        // 将新列表添加到ArticleListManager
        listManager.lists.append(newList)
        listManager.saveLists()
    } else {
        // 如果已有，更新列表信息
        if let index = listManager.lists.firstIndex(where: { $0.id == document.id }) {
            listManager.lists[index].name = document.title
            listManager.lists[index].articleIds = document.chapterIds
            listManager.saveLists()
        }
    }
}
```

2. 处理文档删除时同时删除相关列表：

```swift
func deleteDocument(at indexSet: IndexSet) {
    // 获取要删除的文档ID
    let documentsToDelete = indexSet.map { self.documents[$0] }
    
    // 从文档列表中移除
    documents.remove(atOffsets: indexSet)
    saveDocuments()
    
    // 从ArticleListManager中移除对应的列表
    let listManager = ArticleListManager.shared
    for document in documentsToDelete {
        if let index = listManager.lists.firstIndex(where: { $0.id == document.id }) {
            listManager.lists.remove(at: index)
        }
    }
    listManager.saveLists()
}
```

3. 添加章节到文档的方法：

```swift
func addChapterToDocument(documentId: UUID, chapterId: UUID) {
    if let index = documents.firstIndex(where: { $0.id == documentId }) {
        if !documents[index].chapterIds.contains(chapterId) {
            documents[index].chapterIds.append(chapterId)
            saveDocuments()
            
            // 同时更新ArticleListManager中的记录
            let listManager = ArticleListManager.shared
            if let listIndex = listManager.lists.firstIndex(where: { $0.id == documentId }) {
                if !listManager.lists[listIndex].articleIds.contains(chapterId) {
                    listManager.lists[listIndex].articleIds.append(chapterId)
                    listManager.saveLists()
                }
            }
        }
    }
}
```

### ChapterManager

1. 修改章节创建逻辑，设置正确的列表ID：

```swift
private func createDefaultChapter(content: String, documentId: UUID) -> Chapter {
    return Chapter(
        title: "完整内容",
        content: content,
        startIndex: 0,
        endIndex: content.count,
        documentId: documentId,
        listId: documentId // 设置章节所属列表ID为文档ID
    )
}
```

2. 增强章节保存逻辑，更新相关列表：

```swift
private func saveChapters(_ chapters: [Chapter], for documentId: UUID) {
    // 设置每个章节的documentId和listId
    var updatedChapters = chapters
    for i in 0..<updatedChapters.count {
        updatedChapters[i].documentId = documentId
        updatedChapters[i].listId = documentId // 使用文档ID作为列表ID
    }
    
    // 保存章节数据
    if let encoded = try? JSONEncoder().encode(updatedChapters) {
        UserDefaults.standard.set(encoded, forKey: saveKey + documentId.uuidString)
        
        // 更新文档的章节ID列表
        let chapterIds = updatedChapters.map { $0.id }
        
        // 更新文档库中的章节ID
        let documentLibrary = DocumentLibraryManager.shared
        if let document = documentLibrary.findDocument(by: documentId) {
            var updatedDocument = document
            updatedDocument.chapterIds = chapterIds
            documentLibrary.updateDocument(updatedDocument)
        }
        
        // 确保将章节添加到对应的ArticleList中
        for chapter in updatedChapters {
            ArticleListManager.shared.addArticleToList(articleId: chapter.id, listId: documentId)
        }
    }
}
```

## UI视图修改

所有使用ArticleListManager的视图都进行了修改，确保它们使用userLists而非lists属性：

### ArticleListView
```swift
// 列表选择器下拉菜单
ForEach(listManager.userLists) { list in
    // ...
}

// 根据当前选择的列表过滤文章
if listManager.userLists.first?.id == selectedList.id {
    // ...
}
```

### EditListsView
```swift
List {
    ForEach(listManager.userLists) { list in
        // ...
        if list.id != listManager.userLists.first?.id {
            // ...
        }
    }
}
```

### EditArticleView
```swift
Section(header: Text("所属列表")) {
    ForEach(listManager.userLists) { list in
        // 不显示"所有文章"列表的选项
        if list.id != listManager.userLists.first?.id {
            // ...
        }
    }
}
```

### AddArticleView
```swift
Picker("选择列表", selection: $selectedListId) {
    ForEach(listManager.userLists) { list in
        Text(list.name).tag(list.id as UUID?)
    }
}

// 在保存逻辑中
if let listId = selectedListId, 
   let articleId = newArticle?.id,
   listManager.userLists.first?.id != listId {
    // ...
}
```

## 重构效果

1. **统一数据结构**：文档和文章列表现在共享相同的数据结构模式，使代码更加一致。
2. **明确数据关系**：文章和章节都有明确的所属列表ID，列表中包含文章/章节ID。
3. **UI隔离**：用户界面上只显示用户创建的列表，文档不会显示为文章列表。
4. **功能保持**：在保持原有功能的同时，使代码更加清晰和可维护。

## 总结

通过这次重构，应用程序解决了原有的设计问题，特别是在ID处理方面的混乱。现在文档和文章列表有了清晰的层级关系，同时在UI上保持了简洁的用户体验。代码的可维护性和可扩展性也得到了显著提高。 