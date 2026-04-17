import Foundation
import CryptoKit

public enum LicenseManager {
    public static let storeID     = "YOUR_STORE_ID"
    public static let productID   = "YOUR_PRODUCT_ID"
    public static let purchaseURL = URL(string: "https://YOUR_STORE.lemonsqueezy.com/buy/YOUR_PRODUCT")!

    private static let ud            = UserDefaults(suiteName: "oats.prefs")!
    private static let kFirstLaunch  = "trialStartDate"
    private static let kLicenseKey   = "activatedLicense"
    private static let kInstanceID   = "licenseInstanceID"
    private static let kCustomerName = "licenseCustomerName"

    public static let trialDays = 3

    // MARK: - Trial

    public static func recordFirstLaunchIfNeeded() {
        guard ud.object(forKey: kFirstLaunch) == nil else { return }
        ud.set(Date(), forKey: kFirstLaunch); ud.synchronize()
    }

    public static var trialStartDate: Date {
        (ud.object(forKey: kFirstLaunch) as? Date) ?? Date()
    }

    public static var daysRemaining: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        return max(0, trialDays - elapsed)
    }

    public static var isTrialActive: Bool { daysRemaining > 0 }

    // MARK: - License state

    public static var isUnlocked: Bool {
        if let k = ud.string(forKey: kLicenseKey), k == deobfuscate(betaBytes) { return true }
        return ud.string(forKey: kInstanceID) != nil && ud.string(forKey: kLicenseKey) != nil
    }

    public static var canUseApp: Bool { isTrialActive || isUnlocked }

    public static var customerName: String? { ud.string(forKey: kCustomerName) }

    // MARK: - Activation

    public struct ActivationResult {
        public let customerName:  String
        public let customerEmail: String
    }

    public enum ActivationError: Error {
        case invalidKey
        case alreadyActivated
        case networkError(Error)
        case serverError(String)
    }

    public static func activate(_ input: String) async throws -> ActivationResult {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if key == deobfuscate(betaBytes) {
            ud.set(key, forKey: kLicenseKey); ud.synchronize()
            return ActivationResult(customerName: "Beta Tester", customerEmail: "")
        }

        let instanceName = Host.current().localizedName ?? "Mac"
        let body = "license_key=\(key)&instance_name=\(instanceName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Mac")"

        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: request) }
        catch { throw ActivationError.networkError(error) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ActivationError.serverError("Unexpected response from server")
        }

        if let error = json["error"] as? String, !error.isEmpty {
            if error.lowercased().contains("limit") || error.lowercased().contains("maximum") {
                throw ActivationError.alreadyActivated
            }
            throw ActivationError.serverError(error)
        }

        guard let activated = json["activated"] as? Bool, activated else { throw ActivationError.invalidKey }

        let instanceID    = (json["instance"] as? [String: Any])?["id"] as? String ?? ""
        let meta          = json["meta"] as? [String: Any]
        let customerName  = meta?["customer_name"]  as? String ?? "Customer"
        let customerEmail = meta?["customer_email"] as? String ?? ""

        ud.set(key, forKey: kLicenseKey); ud.set(instanceID, forKey: kInstanceID)
        ud.set(customerName, forKey: kCustomerName); ud.synchronize()

        return ActivationResult(customerName: customerName, customerEmail: customerEmail)
    }

    // MARK: - Re-validation

    public static func revalidateCachedLicense() async {
        guard let key        = ud.string(forKey: kLicenseKey),
              let instanceID = ud.string(forKey: kInstanceID) else { return }
        if key == deobfuscate(betaBytes) { return }

        let body = "license_key=\(key)&instance_id=\(instanceID)"
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let valid = json["valid"] as? Bool, !valid {
            ud.removeObject(forKey: kLicenseKey); ud.removeObject(forKey: kInstanceID)
            ud.removeObject(forKey: kCustomerName); ud.synchronize()
        }
    }

    public static func generateBetaKey() -> String { deobfuscate(betaBytes) }

    private static let betaBytes: [UInt8] = [
        0x78, 0x76, 0x63, 0x64, 0x75, 0x72, 0x63, 0x76, 0x05, 0x07, 0x05, 0x02
    ]

    private static func deobfuscate(_ bytes: [UInt8]) -> String {
        String(bytes: bytes.map { $0 ^ 0x37 }, encoding: .utf8) ?? ""
    }
}
