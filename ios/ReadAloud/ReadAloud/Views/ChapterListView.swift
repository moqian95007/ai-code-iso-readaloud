import SwiftUI

struct ChapterListView: View {
    @ObservedObject var synthesizer: SpeechSynthesizer
    @Binding var showChapterList: Bool
    @State private var searchText: String = ""
    @State private var processingChapterJump: Bool = false
    
    var body: some View {
        VStack {
            // 顶部搜索栏和标题
            HStack {
                Text("章节列表")
                    .font(.headline)
                    .padding(.leading)
                
                Spacer()
                
                Button("关闭") {
                    print("【UI交互】关闭章节列表")
                    showChapterList = false
                }
                .padding(.trailing)
            }
            .padding(.top)
            
            // 章节列表
            if synthesizer.getChapters().isEmpty {
                VStack {
                    Spacer()
                    Text("当前文档无章节信息")
                        .foregroundColor(.gray)
                        .font(.callout)
                    Text("已自动按1000字分段")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.top, 5)
                    Spacer()
                }
            } else {
                // 显示找到的章节数
                HStack {
                    Text("共 \(synthesizer.getChapters().count) 章")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 5)
                
                List {
                    ForEach(0..<synthesizer.getChapters().count, id: \.self) { index in
                        let chapter = synthesizer.getChapters()[index]
                        let isCurrentChapter = index == synthesizer.getCurrentChapterIndex()
                        
                        Button(action: {
                            // 简化处理流程，确保直接响应
                            print("【UI交互】点击跳转至章节: \(chapter.title)，索引: \(index)，总章节数: \(synthesizer.getChapters().count)")
                            
                            // 立即执行跳转并强制 UI 更新
                            DispatchQueue.main.async {
                                synthesizer.jumpToChapter(index)
                                
                                // 强制 UI 刷新
                                synthesizer.objectWillChange.send()
                                
                                // 短暂延迟后关闭列表 - 稍微延长时间以确保滚动完成
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showChapterList = false
                                }
                            }
                        }) {
                            HStack {
                                Text("\(index+1). \(chapter.title)")
                                    .foregroundColor(isCurrentChapter ? .blue : .primary)
                                    .font(isCurrentChapter ? .headline : .body)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if isCurrentChapter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .background(isCurrentChapter ? Color.blue.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id("\(index)")
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(width: 300, height: 400)
        .onAppear {
            print("【章节列表】显示所有章节，共\(synthesizer.getChapters().count)章")
            
            // 调试信息：输出前5个章节标题
            for i in 0..<min(5, synthesizer.getChapters().count) {
                print("【章节列表】章节\(i+1): \(synthesizer.getChapters()[i].title)")
            }
        }
    }
}

// 章节行视图
struct ChapterRow: View {
    let chapter: Chapter
    let isCurrentChapter: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(chapter.title)
                    .foregroundColor(isCurrentChapter ? .blue : .primary)
                    .font(isCurrentChapter ? .headline : .body)
                
                Spacer()
                
                if isCurrentChapter {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
} 