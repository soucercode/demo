import SwiftUI
import UIKit

// MARK: - Safe demo state / licensing

@MainActor
final class ProxyDemoState: ObservableObject {
    @Published var activatedKey: String? = UserDefaults.standard.string(forKey: "proxy.demo.activatedKey")
    @Published var licenseExpiry: Date? = UserDefaults.standard.object(forKey: "proxy.demo.expiry") as? Date
    @Published var toast: String?
    @Published var isBusy = false
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "proxy.license.serverURL") ?? ""

    var deviceID: String {
        // Modern iOS apps generally cannot read the hardware UDID. IDFV is used as the app-scoped device ID.
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            return vendor.uppercased()
        }
        let key = "proxy.demo.deviceID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let created = UUID().uuidString.uppercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    var isActivated: Bool {
        guard activatedKey != nil else { return false }
        guard let expiry = licenseExpiry else { return true }
        return expiry > Date()
    }

    func saveServerURL(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURL = cleaned
        UserDefaults.standard.set(cleaned, forKey: "proxy.license.serverURL")
        toast = cleaned.isEmpty ? "Đã tắt server license" : "Đã lưu server license"
    }

    func copyDeviceID() {
        UIPasteboard.general.string = deviceID
        toast = "Đã sao chép Device ID"
    }

    func activate(_ key: String) async {
        guard !isBusy else { return }
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.range(of: #"^DHP-IPA-[A-Z0-9]{6}$"#, options: .regularExpression) != nil else {
            toast = "Key phải có dạng DHP-IPA-XXXXXX"
            return
        }

        isBusy = true
        defer { isBusy = false }

        // Always show the requested 3-second activation state in the demo UI.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        if let base = URL(string: serverURL), !serverURL.isEmpty {
            do {
                let result = try await LicenseAPI.activate(baseURL: base, key: cleaned, deviceID: deviceID)
                guard result.success else {
                    toast = result.message
                    return
                }
                activatedKey = cleaned
                if let expiresAt = result.expiresAt {
                    licenseExpiry = expiresAt
                    UserDefaults.standard.set(expiresAt, forKey: "proxy.demo.expiry")
                } else {
                    licenseExpiry = nil
                    UserDefaults.standard.removeObject(forKey: "proxy.demo.expiry")
                }
                UserDefaults.standard.set(cleaned, forKey: "proxy.demo.activatedKey")
                toast = "Kích hoạt thành công • Proxy SHOP DHP V1.0"
            } catch {
                toast = "Không kết nối được server license"
            }
            return
        }

        // Offline demo fallback. No real server secret is embedded in the IPA.
        activatedKey = cleaned
        licenseExpiry = nil
        UserDefaults.standard.set(cleaned, forKey: "proxy.demo.activatedKey")
        toast = "Kích hoạt demo thành công • Proxy SHOP DHP V1.0"
    }

    func clearCache() {
        let fm = FileManager.default
        let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProxySHOPDHP", isDirectory: true)
        try? fm.removeItem(at: cacheURL)
        toast = "Đã xóa bộ nhớ đệm của ứng dụng"
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
    let success: Bool
    let message: String
    let expiresAt: Date?
}

enum LicenseAPI {
    static func activate(baseURL: URL, key: String, deviceID: String) async throws -> LicenseAPIResult {
        var url = baseURL
        if url.path.hasSuffix("/") {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("license/activate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key,
            "deviceId": deviceID,
            "appVersion": "1.0",
            "device": AppInfo.hardwareDisplayName,
            "ios": AppInfo.osVersion
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LicenseAPIResult.self, from: data)
    }
}

// MARK: - Home

struct ContentView: View {
    var body: some View { ProxyShopHomeView() }
}

struct ProxyShopHomeView: View {
    @StateObject private var state = ProxyDemoState()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
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
            .sheet(isPresented: $showSettings) { ProxySettingsView(state: state) }
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
                Text(ExploitSupportPolicy.currentSupportLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .proxyCard()
    }

    private var gameCards: some View {
        HStack(spacing: 14) {
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
        Button { showGame = true } label: {
            VStack(spacing: 0) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 30)
                    .padding(.bottom, 26)

                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(0.72), lineWidth: 1.4))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGame) { GameDemoView(title: title, imageName: imageName, bundleID: bundleID, state: state) }
    }
}

// MARK: - Settings

struct ProxySettingsView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.vietnamese.rawValue
    @State private var showLicense = false
    @State private var showPolicy = false
    @State private var showInfo = false
    @State private var showServer = false
    @State private var showUpdate = false

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .vietnamese }

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        languageRow
                        SettingsRow(icon: "arrow.triangle.2.circlepath", color: .blue, title: language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates", subtitle: language == .vietnamese ? "So sánh với server" : "Compare with server") { showUpdate = true }
                        SettingsRow(icon: "trash.fill", color: .orange, title: language == .vietnamese ? "Xóa Bộ Nhớ Đệm" : "Clear Cache", subtitle: language == .vietnamese ? "File tạm + ảnh đã tải" : "Temporary files + downloaded images") { state.clearCache() }
                        SettingsRow(icon: "square.and.arrow.up", color: .green, title: language == .vietnamese ? "Chia Sẻ Ứng Dụng" : "Share App", subtitle: language == .vietnamese ? "Gửi link tải cho bạn bè" : "Send download link to friends") { state.toast = language == .vietnamese ? "Link demo đã sẵn sàng" : "Demo link is ready" }
                        SettingsRow(icon: "info.circle.fill", color: .purple, title: language == .vietnamese ? "Thông Tin Ứng Dụng" : "App Information", subtitle: "Version · Device · ID") { showInfo = true }
                        SettingsRow(icon: "key.fill", color: .cyan, title: "License Key", subtitle: state.isActivated ? (language == .vietnamese ? "Đã kích hoạt" : "Activated") : (language == .vietnamese ? "Dán key để kích hoạt" : "Paste a key to activate")) { showLicense = true }
                        SettingsRow(icon: "server.rack", color: .indigo, title: "License Server", subtitle: state.serverURL.isEmpty ? "Chưa cấu hình" : state.serverURL) { showServer = true }
                        SettingsRow(icon: "shield.fill", color: .green, title: language == .vietnamese ? "Chính Sách & Điều Khoản" : "Policy & Terms", subtitle: language == .vietnamese ? "Xem quy định sử dụng" : "Usage rules") { showPolicy = true }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(language == .vietnamese ? "Cài Đặt" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } }
            }
            .sheet(isPresented: $showLicense) { LicenseKeyView(state: state) }
            .sheet(isPresented: $showPolicy) { PolicyView() }
            .sheet(isPresented: $showInfo) { AppInfoView(state: state) }
            .sheet(isPresented: $showServer) { LicenseServerView(state: state) }
            .alert(language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates", isPresented: $showUpdate) { Button("OK", role: .cancel) {} } message: { Text(language == .vietnamese ? "Bạn đang dùng Proxy SHOP DHP V1.0." : "You are using Proxy SHOP DHP V1.0.") }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.fill").font(.system(size: 31)).foregroundStyle(.cyan).frame(width: 54, height: 54).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(language == .vietnamese ? "Cài Đặt" : "Settings").font(.largeTitle.weight(.bold))
                Text("Proxy SHOP DHP V1.0").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        }
        .padding(16)
        .proxyCard()
    }
}

struct LicenseServerView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("License Server") {
                    TextField("https://example.com/api", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Lưu Server") {
                        state.saveServerURL(url)
                        dismiss()
                    }
                }
                Section {
                    Text("Không đặt tài khoản hoặc mật khẩu admin trong IPA. App chỉ cần API license; tài khoản admin phải nằm ở server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("License Server")
            .onAppear { url = state.serverURL }
        }
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
    let description: String
    let implemented: Bool
    let bundledFileName: String?
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
    @State private var showMaintenance = false
    @State private var maintenanceText = ""
    @State private var showOpenGameResult = false

    private let proxyFeatures: [DemoFeature] = [
        DemoFeature(name: "Proxy Aim Body", description: "File đang được bảo trì", implemented: false, bundledFileName: nil),
        DemoFeature(name: "Proxy Aim Neck V2", description: "Sẵn sàng", implemented: true, bundledFileName: "Aim Chest.3105"),
        DemoFeature(name: "Proxy Aim Neck V1", description: "File đang được bảo trì", implemented: false, bundledFileName: nil),
        DemoFeature(name: "Proxy Aim Drag", description: "File đang được bảo trì", implemented: false, bundledFileName: nil),
        DemoFeature(name: "Magic V4", description: "Sẵn sàng", implemented: true, bundledFileName: "Magic.3105")
    ]

    private let locationFeatures: [DemoFeature] = [
        DemoFeature(name: "Định vị súng", description: "Sẵn sàng", implemented: true, bundledFileName: "Chams Súng Green(1).3105"),
        DemoFeature(name: "Định vị nâng cao", description: "File đang được bảo trì", implemented: false, bundledFileName: nil)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        Image(imageName).resizable().scaledToFit().frame(width: 118, height: 118).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(color: .cyan.opacity(0.22), radius: 18)
                        Text(title).font(.largeTitle.weight(.bold))
                        Text(bundleID).font(.subheadline.monospaced()).foregroundStyle(.secondary)

                        Button(action: openGame) {
                            HStack(spacing: 10) { Image(systemName: "play.fill"); Text("MỞ GAME").font(.title3.weight(.bold)) }
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 22))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 0) {
                            GameTab(title: "Proxy", icon: "bolt.fill", active: selectedTab == 0) { selectedTab = 0 }
                            GameTab(title: "Định Vị", icon: "location.fill", active: selectedTab == 1) { selectedTab = 1 }
                            GameTab(title: "Mod NV", icon: "person.2.fill", active: selectedTab == 2) { selectedTab = 2 }
                        }
                        .proxyCard()

                        if selectedTab == 0 {
                            featureList(title: "CHỨC NĂNG PROXY", features: proxyFeatures)
                        } else if selectedTab == 1 {
                            featureList(title: "CHỨC NĂNG ĐỊNH VỊ", features: locationFeatures)
                        } else {
                            DemoMessageCard(title: "Mod NV", text: "File đang được bảo trì. Nút sẽ tự tắt sau khi kiểm tra.", icon: "person.2.fill")
                        }
                    }
                    .padding(16)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } } }
            .alert("File đang được bảo trì", isPresented: $showMaintenance) { Button("Đóng", role: .cancel) {} } message: { Text(maintenanceText) }
            .alert("Mở Game", isPresented: $showOpenGameResult) { Button("OK", role: .cancel) {} } message: { Text("iOS chỉ cho phép mở ứng dụng khác nếu ứng dụng đó cung cấp URL Scheme. Hãy cấu hình URL Scheme của game ở bước triển khai thực tế.") }
            .preferredColorScheme(.dark)
        }
    }

    private func featureList(title: String, features: [DemoFeature]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            ForEach(features.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(AppTheme.rowColor(index + 2))
                        .frame(width: 38, height: 38)
                        .background(AppTheme.rowColor(index + 2).opacity(0.16), in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(features[index].name).font(.headline)
                        Text(features[index].description)
                            .font(.caption)
                            .foregroundStyle(features[index].implemented ? .green.opacity(0.9) : .secondary)
                    }

                    Spacer()

                    // The 3-second loading state stays in the same switch position.
                    // There is no separate loading button.
                    if busyIndex == index {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.cyan)
                            .frame(width: 32, height: 32)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { enabled.contains(index) },
                            set: { value in handleFeature(features[index], index: index, value: value) }
                        ))
                        .labelsHidden()
                        .tint(.cyan)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }

            Text("Mục bảo trì sẽ tự tắt sau khi kiểm tra. Mục demo đã gắn file chỉ được lưu trong dữ liệu riêng của ứng dụng.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .proxyCard()
    }

    private func handleFeature(_ feature: DemoFeature, index: Int, value: Bool) {
        guard value else {
            enabled.remove(index)
            return
        }

        busyIndex = index
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            busyIndex = nil

            if feature.implemented, let bundledFileName = feature.bundledFileName {
                if copyBundledFeatureFile(named: bundledFileName) {
                    enabled.insert(index)
                    maintenanceText = "\(feature.name) đã bật thành công."
                } else {
                    enabled.remove(index)
                    maintenanceText = "Không thể nạp file demo. Nút đã tự tắt."
                }
            } else {
                enabled.remove(index)
                maintenanceText = "\(feature.name) đang được bảo trì. Nút đã tự tắt."
            }
            showMaintenance = true
        }
    }

    private func openGame() {
        let scheme = title == "Free Fire Max" ? "freefiremax" : "freefire"
        guard let url = URL(string: "\(scheme)://") else { showOpenGameResult = true; return }
        UIApplication.shared.open(url) { success in
            if !success { showOpenGameResult = true }
        }
    }

    private func copyBundledFeatureFile(named name: String) -> Bool {
        guard let source = Bundle.main.url(forResource: name, withExtension: nil) else {
            return false
        }
        let fm = FileManager.default
        let destinationDirectory = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProxySHOPDHP", isDirectory: true)
            .appendingPathComponent("features", isDirectory: true)
        do {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destination = destinationDirectory.appendingPathComponent(name)
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }
}

struct GameTab: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: icon); Text(title).font(.footnote.weight(.semibold)) }
                .foregroundStyle(active ? .cyan : .secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(active ? Color.cyan.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - License UI

struct LicenseKeyView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var showPolicy = false

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        deviceSupportCard
                        VStack(alignment: .leading, spacing: 14) {
                            Text("License Key").font(.title2.weight(.bold))
                            Text("Dán key để kích hoạt trên thiết bị này.").foregroundStyle(.secondary)
                            Text("Device ID / HWID").font(.headline).padding(.top, 10)
                            HStack {
                                Text(state.deviceID).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                Spacer()
                                Button { state.copyDeviceID() } label: { Image(systemName: "doc.on.doc") }
                            }
                            .padding(16).proxyCard()

                            HStack {
                                TextField("Nhập / dán key...", text: $key).textInputAutocapitalization(.characters).autocorrectionDisabled()
                                Button { key = UIPasteboard.general.string ?? "" } label: { Image(systemName: "doc.on.clipboard") }
                            }
                            .padding(16).proxyCard()

                            Button {
                                Task { await state.activate(key) }
                            } label: {
                                HStack { if state.isBusy { ProgressView().tint(.white) }; Text(state.isBusy ? "Đang kiểm tra 3 giây..." : (state.isActivated ? "Đã Kích Hoạt" : "Kích hoạt")) }
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .background(LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain).disabled(state.isBusy)

                            Button { state.copyDeviceID() } label: {
                                Text("Sao chép UDID / Device ID").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain)

                            Button { showPolicy = true } label: {
                                HStack { Image(systemName: "checkmark.shield.fill").foregroundStyle(.cyan); VStack(alignment: .leading) { Text("Chính sách sử dụng").font(.headline); Text("Vui lòng đọc kỹ trước khi sử dụng dịch vụ").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                    .padding(15)
                            }
                            .buttonStyle(.plain).proxyCard()
                        }
                        .padding(16).proxyCard()
                    }
                    .padding(16)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } } }
            .sheet(isPresented: $showPolicy) { PolicyView() }
            .preferredColorScheme(.dark)
        }
    }

    private var deviceSupportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
            InfoLine(icon: "iphone", color: .cyan, title: "Device", value: AppInfo.hardwareDisplayName)
            HStack(spacing: 10) {
                Circle().fill(ExploitSupportPolicy.isCurrentOSSupported ? .green : .red).frame(width: 12, height: 12)
                Text(ExploitSupportPolicy.isCurrentOSSupported ? "Có Hỗ Trợ" : "Không Hỗ Trợ").font(.title3.weight(.bold)).foregroundStyle(ExploitSupportPolicy.isCurrentOSSupported ? .green : .red)
            }
        }
        .padding(18).proxyCard()
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
    var body: some View { HStack(spacing: 8) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(text).font(.footnote.weight(.semibold)) }.padding(.horizontal, 14).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.12))) }
}

private struct ProxyCardModifier: ViewModifier {
    func body(content: Content) -> some View { content.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.13), lineWidth: 1)).shadow(color: .purple.opacity(0.08), radius: 18) }
}

extension View { func proxyCard() -> some View { modifier(ProxyCardModifier()) } }
