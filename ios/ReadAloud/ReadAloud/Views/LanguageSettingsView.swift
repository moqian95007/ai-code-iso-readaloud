import SwiftUI

struct LanguageSettingsView: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    @Binding var isPresented: Bool
    @State private var selectedLanguage: AppLanguage
    @State private var showRestartAlert = false
    @State private var previousLanguage: AppLanguage
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        let currentLanguage = LanguageManager.shared.currentLanguage
        self._selectedLanguage = State(initialValue: currentLanguage)
        self._previousLanguage = State(initialValue: currentLanguage)
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(AppLanguage.allCases) { language in
                    Button(action: {
                        if selectedLanguage != language {
                            previousLanguage = selectedLanguage
                            selectedLanguage = language
                            languageManager.setLanguage(language)
                            showRestartAlert = true
                        }
                    }) {
                        HStack {
                            Text(language.displayName)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle(Text("language_settings".localized), displayMode: .inline)
            .navigationBarItems(
                trailing: Button("cancel".localized) {
                    isPresented = false
                }
            )
            .alert(isPresented: $showRestartAlert) {
                Alert(
                    title: Text("language_changed".localized),
                    message: Text("language_restart_message".localized),
                    primaryButton: .default(Text("OK")) {
                        // 关闭弹窗
                        isPresented = false
                    },
                    secondaryButton: .cancel(Text("cancel".localized)) {
                        // 恢复原来的语言设置
                        selectedLanguage = previousLanguage
                        languageManager.setLanguage(previousLanguage)
                    }
                )
            }
            .onAppear {
                // 确保显示最新的语言设置
                selectedLanguage = languageManager.currentLanguage
                previousLanguage = languageManager.currentLanguage
            }
        }
    }
}

struct LanguageSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        LanguageSettingsView(isPresented: .constant(true))
    }
} 