import SwiftUI

struct DocumentItem: View {
    let document: Document
    let viewModel: DocumentsViewModel
    
    var body: some View {
        NavigationLink(destination: DocumentReaderView(documentTitle: document.title, document: document, viewModel: viewModel)) {
            VStack {
                // 文档封面图
                coverView
                
                Text(document.title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .center)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 封面视图
    private var coverView: some View {
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
    }
} 