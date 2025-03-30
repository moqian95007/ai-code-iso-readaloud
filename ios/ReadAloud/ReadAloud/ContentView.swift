//
//  ContentView.swift
//  ReadAloud
//
//  Created by moqian on 2025/3/27.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @ObservedObject private var navigationState = ReadAloudNavigationState.shared
    @ObservedObject private var playbackManager = GlobalPlaybackManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部搜索框
                SearchBar(searchText: $viewModel.searchText)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 文件朗读区域
                        DocumentReadingSection()
                    }
                    .padding(.top, 10)
                }
                
                // 底部导航栏
                BottomTabBar(selectedTab: $viewModel.selectedTab)
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

// 创建 ContentViewModel 类
class ContentViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedTab: Int = 0
}

#Preview {
    ContentView()
}
