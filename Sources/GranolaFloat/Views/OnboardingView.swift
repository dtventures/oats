import OatsCore
import SwiftUI
import AppKit

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var step:            Step    = .welcome
    @State private var granolaKey:      String  = ""
    @State private var claudeKey:       String  = ""
    @State private var userName:        String  = ""
    @State private var userEmail:       String  = ""
    @State private var isValidating:    Bool    = false
    @State private var validationError: String? = nil
    @State private var profileError:    String? = nil
    @State private var showGranolaKey:  Bool    = true
    @State private var showClaudeKey:   Bool    = true

    enum Step: Int, CaseIterable { case welcome, granolaKey, claudeKey, profile }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                if step != .welcome {
                    HStack(spacing: 7) {
                        ForEach([Step.granolaKey, .claudeKey, .profile], id: \.self) { s in
                            Circle()
                                .fill(step.rawValue >= s.rawValue
                                      ? Color.granolaGreen
                                      : Color.checkboxBorder.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: step)
                        }
                    }
                    .padding(.top, 28)
                }

                Spacer(minLength: 0)

                Group {
                    switch step {
                    case .welcome:
                        WelcomeStepView { advance(to: .granolaKey) }

                    case .granolaKey:
                        GranolaKeyStepView(
                            key: $granolaKey,
                            showKey: $showGranolaKey,
                            isValidating: $isValidating,
                            error: $validationError,
                            onNext: validateAndContinue,
                            onBack: { advance(to: .welcome) }
                        )
                    case .claudeKey:
                        ClaudeKeyStepView(
                            key: $claudeKey,
                            showKey: $showClaudeKey,
                            onNext: { advance(to: .profile) },
                            onSkip: { advance(to: .profile) },
                            onBack: { advance(to: .granolaKey) }
                        )
                    case .profile:
                        ProfileStepView(
                            name: $userName,
                            email: $userEmail,
                            error: $profileError,
                            onDone: finish,
                            onBack: { advance(to: .claudeKey) }
                        )
                    }
                }
                .id(step.rawValue)
                .transition(.asymmetric(
                    insertion: .move(edge: step == .welcome ? .leading : .trailing).combined(with: .opacity),
                    removal:   .move(edge: step == .welcome ? .trailing : .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 0)
            }
        }
        .frame(width: 480, height: 380)
        .preferredColorScheme(.light)
    }

    // MARK: - Navigation

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    // MARK: - Actions

    private func validateAndContinue() {
        let trimmed = granolaKey.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            validationError = "Please enter your Granola API key."
            return
        }
        isValidating    = true
        validationError = nil
        Task {
            let valid = await GranolaAPI.validate(key: trimmed)
            await MainActor.run {
                isValidating = false
                if valid {
                    KeychainManager.save(trimmed, for: KeychainManager.Key.granolaAPIKey)
                    advance(to: .claudeKey)
                } else {
                    validationError = "Couldn't connect with that key — check it's correct."
                }
            }
        }
    }

    private func finish() {
        let trimmedClaude = claudeKey.trimmingCharacters(in: .whitespaces)
        let trimmedName   = userName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail  = userEmail.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            profileError = UserProfileStore.missingIdentityMessage
            return
        }

        if !trimmedClaude.isEmpty {
            KeychainManager.save(trimmedClaude, for: KeychainManager.Key.claudeAPIKey)
        }
        let defaults = UserDefaults(suiteName: UserProfileStore.suiteName)!
        if !trimmedName.isEmpty  { defaults.set(trimmedName,  forKey: "userName") }
        if !trimmedEmail.isEmpty { defaults.set(trimmedEmail, forKey: "userEmail") }
        defaults.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OatIconView(size: 80)
                .padding(.bottom, 18)

            Text("Oats")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 8)

            Text("Your meeting action items & to-do's.\nAutomatically created and always visible.")
                .font(.system(size: 13.5))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.bottom, 32)

            OnboardingButton("Get Started", style: .primary, action: onNext)
        }
        .padding(.horizontal, 64)
    }
}

// MARK: - Step 2: Granola API Key

private struct GranolaKeyStepView: View {
    @Binding var key:          String
    @Binding var showKey:      Bool
    @Binding var isValidating: Bool
    @Binding var error:        String?
    var onNext: () -> Void
    var onBack: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect Granola")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 6)

            Text("Enter your Granola API key to sync your meeting notes.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .padding(.bottom, 20)

            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField("", text: $key, prompt: Text("grn_…").foregroundColor(.textSecondary))
                            .focused($focused)
                    } else {
                        SecureField("", text: $key, prompt: Text("grn_…").foregroundColor(.textSecondary))
                            .focused($focused)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
                .onAppear { focused = true }

                Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.granolaGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(error != nil ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .padding(.bottom, 6)

            Group {
                if let err = error {
                    Text(err).foregroundColor(.red.opacity(0.8))
                } else {
                    Text("Granola → Settings → Integrations → API")
                        .foregroundColor(.textSecondary)
                }
            }
            .font(.system(size: 11))
            .padding(.bottom, 28)

            HStack(spacing: 10) {
                OnboardingButton("Back", style: .ghost, action: onBack)
                Spacer()
                OnboardingButton(
                    isValidating ? "Checking…" : "Continue",
                    style: .primary,
                    disabled: key.trimmingCharacters(in: .whitespaces).isEmpty || isValidating,
                    action: onNext
                )
            }
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 3: Claude API Key

private struct ClaudeKeyStepView: View {
    @Binding var key:     String
    @Binding var showKey: Bool
    var onNext: () -> Void
    var onSkip: () -> Void
    var onBack: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Extraction")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 6)

            Text("Optional: add a Claude API key for smarter action item extraction from free-form transcripts. Without it, we use pattern matching.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .padding(.bottom, 20)

            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField("", text: $key, prompt: Text("sk-ant-…").foregroundColor(.textSecondary))
                            .focused($focused)
                    } else {
                        SecureField("", text: $key, prompt: Text("sk-ant-…").foregroundColor(.textSecondary))
                            .focused($focused)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.textPrimary)
                .onAppear { focused = true }

                Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.granolaGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 9))
            .padding(.bottom, 6)

            Text("Uses claude-haiku-4-5 — very cheap per note.")
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .padding(.bottom, 28)

            HStack(spacing: 10) {
                OnboardingButton("Back", style: .ghost, action: onBack)
                Spacer()
                OnboardingButton("Skip", style: .secondary, action: onSkip)
                OnboardingButton("Continue", style: .primary, action: onNext)
            }
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Step 4: Profile

private struct ProfileStepView: View {
    @Binding var name:  String
    @Binding var email: String
    @Binding var error: String?
    var onDone: () -> Void
    var onBack: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who are you?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 6)

            Text("We use your name and email to find your action items in meeting notes.")
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
                .padding(.bottom, 20)

            OnboardingField(placeholder: "First name", text: $name)
                .focused($focused)
                .onChange(of: name) { error = nil }
                .onAppear { focused = true }
                .padding(.bottom, 10)

            OnboardingField(placeholder: "Work email", text: $email)
                .onChange(of: email) { error = nil }
                .padding(.bottom, error == nil ? 28 : 12)

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.bottom, 16)
            }

            HStack(spacing: 10) {
                OnboardingButton("Back", style: .ghost, action: onBack)
                Spacer()
                OnboardingButton(
                    "Done",
                    style: .primary,
                    disabled: name.trimmingCharacters(in: .whitespaces).isEmpty
                              || email.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: onDone
                )
            }
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Shared: icon loader

private struct OatIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.appResources.url(forResource: "OatIcon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .fill(Color.granolaLight)
                    Image(systemName: "checklist")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundColor(.granolaGreen)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Shared components

private struct OnboardingField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundColor(.textSecondary)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundColor(.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.creamHover, in: RoundedRectangle(cornerRadius: 9))
    }
}

private enum OBButtonStyle { case primary, secondary, ghost }

private struct OnboardingButton: View {
    let label:    String
    let style:    OBButtonStyle
    var disabled: Bool = false
    let action:   () -> Void

    init(_ label: String, style: OBButtonStyle, disabled: Bool = false, action: @escaping () -> Void) {
        self.label    = label
        self.style    = style
        self.disabled = disabled
        self.action   = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: style == .primary ? .medium : .regular))
                .foregroundColor(fgColor)
                .padding(.horizontal, style == .ghost ? 0 : 18)
                .padding(.vertical, 8)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var bgColor: Color {
        switch style {
        case .primary:   return .granolaGreen
        case .secondary: return .creamHover
        case .ghost:     return .clear
        }
    }

    private var fgColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return .textPrimary
        case .ghost:     return .textSecondary
        }
    }
}
