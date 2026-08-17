import SwiftUI
import PodiumKit

struct WizardView: View {
    enum Step { case welcome, choosePath, generateKey, enterIds, done }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// When true, the wizard opens directly at the key step (used for "Connect Apple Ads" later).
    var connectOnly = false

    @State private var step: Step = .welcome
    @State private var privateKeyPEM = ""
    @State private var publicKeyPEM = ""
    @State private var clientId = ""
    @State private var teamId = ""
    @State private var keyId = ""
    @State private var orgId = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validatedCredentials: AdsCredentials?

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: 560)
                .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay(alignment: .topTrailing) {
            Button {
                if connectOnly {
                    model.showConnectWizard = false
                    dismiss()
                } else {
                    model.finishOnboarding(with: nil)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
            .help("Close — you can finish connecting anytime from the sidebar")
        }
        .onAppear { if connectOnly { generateKey(); step = .generateKey } }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Welcome to Podium").font(.largeTitle.bold())
                Text("Free, open-source App Store optimization. Track keyword rankings, see official Apple popularity data, and watch your apps climb.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Get started") { step = .choosePath }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        case .choosePath:
            VStack(spacing: 20) {
                Text("How do you want to start?").font(.title.bold())
                pathCard(
                    title: "Start tracking now",
                    subtitle: "Track keyword rankings and ratings with zero setup. You can connect Apple Ads anytime later.",
                    systemImage: "bolt") {
                    model.finishOnboarding(with: nil)
                }
                pathCard(
                    title: "Connect Apple Ads (5 minutes)",
                    subtitle: "Unlock official keyword popularity and top-search-terms data via your free Apple Ads account.",
                    systemImage: "key") {
                    generateKey()
                    step = .generateKey
                }
            }
        case .generateKey:
            VStack(alignment: .leading, spacing: 14) {
                Text("Step 1 — Your key").font(.title2.bold())
                Text("Podium generated a secure key on this Mac. Copy the public part below and paste it into Apple Ads → Account Settings → API → Public Key, then press Save there.")
                    .foregroundStyle(.secondary)
                TextEditor(text: .constant(publicKeyPEM))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    Button("Copy public key") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(publicKeyPEM, forType: .string)
                    }
                    .buttonStyle(.glass)
                    Link("Open Apple Ads", destination: URL(string: "https://ads.apple.com")!)
                    Spacer()
                    Button("Next") { step = .enterIds }.buttonStyle(.glassProminent)
                }
                Text("The private part never leaves your Mac — it will be stored in your Keychain.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        case .enterIds:
            VStack(alignment: .leading, spacing: 14) {
                Text("Step 2 — Your IDs").font(.title2.bold())
                Text("After saving the key, Apple Ads shows a block with your credentials. Copy each value here.")
                    .foregroundStyle(.secondary)
                Form {
                    TextField("clientId", text: $clientId, prompt: Text("SEARCHADS.xxxx"))
                    TextField("teamId", text: $teamId, prompt: Text("SEARCHADS.xxxx"))
                    TextField("keyId", text: $keyId, prompt: Text("xxxxxxxx-xxxx"))
                    TextField("orgId  (Account Settings → API, number)", text: $orgId, prompt: Text("1234567"))
                }
                .formStyle(.grouped)
                .frame(height: 190)
                if let validationError {
                    Text(validationError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Back") { step = .generateKey }
                        .buttonStyle(.glass)
                    Spacer()
                    Button(isValidating ? "Checking…" : "Validate and finish") { validate() }
                        .buttonStyle(.glassProminent)
                        .disabled(isValidating || clientId.isEmpty || teamId.isEmpty || keyId.isEmpty)
                }
            }
        case .done:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56)).foregroundStyle(.green)
                Text("Connected").font(.largeTitle.bold())
                Text("Official Apple data is now available. Add your app and start tracking.")
                    .foregroundStyle(.secondary)
                Button("Open Podium") {
                    model.finishOnboarding(with: validatedCredentials ?? currentCredentials())
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }

    private func pathCard(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title2).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func generateKey() {
        guard privateKeyPEM.isEmpty else { return }
        privateKeyPEM = ClientSecret.generatePrivateKeyPEM()
        publicKeyPEM = (try? ClientSecret.publicKeyPEM(fromPrivatePEM: privateKeyPEM)) ?? ""
    }

    private func currentCredentials() -> AdsCredentials {
        AdsCredentials(
            clientId: clientId.trimmingCharacters(in: .whitespaces),
            teamId: teamId.trimmingCharacters(in: .whitespaces),
            keyId: keyId.trimmingCharacters(in: .whitespaces),
            privateKeyPEM: privateKeyPEM,
            orgId: Int(orgId.trimmingCharacters(in: .whitespaces)))
    }

    private func validate() {
        isValidating = true
        validationError = nil
        var creds = currentCredentials()
        Task {
            do {
                let provider = TokenProvider(credentials: creds)
                _ = try await provider.validToken()
                let api = AdsAPIClient(credentials: creds, tokenProvider: provider)
                let accounts = try await api.acls()
                if let accountId = accounts.compactMap(\.adAccount?.id).first {
                    creds.adAccountId = accountId
                }
                validatedCredentials = creds
                step = .done
            } catch {
                validationError = "Apple rejected the credentials — double-check each value and that the key is saved in Apple Ads. (\(error))"
            }
            isValidating = false
        }
    }
}
