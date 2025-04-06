import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 用户头像
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .padding(.top, 50)
                
                // 用户名
                Text("用户名")
                    .font(.title)
                    .fontWeight(.bold)
                
                // 分割线
                Divider()
                    .padding(.horizontal)
                
                // 设置项目列表
                List {
                    settingRow(icon: "gear", title: "设置")
                    settingRow(icon: "star.fill", title: "我的收藏")
                    settingRow(icon: "arrow.down.circle.fill", title: "下载管理")
                    settingRow(icon: "moon.fill", title: "深色模式")
                    settingRow(icon: "questionmark.circle", title: "帮助与反馈")
                    settingRow(icon: "info.circle", title: "关于我们")
                }
                .listStyle(InsetGroupedListStyle())
                
                Spacer()
            }
            .navigationBarTitle("我的", displayMode: .inline)
        }
    }
    
    // 设置行
    private func settingRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(title)
                .padding(.leading, 5)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
} 