import Foundation

extension Bundle {
    /// Resolves the SPM resource bundle regardless of where the app is installed.
    ///
    /// The SPM-generated `Bundle.module` accessor hardcodes two paths:
    ///   1. `Bundle.main.bundleURL/Oats_Oats.bundle`  — the .app root (wrong for a real .app)
    ///   2. An absolute path on the developer's build machine (never works for others)
    ///
    /// When packaged as a proper .app, the bundle lives in `Contents/Resources/`.
    /// This accessor checks that location first, then falls back to the SPM paths.
    static let appResources: Bundle = {
        let bundleName = "Oats_Oats.bundle"

        // 1. Contents/Resources/ — where build.sh puts it
        if let url = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           let bundle = Bundle(url: url) {
            return bundle
        }

        // 2. App root — where SPM's generated accessor looks (dev machine running swift run)
        let rootURL = Bundle.main.bundleURL.appendingPathComponent(bundleName)
        if let bundle = Bundle(url: rootURL) {
            return bundle
        }

        // 3. Next to the binary — works when running via `swift run`
        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
                                                   .appendingPathComponent(bundleName),
           let bundle = Bundle(url: execURL) {
            return bundle
        }

        fatalError("Could not locate resource bundle '\(bundleName)'")
    }()
}
