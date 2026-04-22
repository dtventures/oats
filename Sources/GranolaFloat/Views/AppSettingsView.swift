import OatsCore
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var store: TodoStore

    enum SyncPeriod: String, CaseIterable {
        case week    = "Past week"
        case weeks2  = "Past 2 weeks"
        case month   = "Past month"
        case allTime = "All time"

        var days: Int {
            switch self {
            case .week:    return 7
            case .weeks2:  return 14
            case .month:   return 30
            case .allTime: return 365
            }
        }
    }

    @State private var syncPeriod:       SyncPeriod = .weeks2
    @State private var granolaKey:       String = ""
    @State private var claudeKey:        String = ""
    @State private var granolaKeySaved:   Bool   = false
    @State private var claudeKeySaved:    Bool   = false
    @State private var granolaKeyVisible: Bool   = false
    @State private var claudeKeyVisible:  Bool   = false
    @State private var licenseKey:        String = ""
    @State private var licenseError:     String? = nil
    @State private var licenseActivated: Bool   = false
    @State private var licenseActivating: Bool  = false

    // Profile — stored in the shared suite so all app contexts read the same values
    @AppStorage("userName",  store: UserDefaults(suiteName: "oats.prefs"))  private var userName  = ""
    @AppStorage("userEmail", store: UserDefaults(suiteName: "oats.prefs"))  private var userEmail = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {

            SettingsRow(label: "Your Name") {
                TextField(
                    "",
                    text: $userName,
                    prompt: Text("First name").foregroundColor(.textSecondary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))

                Text("Used to identify your action items in notes")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
            }

            SettingsRow(label: "Your Email") {
                TextField(
                    "",
                    text: $userEmail,
                    prompt: Text("you@company.com").foregroundColor(.textSecondary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))
            }

            SettingsRow(label: "Granola API Key") {
                HStack(spacing: 8) {
                    if granolaKeySaved && !granolaKeyVisible {
                        // Masked — show dots, not directly editable; click Show to reveal
                        Text(String(repeating: "•", count: min(granolaKey.count, 28)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField(
                            "",
                            text: $granolaKey,
                            prompt: Text("grn_…").foregroundColor(.textSecondary)
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .onChange(of: granolaKey) { granolaKeySaved = false }
                    }

                    if granolaKeySaved {
                        Button(granolaKeyVisible ? "Hide" : "Show") { granolaKeyVisible.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.granolaGreen)
                    } else {
                        Button("Save") { saveGranolaKey() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                granolaKey.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.checkboxBorder
                                    : Color.granolaGreen,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .disabled(granolaKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))

                Text("Granola → Settings → Integrations → API")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
            }

            SettingsRow(label: "Claude API Key") {
                HStack(spacing: 8) {
                    if claudeKeySaved && !claudeKeyVisible {
                        Text(String(repeating: "•", count: min(claudeKey.count, 28)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField(
                            "",
                            text: $claudeKey,
                            prompt: Text("sk-ant-…").foregroundColor(.textSecondary)
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .onChange(of: claudeKey) { claudeKeySaved = false }
                    }

                    if claudeKeySaved {
                        Button(claudeKeyVisible ? "Hide" : "Show") { claudeKeyVisible.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.granolaGreen)
                    } else {
                        Button("Save") { saveClaudeKey() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                claudeKey.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.checkboxBorder
                                    : Color.granolaGreen,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .disabled(claudeKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))

                Text("Enables AI extraction for free-form transcripts")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
            }

            // Status row — only when no key is saved
            if granolaKey.isEmpty && !granolaKeySaved {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.granolaGreen)
                        .frame(width: 6, height: 6)
                    Text("No Granola API key — add one above to sync your meetings")
                        .font(.system(size: 10))
                        .foregroundColor(.granolaGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.granolaLight, in: RoundedRectangle(cornerRadius: 8))
            }

            if !UserProfileStore.current().isComplete {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 6, height: 6)
                    Text(UserProfileStore.missingIdentityMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // Sync history
            SettingsRow(label: "Sync History") {
                HStack(spacing: 8) {
                    Picker("", selection: $syncPeriod) {
                        ForEach(SyncPeriod.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        Task { await store.syncPeriod(days: syncPeriod.days) }
                    } label: {
                        Text(store.isSyncing ? "Syncing…" : "Run")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.granolaGreen, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSyncing)
                }

                Text("Fetches notes from the selected period and extracts any new action items")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
            }

            // ── Billing ───────────────────────────────────────────────
            Divider()
                .background(Color.creamDivider)
                .padding(.vertical, 4)

            if LicenseManager.isUnlocked || licenseActivated {
                // Licensed state
                SettingsRow(label: "Billing") {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.granolaGreen)
                        Text("Oats — Licensed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.granolaLight, in: RoundedRectangle(cornerRadius: 8))
                }
            } else if LicenseManager.isTrialActive {
                // Trial active — show upgrade CTA
                SettingsRow(label: "Billing") {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(LicenseManager.daysRemaining) day\(LicenseManager.daysRemaining == 1 ? "" : "s") left in trial")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text("Upgrade to keep your todos forever")
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Button("Upgrade") {
                            NSWorkspace.shared.open(LicenseManager.purchaseURL)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.granolaGreen, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.granolaLight, in: RoundedRectangle(cornerRadius: 8))

                    // License key entry for users who already bought
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $licenseKey,
                            prompt: Text("Have a license key? Enter it here")
                                .foregroundColor(.textSecondary)
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .onChange(of: licenseKey) { licenseError = nil }

                        if !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(licenseActivating ? "…" : "Activate") { activateLicense() }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(licenseActivating ? Color.checkboxBorder : Color.granolaGreen,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .disabled(licenseActivating)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))

                    if let err = licenseError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.75))
                    }
                }
            } else {
                // Trial expired, not licensed — enter key to unlock
                SettingsRow(label: "Billing") {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trial ended")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Text("Purchase to continue using Oats")
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Button("Buy — $9.99") {
                            NSWorkspace.shared.open(LicenseManager.purchaseURL)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.granolaGreen, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.granolaLight, in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $licenseKey,
                            prompt: Text("License key").foregroundColor(.textSecondary)
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .onChange(of: licenseKey) { licenseError = nil }

                        Button(licenseActivating ? "…" : "Activate") { activateLicense() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || licenseActivating)
                                    ? Color.checkboxBorder : Color.granolaGreen,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || licenseActivating)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 8))

                    if let err = licenseError {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.75))
                    }
                }
            }

            Color.clear.frame(height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        } // end ScrollView
        .onAppear {
            granolaKey      = KeychainManager.load(KeychainManager.Key.granolaAPIKey) ?? ""
            claudeKey       = KeychainManager.load(KeychainManager.Key.claudeAPIKey)  ?? ""
            granolaKeySaved = !granolaKey.isEmpty
            claudeKeySaved  = !claudeKey.isEmpty
        }
    }

    // MARK: - Actions

    private func saveGranolaKey() {
        let trimmed = granolaKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        KeychainManager.save(trimmed, for: KeychainManager.Key.granolaAPIKey)
        granolaKeySaved   = true
        granolaKeyVisible = false
        // Trigger a sync so the key is tested immediately
        Task { await store.sync() }
    }

    private func saveClaudeKey() {
        let trimmed = claudeKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            KeychainManager.delete(KeychainManager.Key.claudeAPIKey)
        } else {
            KeychainManager.save(trimmed, for: KeychainManager.Key.claudeAPIKey)
        }
        claudeKeySaved   = true
        claudeKeyVisible = false
    }

    private func activateLicense() {
        let k = licenseKey.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty, !licenseActivating else { return }
        licenseActivating = true
        licenseError      = nil
        Task {
            do {
                _ = try await LicenseManager.activate(k)
                await MainActor.run {
                    licenseActivated  = true
                    licenseActivating = false
                    store.showPaywall = false
                }
            } catch LicenseManager.ActivationError.invalidKey {
                await MainActor.run {
                    licenseError      = "Invalid key — check and try again."
                    licenseActivating = false
                }
            } catch LicenseManager.ActivationError.alreadyActivated {
                await MainActor.run {
                    licenseError      = "Key already used on too many devices."
                    licenseActivating = false
                }
            } catch LicenseManager.ActivationError.networkError {
                await MainActor.run {
                    licenseError      = "Network error — check your connection."
                    licenseActivating = false
                }
            } catch LicenseManager.ActivationError.serverError(let msg) {
                await MainActor.run {
                    licenseError      = msg
                    licenseActivating = false
                }
            } catch {
                await MainActor.run {
                    licenseError      = "Something went wrong — try again."
                    licenseActivating = false
                }
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.sectionLabel)
                .kerning(0.8)
            content()
        }
    }
}
