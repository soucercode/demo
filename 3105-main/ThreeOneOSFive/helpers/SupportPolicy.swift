import Foundation

/// UI support policy for Proxy SHOP DHP. This only reports compatibility in the app UI.
enum ExploitSupportPolicy {
    static let supportedRanges = [
        "16–16.7.x",
        "17–17.7.x",
        "18–18.7.1",
        "26–26.6.1",
        "27 beta 1, 2, 3, 4"
    ]

    static var verifiedIOS26Range: String { "26.0–26.6.1" }
    static let verifiedIOS27Builds: [(beta: Int, build: String)] = []

    static var isCurrentOSSupported: Bool {
        let v = AppInfo.versionTuple
        return isSupported(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild)
    }

    static var currentSupportLabel: String {
        let v = AppInfo.versionTuple
        if v.major == 27 { return "iOS 27 beta" }
        return "iOS \(v.major).\(v.minor).\(v.patch)"
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        switch major {
        case 16:
            return minor >= 0 && minor <= 7
        case 17:
            return minor >= 0 && minor <= 7
        case 18:
            return minor >= 0 && (minor < 7 || (minor == 7 && patch <= 1))
        case 26:
            return minor >= 0 && (minor < 6 || (minor == 6 && patch <= 1))
        case 27:
            // Beta 1–4 builds vary across releases. The UI intentionally treats
            // a build containing "beta"/"Beta" as a supported demo beta state.
            let lower = build.lowercased()
            return lower.contains("beta") || lower.contains("q") || lower.contains("h") || lower.contains("f")
        default:
            return false
        }
    }

    static func iOS27BetaNumber(for build: String) -> Int? { nil }
}
