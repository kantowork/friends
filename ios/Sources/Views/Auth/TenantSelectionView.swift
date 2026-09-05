import SwiftUI
import AVFoundation

// MARK: - A03m TenantSelectionView
// テナント選択モーダル画面。QRコードスキャン / JSON貼り付け / URL入力 の3方式に対応。

// MARK: - ViewModel

@MainActor
final class TenantSelectionViewModel: ObservableObject {

    enum InputTab: Int, CaseIterable {
        case qr = 0, url = 1, json = 2

        var label: String {
            switch self {
            case .qr:   return L10n.Tenant.tabQR
            case .url:  return L10n.Tenant.tabURL
            case .json: return L10n.Tenant.tabCustom
            }
        }

        var icon: String {
            switch self {
            case .qr:   return "qrcode.viewfinder"
            case .url:  return "link"
            case .json: return "doc.text"
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

    @Published var selectedTab: InputTab = .qr
    @Published var jsonInput: String = ""
    @Published var urlInput: String = ""
    @Published var verificationState: VerificationState = .idle
    @Published var isConfirmed = false

    private let chatService = ChatService.shared

    // MARK: - Parse & Verify

    func verifyFromText(_ rawInput: String) {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // QRコード等に URL が直接含まれている場合
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
        guard case .success = verificationState else { return }
        isConfirmed = true
        dismiss()
    }

    func reset() {
        verificationState = .idle
    }

    // MARK: - Private

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
        if let masterKey = json["tenantMasterKey"] as? String ?? json["masterKey"] as? String {
            CryptoKeyManager.shared.saveTenantMasterKey(tenantId: tid, masterKeyBase64: masterKey)
        }
        if let workerUrl = json["workerApiUrl"] as? String {
            RecoveryConfig.saveWorkersBaseURL(workerUrl)
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
        chatService.verifyAndApplyTenant(tenantId: tenantId) { [weak self] result in
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
            VStack(spacing: 0) {
                // Header
                headerSection

                // Tab Selector
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Tab Content
                Group {
                    switch viewModel.selectedTab {
                    case .qr:
                        QRScanTab(viewModel: viewModel)
                    case .json:
                        JSONInputTab(viewModel: viewModel)
                    case .url:
                        URLInputTab(viewModel: viewModel)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.selectedTab)

                Spacer()

                // Verification Result + Confirm Button
                verificationResultSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
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

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.blue)
            }
            .padding(.top, 20)

            Text(L10n.Tenant.header)
                .font(.title3)
                .bold()

            Text(L10n.Tenant.subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(TenantSelectionViewModel.InputTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        viewModel.selectedTab == tab
                            ? Color.blue
                            : Color.clear
                    )
                    .foregroundColor(
                        viewModel.selectedTab == tab ? .white : .secondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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
                        .font(.system(size: 22))
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
                            .foregroundColor(.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
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
                .frame(height: 50)
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

// MARK: - Tab: QR Scan

private struct QRScanTab: View {
    @ObservedObject var viewModel: TenantSelectionViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Camera Preview or Simulator Fallback
            #if targetEnvironment(simulator)
            SimulatorQRFallback(viewModel: viewModel)
            #else
            QRCameraPreview(viewModel: viewModel)
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - QR Camera Preview (Real Device)

private struct QRCameraPreview: View {
    @ObservedObject var viewModel: TenantSelectionViewModel
    @StateObject private var scanner = QRCodeScanner()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Camera feed
                QRCameraRepresentable(scanner: scanner)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                // Scan frame overlay
                ScanFrameOverlay()

                // Scanning animation label
                VStack {
                    Spacer()
                    Text(L10n.Tenant.cameraInstruction)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
            .frame(height: 260)
        }
        .onChange(of: scanner.scannedCode) { code in
            guard let code else { return }
            scanner.stop()
            viewModel.verifyFromText(code)
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }
}

// MARK: - Scan Frame Overlay

private struct ScanFrameOverlay: View {
    @State private var scanning = false
    let cornerLength: CGFloat = 28
    let cornerWidth: CGFloat = 4

    var body: some View {
        ZStack {
            // Dimmed outer area
            Color.black.opacity(0.35)
                .mask(
                    Rectangle()
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black)
                                .frame(width: 180, height: 180)
                        )
                        .compositingGroup()
                        .luminanceToAlpha()
                        .blendMode(.destinationOut)
                )

            // Corner brackets
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 180, height: 180)

            // Scan line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .blue.opacity(0.8), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: 160, height: 2)
                .offset(y: scanning ? 80 : -80)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: scanning
                )
        }
        .onAppear { scanning = true }
    }
}

// MARK: - AVFoundation Camera Representable

private struct QRCameraRepresentable: UIViewRepresentable {
    let scanner: QRCodeScanner

    func makeUIView(context: Context) -> UIView {
        scanner.makePreviewView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - QRCodeScanner (AVFoundation)

@MainActor
final class QRCodeScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func makePreviewView() -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return view
        }

        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        return view
    }

    func start() {
        guard !session.isRunning else { return }
        let captureSession = self.session
        Task.detached {
            captureSession.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        let captureSession = self.session
        Task.detached {
            captureSession.stopRunning()
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue else { return }
        Task { @MainActor [weak self] in
            self?.scannedCode = str
        }
    }
}

// MARK: - Simulator Fallback

private struct SimulatorQRFallback: View {
    @ObservedObject var viewModel: TenantSelectionViewModel

    private let samplePayload = """
    FRIENDS_TENANT:eyJ0eXBlIjoidGVuYW50X2ludml0ZSIsInZlcnNpb24iOjEsInRlbmFudElkIjoidF9kZWZhdWx0IiwidGVuYW50Q29kZSI6ImZyaWVuZHMua2FudG8ud29yayIsInRlbmFudE5hbWUiOiLjg4fjg5Xjgqnjg6vjg4giLCJ0ZW5hbnRNYXN0ZXJLZXkiOiJjTEUwZlR5ZXkxZzhDemlNQUlpN3UxM2MyMmRRZGkvVXpndFpYejcrVXBvPSIsImlzRGVmYXVsdFRlbmFudCI6dHJ1ZSwid29ya2VyQXBpVXJsIjoiaHR0cHM6Ly9mcmllbmRzLWFwaS5jZW8tZGM1LndvcmtlcnMuZGV2IiwicjJDb25maWciOnsicHVibGljQmFzZVVybCI6Imh0dHBzOi8vYnVja2V0LmZyaWVuZHMua2FudG8ud29yayIsImJ1Y2tldE5hbWUiOiJmcmllbmRzLWthbnRvd29yayIsImVuZHBvaW50VXJsIjoiaHR0cHM6Ly9kYzViM2JlYzBhNjg5MWU0MzUwZGE5NTEzYzNmYzVkYi5yMi5jbG91ZGZsYXJlc3RvcmFnZS5jb20iLCJhY2Nlc3NLZXlJZCI6ImEwNWVmMTlmMWRiNTI3NjMxZWE3OTllMGM5NjQ1MjAzIiwic2VjcmV0QWNjZXNzS2V5IjoiNDczOThjYjUwMmVlYWVlYzRmYzc3ZWFkNzNiZmU0MGY1YzdlZDBjNmNhOTVmYzcwZjYzYTMxZTQ4MTUyZDdmZCJ9fQ==
    """

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 220)

                VStack(spacing: 14) {
                    Image(systemName: "camera.slash.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.horizontal, 24)
            }

            Button {
                viewModel.verifyFromText(samplePayload)
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Tab: JSON / Text Input

private struct JSONInputTab: View {
    @ObservedObject var viewModel: TenantSelectionViewModel
    @FocusState private var isFocused: Bool

    private let templateJSON = """
    {
      "tenantId": "t_default",
      "tenantCode": "friends.kanto.work",
      "tenantName": "デフォルト",
      "tenantMasterKey": "<BASE64_MASTER_KEY>",
      "workerApiUrl": "https://friends-api.<subdomain>.workers.dev"
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Input field label
            HStack {
                Text(L10n.Tenant.inputLabel)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                Spacer()
                Button(L10n.Tenant.inputTemplate) {
                    viewModel.jsonInput = templateJSON
                    isFocused = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            TextEditor(text: $viewModel.jsonInput)
                .font(.system(.caption, design: .monospaced))
                .focused($isFocused)
                .padding(10)
                .frame(height: 150)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.blue.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1.5)
                )

            // Accepted format hints
            VStack(alignment: .leading, spacing: 4) {
                FormatHint(icon: "qrcode", text: "FRIENDS_TENANT:<base64>")
                FormatHint(icon: "doc.text", text: "{ \"tenantId\": ..., \"tenantMasterKey\": ... }")
            }

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
                .frame(height: 50)
                .background(
                    viewModel.jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.blue.opacity(0.4)
                        : Color.blue
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

private struct FormatHint: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
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

            TextField("https://example.com/preset-tenant.json", text: $viewModel.urlInput)
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
                        .stroke(isFocused ? Color.blue.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1.5)
                )

            // URL format hints
            VStack(alignment: .leading, spacing: 4) {
                FormatHint(icon: "globe", text: "https://example.com/preset-tenant.json")
                FormatHint(icon: "link", text: "http://192.168.1.10:8080/tenant.json (ローカル開発)")
            }

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
                .frame(height: 50)
                .background(
                    viewModel.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.blue.opacity(0.4)
                        : Color.blue
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
