import SwiftUI

struct SettingsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppLogo()

                    VStack(alignment: .leading, spacing: 3) {
                        Text("CheatiOS DSW").font(.headline)
                        Text(language.text("common.version", appVersion))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            /* Tạm ẩn mục Ngôn ngữ
            Section(language.text("settings.language")) {
                Picker(language.text("settings.language"), selection: $languageCode) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            */

            Section(language.text("common.device")) {
                LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
            }

            Section {
                HStack {
                    Text(language.text("settings.current_version"))
                    Spacer()
                    Label(
                        language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"),
                        systemImage: appState.isSupported ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                }
                LabeledContent("iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range)
                VStack(alignment: .leading, spacing: 8) {
                    Text("iOS 27.0")
                        .font(.body)
                    ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { version in
                        Text(
                            language.text(
                                "settings.beta_build",
                                Int64(version.beta),
                                version.build
                            )
                        )
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(language.text("settings.verified_versions"))
            } footer: {
                Text(language.text("settings.supported_versions_footer"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(TechBackground())
        .tint(AppTheme.accent)
        .navigationTitle(language.text("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }
}
