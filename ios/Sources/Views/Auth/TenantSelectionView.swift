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

        guard let tenantId = extractTenantId(from: input) else {
            verificationState = .failure("形式が正しくありません。")
            return
        }
        verify(tenantId: tenantId)
    }

    func verifyFromUrl() {
        let raw = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        // friends://tenant?id=t_xxxx  or  https://friends.kanto.work/tenant?id=t_xxxx
        if let url = URL(string: raw),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let tid = components.queryItems?.first(where: { $0.name == "id" })?.value,
           tid.hasPrefix("t_") {
            verify(tenantId: tid)
        } else {
            verificationState = .failure("形式が正しくありません。")
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
                if let masterKey = json["tenantMasterKey"] as? String ?? json["masterKey"] as? String {
                    CryptoKeyManager.shared.saveTenantMasterKey(tenantId: tid, masterKeyBase64: masterKey)
                }
                return tid
            }
            return nil
        }
        // 2. JSON object
        if let data = input.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tid = json["tenantId"] as? String {
            if let masterKey = json["tenantMasterKey"] as? String ?? json["masterKey"] as? String {
                CryptoKeyManager.shared.saveTenantMasterKey(tenantId: tid, masterKeyBase64: masterKey)
            }
            return tid
        }
        // 3. Raw tenantId (t_ prefix)
        if input.hasPrefix("t_") {
            return input
        }
        return nil
    }

    private func verify(tenantId: String) {
        verificationState = .loading
        chatService.verifyAndApplyTenant(tenantId: tenantId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let tenant):
                    self?.verificationState = .success(tenant)
                case .failure(let error):
                    self?.verificationState = .failure("検証失敗: \(error.localizedDescription)")
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
                    Text("QRコードをフレーム内に合わせてください")
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
    FRIENDS_TENANT:eyJ0ZW5hbnRJZCI6InRfZGVmYXVsdCJ9
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
                        .foregroundColor(.secondary)
                    Text(L10n.Tenant.cameraSimulatorNote)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            }

            Button {
                viewModel.verifyFromText(samplePayload)
            } label: {
                Label(L10n.Tenant.cameraSimulatorBtn, systemImage: "qrcode")
                    .font(.subheadline.weight(.semibold))
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
      "tenantId": "t_xxxxx"
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
                FormatHint(icon: "doc.text", text: "{ \"tenantId\": \"t_xxxx\" }")
                FormatHint(icon: "textformat.abc", text: "t_xxxxxxxxxxxxxxxx（IDの直接入力）")
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

            TextField("friends://tenant?id=t_xxxx", text: $viewModel.urlInput)
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
                FormatHint(icon: "iphone.smartbubble", text: "friends://tenant?id=t_xxxx")
                FormatHint(icon: "globe", text: "https://friends.kanto.work/tenant?id=t_xxxx")
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
