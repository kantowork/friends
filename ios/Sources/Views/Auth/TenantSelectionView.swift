import SwiftUI
import AVFoundation

// MARK: - A03m TenantSelectionView
// テナント選択モーダル画面。二次元コードスキャン / JSON貼り付け / URL入力 の3方式に対応。

// MARK: - ViewModel

@MainActor
final class TenantSelectionViewModel: ObservableObject {

    enum InputTab: Int, CaseIterable {
        case twoDimensionalCode = 0, url = 1, text = 2

        var label: String {
            switch self {
            case .twoDimensionalCode: return L10n.Tenant.tab2DCode
            case .url:                return L10n.Tenant.tabURL
            case .text:               return L10n.Tenant.tabText
            }
        }
    }

    enum VerificationState: Equatable {
        case idle
        case loading
        case success(FriendsTenant)
        case failure(String)

        static func == (lhs: VerificationState, rhs: VerificationState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading): return true
            case (.success(let a), .success(let b)): return a.tenantID == b.tenantID
            case (.failure(let a), .failure(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var selectedTab: InputTab = .twoDimensionalCode
    @Published var jsonInput: String = ""
    @Published var urlInput: String = ""
    @Published var verificationState: VerificationState = .idle
    @Published var isConfirmed = false

    private let authService = AuthService.shared

    // MARK: - Parse & Verify

    func verifyFromText(_ rawInput: String) {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // 二次元コード等に URL が直接含まれている場合
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            if let url = URL(string: input) {
                fetchAndVerify(from: url)
                return
            }
        }

        guard let tenantId = extractTenantId(from: input) else {
            verificationState = .failure(L10n.Error.Tenant.invalidFormat)
            return
        }
        verify(tenantId: tenantId)
    }

    func verifyFromUrl() {
        let raw = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            verificationState = .failure(L10n.Error.Tenant.invalidFormat)
            return
        }
        fetchAndVerify(from: url)
    }

    func fetchAndVerify(from url: URL) {
        verificationState = .loading
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10.0
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    await MainActor.run {
                        self.verificationState = .failure(L10n.Error.Tenant.fetchFailed)
                    }
                    return
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tid = json["tenantId"] as? String, !tid.isEmpty else {
                    await MainActor.run {
                        self.verificationState = .failure(L10n.Error.Tenant.invalidFormat)
                    }
                    return
                }

                await MainActor.run {
                    self.parseAndSaveTenantPayload(json)
                    self.verify(tenantId: tid)
                }
            } catch {
                await MainActor.run {
                    self.verificationState = .failure(L10n.Error.Tenant.fetchFailed)
                }
            }
        }
    }

    func confirmTenant(dismiss: DismissAction) {
        guard case .success(let tenant) = verificationState else { return }
        isConfirmed = true
        TenantManager.shared.addOrUpdateTenant(tenant: tenant, workerApiUrl: parsedWorkerApiUrl)
        if authService.authStatus == .authenticated {
            authService.switchToTenant(tenantId: tenant.tenantID) { _ in }
        }
        dismiss()
    }

    func reset() {
        verificationState = .idle
        parsedWorkerApiUrl = nil
    }

    // MARK: - Private

    private var parsedWorkerApiUrl: String? = nil

    private func extractTenantId(from input: String) -> String? {
        // 1. FRIENDS_TENANT: base64
        if input.hasPrefix("FRIENDS_TENANT:") {
            let b64 = input.replacingOccurrences(of: "FRIENDS_TENANT:", with: "")
            if let data = Data(base64Encoded: b64),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tid = json["tenantId"] as? String {
                parseAndSaveTenantPayload(json)
                return tid
            }
            return nil
        }
        // 2. JSON object
        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tid = json["tenantId"] as? String {
            parseAndSaveTenantPayload(json)
            return tid
        }
        return nil
    }

    private func parseAndSaveTenantPayload(_ json: [String: Any]) {
        guard let tid = json["tenantId"] as? String else { return }
        if let masterKey = json["tenantMasterKey"] as? String {
            CryptoKeyManager.shared.saveTenantMasterKey(tenantId: tid, masterKeyBase64: masterKey)
        }
        if let workerUrl = json["workerApiUrl"] as? String {
            self.parsedWorkerApiUrl = workerUrl
        }
        if let r2 = json["r2Config"] as? [String: Any] {
            R2Config.saveConfig(
                publicBaseURL: r2["publicBaseUrl"] as? String,
                bucketName: r2["bucketName"] as? String,
                endpointURL: r2["endpointUrl"] as? String,
                accessKeyId: r2["accessKeyId"] as? String,
                secretAccessKey: r2["secretAccessKey"] as? String
            )
        }
    }

    private func verify(tenantId: String) {
        verificationState = .loading
        authService.verifyAndApplyTenant(tenantId: tenantId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tenant):
                    self?.verificationState = .success(tenant)
                case .failure(let error):
                    self?.verificationState = .failure(L10n.Error.Tenant.verificationFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Main View

struct TenantSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = TenantSelectionViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Segmented Control
                    Picker("", selection: $viewModel.selectedTab) {
                        ForEach(TenantSelectionViewModel.InputTab.allCases, id: \.self) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Tab Content
                    Group {
                        switch viewModel.selectedTab {
                        case .twoDimensionalCode:
                            TwoDimensionalCodeScanTab(viewModel: viewModel)
                        case .url:
                            URLInputTab(viewModel: viewModel)
                        case .text:
                            TextInputTab(viewModel: viewModel)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)

                    Spacer(minLength: 20)

                    // Verification Result + Confirm Button
                    verificationResultSection
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.Tenant.selectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
            .onChange(of: viewModel.selectedTab) { _ in
                viewModel.reset()
            }
        }
    }

    private var verificationResultSection: some View {
        VStack(spacing: 12) {
            switch viewModel.verificationState {
            case .idle:
                EmptyView()

            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.Tenant.verifying)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(14)

            case .failure(let msg):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .padding(.top, 1)
                    Text(msg)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.red.opacity(0.08))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )

            case .success(let tenant):
                TenantConfirmationCard(tenant: tenant) {
                    viewModel.confirmTenant(dismiss: dismiss)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.verificationState)
    }
}

// MARK: - Tenant Confirmation Card

private struct TenantConfirmationCard: View {
    let tenant: FriendsTenant
    let onConfirm: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            // Tenant Info
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tenant.tenantName)
                        .font(.headline)
                        .bold()
                    Text("@\(tenant.tenantCode)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if tenant.isDefaultTenant {
                        Text(L10n.Tenant.defaultBadge)
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.appAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
            )

            // Confirm Button
            Button(action: onConfirm) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                    Text(L10n.Tenant.confirmBtn)
                        .font(.body)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .padding(.vertical, 4)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(13)
            }
            .buttonStyle(.plain)
        }
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - Tab: Two-Dimensional Code Scan

private struct TwoDimensionalCodeScanTab: View {
    @ObservedObject var viewModel: TenantSelectionViewModel

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                TwoDimensionalCodeScannerView(guideSize: 180) { code in
                    viewModel.verifyFromText(code)
                }

                // Instruction badge
                VStack {
                    Spacer()
                    Text(L10n.Tenant.cameraInstruction)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - Tab: Text (JSON) Input

private struct TextInputTab: View {
    @ObservedObject var viewModel: TenantSelectionViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Tenant.inputLabel)
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)

            TextEditor(text: $viewModel.jsonInput)
                .font(.system(.caption, design: .monospaced))
                .focused($isFocused)
                .padding(10)
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.appAccent.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1.5)
                )

            Button {
                isFocused = false
                viewModel.verifyFromText(viewModel.jsonInput)
            } label: {
                HStack(spacing: 6) {
                    if case .loading = viewModel.verificationState {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text(L10n.Tenant.verifyBtn)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .padding(.vertical, 4)
                .background(
                    viewModel.jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.appAccent.opacity(0.4)
                        : Color.appAccent
                )
                .foregroundColor(.white)
                .cornerRadius(13)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - Tab: URL Input

private struct URLInputTab: View {
    @ObservedObject var viewModel: TenantSelectionViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Tenant.urlLabel)
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)

            TextField(L10n.Tenant.urlPlaceholder, text: $viewModel.urlInput)
                .font(.system(.subheadline, design: .monospaced))
                .focused($isFocused)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.appAccent.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1.5)
                )

            Button {
                isFocused = false
                viewModel.verifyFromUrl()
            } label: {
                HStack(spacing: 6) {
                    if case .loading = viewModel.verificationState {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                    }
                    Text(L10n.Tenant.verifyBtn)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .padding(.vertical, 4)
                .background(
                    viewModel.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.appAccent.opacity(0.4)
                        : Color.appAccent
                )
                .foregroundColor(.white)
                .cornerRadius(13)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
