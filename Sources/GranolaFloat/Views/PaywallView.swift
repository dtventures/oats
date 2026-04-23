import OatsCore
import SwiftUI
import AppKit

struct PaywallView: View {
    var onUnlock: () -> Void

    @State private var licenseKey   = ""
    @State private var errorText:   String? = nil
    @State private var isActivating = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Group {
                if let url = Bundle.appResources.url(forResource: "OatIcon", withExtension: "png"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.granolaLight)
                        Image(systemName: "checklist")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.granolaGreen)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 14)

            Text("Oats")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 4)

            Text("Your free trial has ended")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .padding(.bottom, 28)

            // Buy button
            Button {
                NSWorkspace.shared.open(LicenseManager.purchaseURL)
            } label: {
                Text("Get Oats — $9.99")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Color.granolaGreen, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)

            // License key entry
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $licenseKey,
                        prompt: Text("OATS-XXXXXXXX-YYYY")
                            .foregroundColor(.textSecondary)
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .focused($keyFocused)
                    .onChange(of: licenseKey) { errorText = nil }
                    .onSubmit { tryActivate() }

                    Button(isActivating ? "…" : "Activate") { tryActivate() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            (licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                                ? Color.checkboxBorder : Color.granolaGreen,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))

                if let err = errorText {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Already purchased? Enter your license key above.")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream)
    }

    private func tryActivate() {
        let k = licenseKey.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty, !isActivating else { return }
        isActivating = true
        errorText    = nil
        Task {
            do {
                _ = try await LicenseManager.activate(k)
                await MainActor.run { onUnlock() }
            } catch LicenseManager.ActivationError.invalidKey {
                await MainActor.run {
                    errorText    = "Invalid key — double-check and try again."
                    isActivating = false
                }
            } catch LicenseManager.ActivationError.alreadyActivated {
                await MainActor.run {
                    errorText    = "Key is already in use on too many devices."
                    isActivating = false
                }
            } catch LicenseManager.ActivationError.networkError {
                await MainActor.run {
                    errorText    = "Network error — check your connection and retry."
                    isActivating = false
                }
            } catch LicenseManager.ActivationError.serverError(let msg) {
                await MainActor.run {
                    errorText    = msg
                    isActivating = false
                }
            } catch {
                await MainActor.run {
                    errorText    = "Something went wrong — try again."
                    isActivating = false
                }
            }
        }
    }
}

// MARK: - Trial countdown banner (shown during active trial)

struct TrialBannerView: View {
    let daysLeft: Int
    var onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)

            Text(daysLeft == 1 ? "1 day left in trial" : "\(daysLeft) days left in trial")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)

            Spacer()

            Button("Upgrade") { onUpgrade() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.granolaGreen)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.granolaLight, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.creamHover.opacity(0.6))
    }
}
