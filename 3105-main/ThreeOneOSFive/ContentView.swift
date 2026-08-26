import SwiftUI
import UIKit

// MARK: - License state / API

@MainActor
final class ProxyDemoState: ObservableObject {
    @Published var activatedKey: String? = UserDefaults.standard.string(forKey: "proxy.demo.activatedKey")
    @Published var licenseExpiryText: String? = UserDefaults.standard.string(forKey: "proxy.demo.expiryText")
    @Published var toast: String?
    @Published var isBusy = false
    @Published var isActivated = false
    @Published var activationChecked = false

    private let serverURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "LicenseServerURL") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        return URL(string: "http://192.168.0.193:5050")!
    }()

    var deviceID: String {
        // IDFV là định danh theo app/vendor. Nếu API iOS không cung cấp, lưu UUID riêng của app.
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            return vendor.uppercased()
        }
        let key = "proxy.demo.deviceID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let created = UUID().uuidString.uppercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    func showToast(_ message: String) {
        toast = message
    }

    func copyDeviceID() {
        UIPasteboard.general.string = deviceID
        showToast("Đã sao chép Device ID")
    }

    func activate(_ key: String) async {
        guard !isBusy else { return }

        let cleaned = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        // Hỗ trợ prefix tự do từ server: DHPDEPTRAI-XXXXXX, DHP-IPA-XXXXXX...
        let valid = cleaned.range(
            of: #"^[A-Z0-9-]{1,24}-[A-Z0-9]{6}$"#,
            options: .regularExpression
        ) != nil

        guard valid else {
            showToast("⚠️ Key không đúng định dạng")
            return
        }

        isBusy = true
        defer { isBusy = false }

        // Trạng thái loading 3 giây theo giao diện demo.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        do {
            let result = try await LicenseAPI.check(
                baseURL: serverURL,
                key: cleaned,
                deviceID: deviceID
            )

            guard result.ok else {
                isActivated = false
                showToast("⚠️ \(result.error ?? "Key không hợp lệ")")
                return
            }

            activatedKey = cleaned
            licenseExpiryText = result.expires ?? "Vĩnh viễn"
            isActivated = true

            UserDefaults.standard.set(cleaned, forKey: "proxy.demo.activatedKey")
            UserDefaults.standard.set(licenseExpiryText, forKey: "proxy.demo.expiryText")
            showToast("Kích hoạt thành công")
        } catch {
            isActivated = false
            showToast("⚠️ Không kết nối được License Server")
        }
    }

    func validateStoredKey() async {
        guard !activationChecked else { return }
        activationChecked = true

        guard let key = activatedKey, !key.isEmpty else {
            isActivated = false
            return
        }

        do {
            let result = try await LicenseAPI.check(
                baseURL: serverURL,
                key: key,
                deviceID: deviceID
            )
            if result.ok {
                isActivated = true
                licenseExpiryText = result.expires ?? licenseExpiryText
                UserDefaults.standard.set(licenseExpiryText, forKey: "proxy.demo.expiryText")
            } else {
                isActivated = false
                activatedKey = nil
                UserDefaults.standard.removeObject(forKey: "proxy.demo.activatedKey")
                showToast("⚠️ \(result.error ?? "Key không còn hợp lệ")")
            }
        } catch {
            // Đã từng kích hoạt thành công thì giữ phiên local khi server tạm thời không reachable.
            isActivated = true
        }
    }

    func clearCache() {
        let fm = FileManager.default
        let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProxySHOPDHP", isDirectory: true)
        try? fm.removeItem(at: cacheURL)
        showToast("Đã xóa bộ nhớ đệm của ứng dụng")
    }

    func writeDemoCache(for feature: String) {
        let fm = FileManager.default
        let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProxySHOPDHP", isDirectory: true)
            .appendingPathComponent("features", isDirectory: true)
        try? fm.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        let safeName = feature.replacingOccurrences(of: " ", with: "_")
        let file = cacheURL.appendingPathComponent("\(safeName).demo.json")
        let data = Data("{\"feature\":\"\(feature)\",\"status\":\"demo-enabled\"}".utf8)
        try? data.write(to: file, options: .atomic)
    }
}

struct LicenseAPIResult: Decodable {
    let ok: Bool
    let status: String?
    let error: String?
    let expires: String?
}

enum LicenseAPI {
    static func check(baseURL: URL, key: String, deviceID: String) async throws -> LicenseAPIResult {
        var url = baseURL
        if url.path.hasSuffix("/") {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("api/key/check")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key,
            "device": deviceID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        let result = try decoder.decode(LicenseAPIResult.self, from: data)
        if !(200...499).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return result
    }
}

// MARK: - Home

struct ContentView: View {
    @StateObject private var state = ProxyDemoState()

    var body: some View {
        Group {
            if state.isActivated {
                ProxyShopHomeView(state: state)
            } else {
                LicenseGateView(state: state)
            }
        }
        .task {
            await state.validateStoredKey()
        }
    }
}

struct LicenseGateView: View {
    @ObservedObject var state: ProxyDemoState
    @State private var key = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("License Key")
                                .font(.largeTitle.weight(.bold))
                            Text("Nhập key để kích hoạt ứng dụng.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
                            InfoLine(icon: "iphone", color: .cyan, title: "Device", value: AppInfo.hardwareDisplayName)
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red)
                                    .frame(width: 12, height: 12)
                                Text(ExploitSupportPolicy.isCurrentOSSupported ? "Có Hỗ Trợ" : "Không Hỗ Trợ")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(ExploitSupportPolicy.isCurrentOSSupported ? .green : .red)
                            }
                        }
                        .padding(18)
                        .proxyCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Thiết bị này:")
                                .font(.headline)
                            Text(state.deviceID)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Button {
                                state.copyDeviceID()
                            } label: {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("Sao chép Device ID")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 10) {
                                TextField("Nhập / dán key...", text: $key)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()

                                Button {
                                    key = UIPasteboard.general.string ?? ""
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                            Button {
                                Task { await state.activate(key) }
                            } label: {
                                HStack(spacing: 9) {
                                    if state.isBusy {
                                        ProgressView().tint(.white)
                                    }
                                    Text(state.isBusy ? "Đang kiểm tra..." : "Kích hoạt")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [.purple, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 18)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(state.isBusy)
                        }
                        .padding(18)
                        .proxyCard()
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) {
                if let toast = state.toast {
                    ToastPill(text: toast)
                        .padding(.top, 8)
                }
            }
        }
    }
}

struct ProxyShopHomeView: View {
    @ObservedObject var state: ProxyDemoState
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        deviceSupportCard
                        gameCards
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { GearButton() }
                }
            }
            .sheet(isPresented: $showSettings) {
                ProxySettingsView(state: state)
            }
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) {
                if let toast = state.toast {
                    ToastPill(text: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .tint(.cyan)
    }

    private var deviceSupportCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
            InfoLine(icon: "iphone", color: .cyan, title: "Device", value: AppInfo.hardwareDisplayName)
            HStack(spacing: 10) {
                Circle()
                    .fill(ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: (ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red).opacity(0.7), radius: 8)
                Text(ExploitSupportPolicy.isCurrentOSSupported ? "Có Hỗ Trợ" : "Không Hỗ Trợ")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ExploitSupportPolicy.isCurrentOSSupported ? .green : .red)
                Spacer()
                if let key = state.activatedKey {
                    Text(key)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(18)
        .proxyCard()
    }

    private var gameCards: some View {
        HStack(spacing: 12) {
            GameLauncherCard(title: "Free Fire Max", imageName: "FreeFireMax", accent: Color(red: 0.05, green: 0.52, blue: 1.0), bundleID: "com.dts.freefiremax", state: state)
            GameLauncherCard(title: "Free Fire", imageName: "FreeFire", accent: Color(red: 1.0, green: 0.48, blue: 0.08), bundleID: "com.dts.freefireth", state: state)
        }
    }
}

struct GameLauncherCard: View {
    let title: String
    let imageName: String
    let accent: Color
    let bundleID: String
    @ObservedObject var state: ProxyDemoState
    @State private var showGame = false

    var body: some View {
        Button {
            guard state.isActivated else {
                state.showToast("⚠️ Bạn phải nhập Key trước")
                return
            }
            showGame = true
        } label: {
            VStack(spacing: 0) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.68), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGame) {
            GameDemoView(title: title, imageName: imageName, bundleID: bundleID, state: state)
        }
    }
}

// MARK: - Settings

struct ProxySettingsView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showInfo = false
    @State private var showUpdate = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        languageRow
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            color: .blue,
                            title: language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates",
                            subtitle: language == .vietnamese ? "So sánh với server" : "Compare with server"
                        ) {
                            showUpdate = true
                        }
                        SettingsRow(
                            icon: "trash.fill",
                            color: .orange,
                            title: language == .vietnamese ? "Xóa Bộ Nhớ Đệm" : "Clear Cache",
                            subtitle: language == .vietnamese ? "File tạm + ảnh đã tải" : "Temporary files + downloaded images"
                        ) {
                            state.clearCache()
                        }
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            color: .green,
                            title: language == .vietnamese ? "Chia Sẻ Ứng Dụng" : "Share App",
                            subtitle: language == .vietnamese ? "Gửi link tải cho bạn bè" : "Send download link to friends"
                        ) {
                            state.showToast(language == .vietnamese ? "Đã sẵn sàng chia sẻ" : "Ready to share")
                        }
                        SettingsRow(
                            icon: "info.circle.fill",
                            color: .purple,
                            title: language == .vietnamese ? "Thông Tin Ứng Dụng" : "App Information",
                            subtitle: "Version · Device · ID"
                        ) {
                            showInfo = true
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(language == .vietnamese ? "Cài Đặt" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") }
                }
            }
            .sheet(isPresented: $showInfo) { AppInfoView(state: state) }
            .alert(language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates", isPresented: $showUpdate) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(language == .vietnamese ? "Bạn đang dùng Proxy SHOP DHP V1.0." : "You are using Proxy SHOP DHP V1.0.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 31))
                .foregroundStyle(.cyan)
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(language == .vietnamese ? "Cài Đặt" : "Settings")
                    .font(.largeTitle.weight(.bold))
                Text("Proxy SHOP DHP V1.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private var languageRow: some View {
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
        .proxyCard()
    }
}

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).frame(width: 54, height: 54).background(color.gradient, in: RoundedRectangle(cornerRadius: 15)).shadow(color: color.opacity(0.35), radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .proxyCard()
    }
}

// MARK: - Game demo screen

struct DemoFeature: Identifiable {
    let id = UUID()
    let name: String
    let available: Bool
}

struct GameDemoView: View {
    let title: String
    let imageName: String
    let bundleID: String
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var busyIndex: Int?
    @State private var enabled = Set<Int>()

    private let proxyFeatures: [DemoFeature] = [
        DemoFeature(name: "Proxy Aim Body", available: false),
        DemoFeature(name: "Proxy Aim Neck V2", available: true),
        DemoFeature(name: "Proxy Aim Neck V1", available: false),
        DemoFeature(name: "Proxy Aim Drag", available: false),
        DemoFeature(name: "Magic V4", available: true)
    ]

    private let locationFeatures: [DemoFeature] = [
        DemoFeature(name: "Định vị súng", available: true),
        DemoFeature(name: "Định vị nâng cao", available: false)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .cyan.opacity(0.18), radius: 14, y: 5)

                        Text(title)
                            .font(.largeTitle.weight(.bold))

                        Text(bundleID)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)

                        Button(action: openGame) {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("MỞ GAME")
                                    .font(.title3.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)

                        tabBar

                        Group {
                            switch selectedTab {
                            case 0:
                                featureList(features: proxyFeatures)
                            case 1:
                                featureList(features: locationFeatures)
                            default:
                                featureList(features: [])
                            }
                        }
                        .id(selectedTab)
                        .transition(.opacity)
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        CircleIcon(systemName: "chevron.left")
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            GameTab(
                title: "Proxy",
                icon: "bolt.fill",
                active: selectedTab == 0,
                activeColor: .cyan
            ) {
                selectTab(0)
            }

            GameTab(
                title: "Định Vị",
                icon: "location.fill",
                active: selectedTab == 1,
                activeColor: .purple
            ) {
                selectTab(1)
            }

            GameTab(
                title: "Mod NV",
                icon: "person.2.fill",
                active: selectedTab == 2,
                activeColor: .green
            ) {
                selectTab(2)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func selectTab(_ tab: Int) {
        guard selectedTab != tab else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            selectedTab = tab
        }
    }

    private func featureList(features: [DemoFeature]) -> some View {
        VStack(spacing: 10) {
            ForEach(features.indices, id: \.self) { index in
                featureRow(features[index], index: index)
            }

            if features.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                    Text("Mod NV")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .proxyCard()
            }
        }
    }

    private func featureRow(_ feature: DemoFeature, index: Int) -> some View {
        let accent = AppTheme.rowColor(index + selectedTab * 2)

        return HStack(spacing: 12) {
            Image(systemName: feature.available ? "bolt.fill" : "wrench.and.screwdriver.fill")
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(feature.name)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            if busyIndex == index {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(accent)
                    .frame(width: 34, height: 34)
                    .transition(.opacity)
            } else {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { enabled.contains(index) },
                        set: { value in
                            handleFeature(feature, index: index, value: value)
                        }
                    )
                )
                .labelsHidden()
                .tint(accent)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func handleFeature(_ feature: DemoFeature, index: Int, value: Bool) {
        guard busyIndex == nil else { return }

        busyIndex = index

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            if feature.available {
                if value {
                    enabled.insert(index)
                } else {
                    enabled.remove(index)
                }
            } else {
                enabled.remove(index)
            }

            withAnimation(.easeOut(duration: 0.16)) {
                busyIndex = nil
            }
        }
    }

    private func openGame() {
        let scheme = title == "Free Fire Max" ? "freefiremax" : "freefire"
        guard let url = URL(string: "\(scheme)://") else { return }
        UIApplication.shared.open(url)
    }
}

struct GameTab: View {
    let title: String
    let icon: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))

                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(active ? activeColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                active ? activeColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(activeColor.opacity(0.42), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - License UI

struct LicenseKeyView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LicenseGateView(state: state)
    }
}

// MARK: - Policy / Info



struct PolicyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Image(systemName: "shield.fill").font(.system(size: 42)).foregroundStyle(.cyan).padding(.top, 8)
                        Text("CHÍNH SÁCH & ĐIỀU KHOẢN\nSỬ DỤNG").font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        Text("Vui lòng đọc kỹ trước khi sử dụng dịch vụ").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 14) {
                            PolicySection(icon: "key.fill", color: .cyan, title: "Quy Định License Key & HWID", text: "Mỗi key có thể được giới hạn số thiết bị theo cấu hình server. Ứng dụng dùng Device ID/IDFV thay cho UDID hệ thống mà app không có quyền đọc.")
                            PolicySection(icon: "exclamationmark.shield.fill", color: .orange, title: "Tuyên Bố Miễn Trừ Trách Nhiệm", text: "Người dùng chịu trách nhiệm tuân thủ điều khoản của nền tảng và dịch vụ liên quan.")
                            PolicySection(icon: "lock.fill", color: .green, title: "Hướng Dẫn An Toàn & Bảo Mật", text: "Không nhúng tài khoản admin hoặc mật khẩu server vào IPA/public repository. Chỉ cấu hình URL API license trong app.")
                        }
                        .padding(16).proxyCard()
                        Button { dismiss() } label: { Text("✓ Tôi Đã Hiểu và Đồng Ý").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17).background(LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain)
                    }
                    .padding(18)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } } }
            .preferredColorScheme(.dark)
        }
    }
}

struct PolicySection: View {
    let icon: String; let color: Color; let title: String; let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(color).frame(width: 40, height: 40).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12)); Text(title).font(.headline) }
            Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

struct AppInfoView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack { ProxyBackground(); VStack(spacing: 14) {
                InfoLine(icon: "app.fill", color: .purple, title: "Ứng dụng", value: "Proxy SHOP DHP")
                InfoLine(icon: "number", color: .cyan, title: "Phiên bản", value: "1.0")
                InfoLine(icon: "iphone", color: .cyan, title: "Thiết bị", value: AppInfo.hardwareDisplayName)
                InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
                InfoLine(icon: "person.crop.circle", color: .green, title: "Device ID", value: state.deviceID)
                Spacer()
            }.padding(18) }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } } }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Reusable UI

struct ProxyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.025, blue: 0.11), .black], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.purple.opacity(0.20), .clear], center: .center, startRadius: 0, endRadius: 460)
            GridOverlay().stroke(Color.white.opacity(0.035), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let spacing: CGFloat = 28
        stride(from: 0, through: rect.width, by: spacing).forEach { x in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height)) }
        stride(from: 0, through: rect.height, by: spacing).forEach { y in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)) }
        return p
    }
}

struct InfoLine: View {
    let icon: String; let color: Color; let title: String; let value: String
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(color).frame(width: 24); Text(title).foregroundStyle(.secondary); Spacer(minLength: 8); Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75) } }
}

struct GearButton: View {
    var body: some View { Image(systemName: "gearshape.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.cyan).frame(width: 52, height: 52).background(Color.white.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)).shadow(color: .cyan.opacity(0.15), radius: 12) }
}

struct CircleIcon: View {
    let systemName: String
    var body: some View { Image(systemName: systemName).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 46, height: 46).background(Color.white.opacity(0.06), in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)) }
}

struct DemoMessageCard: View {
    let title: String; let text: String; let icon: String
    var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.cyan); Text(title).font(.title3.weight(.bold)); Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(28).proxyCard() }
}

struct ToastPill: View {
    let text: String
    var body: some View { HStack(spacing: 8) { Image(systemName: (text.contains("⚠️") || text.localizedCaseInsensitiveContains("không") || text.localizedCaseInsensitiveContains("sai") || text.localizedCaseInsensitiveContains("lỗi")) ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").foregroundStyle((text.contains("⚠️") || text.localizedCaseInsensitiveContains("không") || text.localizedCaseInsensitiveContains("sai") || text.localizedCaseInsensitiveContains("lỗi")) ? .yellow : .green); Text(text).font(.footnote.weight(.semibold)) }.padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.12))) }
}

private struct ProxyCardModifier: ViewModifier {
    func body(content: Content) -> some View { content.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.13), lineWidth: 1)).shadow(color: .purple.opacity(0.08), radius: 18) }
}

extension View { func proxyCard() -> some View { modifier(ProxyCardModifier()) } }
