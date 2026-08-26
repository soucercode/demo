import SwiftUI

struct SettingsView: View {
    @Environment(\.appLanguage) private var environmentLanguage
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false
    @State private var showUpdate = false

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .english }

    var body: some View {
        NavigationStack {
            ZStack {
                TechBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.cyan)
                                .frame(width: 54, height: 54)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language == .vietnamese ? "Cài Đặt" : "Settings")
                                    .font(.largeTitle.weight(.bold))
                                Text("Proxy SHOP DHP V1.0")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack {
                            Image(systemName: "globe").foregroundStyle(.cyan)
                            Text(language == .vietnamese ? "Ngôn Ngữ" : "Language").font(.headline)
                            Spacer()
                            Picker("", selection: $languageCode) {
                                Text("Tiếng Việt").tag(AppLanguage.vietnamese.rawValue)
                                Text("English").tag(AppLanguage.english.rawValue)
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))

                        SettingLine(icon: "arrow.triangle.2.circlepath", color: .blue, title: language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates", subtitle: language == .vietnamese ? "So sánh với server" : "Compare with server") { showUpdate = true }
                        SettingLine(icon: "trash.fill", color: .orange, title: language == .vietnamese ? "Xóa Bộ Nhớ Đệm" : "Clear Cache", subtitle: language == .vietnamese ? "File tạm + ảnh đã tải" : "Temporary files + downloaded images") { }
                        SettingLine(icon: "square.and.arrow.up", color: .green, title: language == .vietnamese ? "Chia Sẻ Ứng Dụng" : "Share App", subtitle: language == .vietnamese ? "Gửi link tải cho bạn bè" : "Send download link to friends") { }
                        SettingLine(icon: "info.circle.fill", color: .purple, title: language == .vietnamese ? "Thông Tin Ứng Dụng" : "App Information", subtitle: "Version · Device · ID") { showInfo = true }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(language == .vietnamese ? "Cài Đặt" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left") } } }
            .sheet(isPresented: $showInfo) { Text("Proxy SHOP DHP V1.0\n\(AppInfo.hardwareDisplayName)\n\(AppInfo.osVersion)\n\(AppInfo.osBuild)").padding() }
            .alert(language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates", isPresented: $showUpdate) { Button("OK", role: .cancel) {} } message: { Text("Proxy SHOP DHP V1.0") }
        }
    }
}

private struct SettingLine: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}
