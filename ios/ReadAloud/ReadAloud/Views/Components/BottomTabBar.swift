import SwiftUI

struct BottomTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack {
            Spacer()
            
            tabButton(index: 0, icon: "house.fill", text: "首页")
            
            Spacer()
            
            tabButton(index: 1, icon: "person", text: "我的")
            
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
    
    private func tabButton(index: Int, icon: String, text: String) -> some View {
        Button(action: {
            selectedTab = index
        }) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(text)
                    .font(.caption)
            }
            .foregroundColor(selectedTab == index ? .red : .gray)
        }
    }
} 