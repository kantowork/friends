import SwiftUI
import AVFoundation

// MARK: - AddFriendView (C03 友達追加画面)
// 1. QRコードタブ: 上部にカメラ、下部に自分のQRコードのみを表示 (30秒毎に更新、パスコード内包)
// 2. テキストタブ: ユーザー名/ID と 3桁パスコードを表示。数字の横に円グラフとカウントダウン表示。コピーはユーザー名のみ。

struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chatService = ChatService.shared
    
    enum TabSelection: Int, CaseIterable {
        case qr = 0
        case text = 1
    }
    
    @State private var selectedTab: TabSelection = .qr
    @State private var timerNow = Date()
    @State private var timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    // Cached 30s QR image
    @State private var cachedQRImage: UIImage? = nil
    @State private var lastGeneratedStep: Int64 = -1
    
    // Text Code Tab Inputs
    @State private var targetInput: String = ""
    @State private var targetPasscode: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    
    // Success Dialog & Scanned Confirmation Sheet
    @State private var showSuccessAlert = false
    @State private var addedFriendName: String = ""
    @State private var scannedPayload: FriendsFriendInvitationPayload? = nil
    @State private var showingConfirmSheet = false
    @State private var isCopiedUserId = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Segmented Control
                Picker("", selection: $selectedTab) {
                    Text(L10n.Friend.tabQR).tag(TabSelection.qr)
                    Text(L10n.Friend.tabText).tag(TabSelection.text)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                
                // Content Tab Views
                if selectedTab == .qr {
                    qrOnlyView
                } else {
                    textCodeView
                }
            }
            .navigationTitle(L10n.Friend.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                updateQRCodeIfNeeded(date: timerNow)
            }
            .onReceive(timer) { input in
                timerNow = input
                updateQRCodeIfNeeded(date: input)
            }
            .alert(L10n.Friend.successAlertTitle, isPresented: $showSuccessAlert) {
                Button(L10n.Common.ok) {
                    dismiss()
                }
            } message: {
                Text(L10n.Friend.successAlertMsg(addedFriendName))
            }
            .sheet(isPresented: $showingConfirmSheet) {
                if let payload = scannedPayload {
                    FriendScanConfirmSheet(payload: payload) { confirmed in
                        showingConfirmSheet = false
                        if confirmed {
                            performAddFriend(payload: payload)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 1. QR Code Tab View (カメラとQRコードのみのミニマル表示・30秒毎更新)
    
    private var qrOnlyView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Half: Camera Scanner
                ZStack {
                    Color.black
                    
                    FriendCameraScannerView { detectedCode in
                        handleScannedCode(detectedCode)
                    }
                    
                    // Finder overlay guide
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
                        .frame(width: min(geometry.size.width * 0.7, 220), height: min(geometry.size.width * 0.7, 220))
                    
                    #if targetEnvironment(simulator)
                    VStack {
                        Spacer()
                        Button {
                            simulateScan()
                        } label: {
                            Label(L10n.Friend.cameraSimulatorBtn, systemImage: "qrcode")
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 12)
                    }
                    #endif
                }
                .frame(height: geometry.size.height * 0.5)
                .clipped()
                
                // Bottom Half: My QR Code Only (30秒毎に更新、余計なボタン・文字なし)
                VStack(spacing: 0) {
                    Spacer()
                    
                    if let qrImage = cachedQRImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(geometry.size.height * 0.38, 200), height: min(geometry.size.height * 0.38, 200))
                            .padding(14)
                            .background(Color.white)
                            .cornerRadius(18)
                            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                    } else {
                        ProgressView()
                            .frame(width: 180, height: 180)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: geometry.size.height * 0.5)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }
    
    // MARK: - 2. Text Code Tab View (ユーザー名・パスコード表示 & 円グラフカウントダウン & ユーザー名コピー & 相手ID入力)
    
    private var textCodeView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section A: 自分の情報表示 (ユーザー名/ID + 3桁パスコード & 円グラフカウントダウン)
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.Friend.myInfoSection)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    // User ID Row with Copy button
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Friend.userIdLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(myDisplayUserId)
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Button {
                            copyUserId()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCopiedUserId ? "checkmark" : "doc.on.doc")
                                Text(isCopiedUserId ? L10n.Common.copied : L10n.Common.copy)
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isCopiedUserId ? Color.green : Color.blue)
                            .cornerRadius(10)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    
                    // Passcode Display (30s rotation with Circular Countdown Meter)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.Friend.passcodeTitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 14) {
                            // 3-digit number boxes
                            HStack(spacing: 8) {
                                ForEach(Array(currentPasscode.enumerated()), id: \.offset) { _, char in
                                    Text(String(char))
                                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                                        .frame(width: 44, height: 48)
                                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                        )
                                }
                            }
                            
                            Spacer()
                            
                            // Circular Countdown Meter
                            CircularCountdownView(remainingSeconds: passcodeRemainingSeconds)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Divider()
                    .padding(.horizontal, 20)
                
                // Section B: 相手のユーザーを追加 (ユーザーID + 3桁合言葉入力)
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.Friend.textInputSection)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // User ID Input
                        TextField(L10n.Friend.targetUserIdPlaceholder, text: $targetInput)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        
                        // Passcode Input
                        HStack {
                            TextField(L10n.Friend.targetPasscodePlaceholder, text: $targetPasscode)
                                .font(.system(.body, design: .monospaced))
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                                .frame(maxWidth: 180)
                            
                            Spacer()
                        }
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button {
                        submitTextFriendAddition()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 6)
                            }
                            Text(L10n.Friend.confirmAdditionBtn)
                                .font(.body)
                                .bold()
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(isInputReady ? Color.blue : Color.blue.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isInputReady || isSubmitting)
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Computed Properties & Helpers
    
    private var myDisplayUserId: String {
        chatService.currentUser?.effectiveUsername ?? "guest"
    }
    
    private var currentPasscode: String {
        guard let user = chatService.currentUser, let tenant = chatService.currentTenant else {
            return "000"
        }
        return FriendPasscodeGenerator.generatePasscode(uid: user.uid, tenantId: tenant.tenantID, date: timerNow)
    }
    
    private var passcodeRemainingSeconds: Int {
        FriendPasscodeGenerator.remainingSeconds(date: timerNow)
    }
    
    /// 30秒毎（ステップ更新時）にのみQRコードを再生成する
    private func updateQRCodeIfNeeded(date: Date) {
        let step = FriendPasscodeGenerator.currentStep(date: date)
        guard step != lastGeneratedStep || cachedQRImage == nil else { return }
        guard let user = chatService.currentUser, let tenant = chatService.currentTenant else { return }
        
        let passcodeForStep = FriendPasscodeGenerator.code(forStep: step, uid: user.uid, tenantId: tenant.tenantID)
        let stepTimestamp = step * Int64(FriendPasscodeGenerator.stepInterval)
        
        var payload = FriendsFriendInvitationPayload()
        payload.type = "friend_invite"
        payload.version = 1
        payload.tenantID = tenant.tenantID
        payload.userID = user.userID
        payload.uid = user.uid
        payload.displayName = user.displayName
        payload.publicKey = user.publicKey
        payload.passcode = passcodeForStep
        payload.timestamp = stepTimestamp
        
        let qrString = FriendInvitationHelper.encode(payload: payload)
        self.cachedQRImage = QRCodeGeneratorHelper.generateQRCode(from: qrString)
        self.lastGeneratedStep = step
    }
    
    private var isInputReady: Bool {
        let cleanInput = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPasscode = targetPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanInput.isEmpty && cleanPasscode.count == 3
    }
    
    // MARK: - Actions
    
    private func copyUserId() {
        UIPasteboard.general.string = "@\(myDisplayUserId)"
        isCopiedUserId = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isCopiedUserId = false
        }
    }
    
    private func handleScannedCode(_ code: String) {
        guard let payload = FriendInvitationHelper.decode(rawInput: code) else {
            return
        }
        scannedPayload = payload
        showingConfirmSheet = true
    }
    
    private func submitTextFriendAddition() {
        let cleanInput = targetInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        let cleanPasscode = targetPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        errorMessage = nil
        isSubmitting = true
        
        // 1. Check if raw input is a full payload string (FRIENDS_USER:...)
        if cleanInput.hasPrefix("FRIENDS_USER:") || cleanInput.hasPrefix("friends://") {
            guard let payload = FriendInvitationHelper.decode(rawInput: cleanInput) else {
                errorMessage = L10n.Error.Friend.invalidFormat
                isSubmitting = false
                return
            }
            performAddFriend(payload: payload, explicitPasscode: cleanPasscode.isEmpty ? nil : cleanPasscode)
            return
        }
        
        // 2. Otherwise treat as Username / UserID
        chatService.addFriendByUsername(targetUsername: cleanInput, passcode: cleanPasscode) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let friend):
                    self.addedFriendName = friend.displayName
                    self.showSuccessAlert = true
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func performAddFriend(payload: FriendsFriendInvitationPayload, explicitPasscode: String? = nil) {
        isSubmitting = true
        errorMessage = nil
        
        chatService.addFriend(from: payload, explicitPasscode: explicitPasscode) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let friend):
                    self.addedFriendName = friend.displayName
                    self.showSuccessAlert = true
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func simulateScan() {
        guard let tenant = chatService.currentTenant else { return }
        let currentStep = FriendPasscodeGenerator.currentStep(date: timerNow)
        let mockPasscode = FriendPasscodeGenerator.code(forStep: currentStep, uid: "simulated_auth_uid_999", tenantId: tenant.tenantID)
        
        var mockPayload = FriendsFriendInvitationPayload()
        mockPayload.type = "friend_invite"
        mockPayload.version = 1
        mockPayload.tenantID = tenant.tenantID
        mockPayload.userID = "u_simulated_friend"
        mockPayload.uid = "simulated_auth_uid_999"
        mockPayload.displayName = "テスト友達 (Simulated)"
        mockPayload.publicKey = "mockPublicKeyBase64=="
        mockPayload.passcode = mockPasscode
        mockPayload.timestamp = currentStep * Int64(FriendPasscodeGenerator.stepInterval)
        
        let encoded = FriendInvitationHelper.encode(payload: mockPayload)
        handleScannedCode(encoded)
    }
}

// MARK: - Circular Countdown Meter View (小さな円グラフ & 残り秒数カウントダウン)

struct CircularCountdownView: View {
    let remainingSeconds: Int
    let totalSeconds: Double = 30.0
    
    private var progress: Double {
        Double(remainingSeconds) / totalSeconds
    }
    
    var body: some View {
        ZStack {
            // Background circle track
            Circle()
                .stroke(Color.orange.opacity(0.2), lineWidth: 3.5)
            
            // Remaining progress ring
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1.0, progress))))
                .stroke(
                    Color.orange,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            
            Text("\(remainingSeconds)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Friend Confirmation Sheet

struct FriendScanConfirmSheet: View {
    let payload: FriendsFriendInvitationPayload
    let onConfirm: (Bool) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 88, height: 88)
                    .overlay(
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 44))
                            .foregroundColor(.blue)
                    )
                
                VStack(spacing: 6) {
                    Text(payload.displayName)
                        .font(.title2)
                        .bold()
                    Text(L10n.Friend.userIdPrefix(payload.userID))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(L10n.Friend.confirmSheetMsg(payload.displayName, payload.userID))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button {
                        onConfirm(true)
                    } label: {
                        Text(L10n.Friend.confirmAdditionBtn)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.blue)
                            .cornerRadius(14)
                    }
                    
                    Button(L10n.Common.cancel) {
                        onConfirm(false)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(L10n.Friend.confirmSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - AVFoundation Camera Scanner View

struct FriendCameraScannerView: UIViewControllerRepresentable {
    let onCodeDetected: (String) -> Void
    
    func makeUIViewController(context: Context) -> FriendCameraScannerViewController {
        let controller = FriendCameraScannerViewController()
        controller.onCodeDetected = onCodeDetected
        return controller
    }
    
    func updateUIViewController(_ uiViewController: FriendCameraScannerViewController, context: Context) {}
}

class FriendCameraScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeDetected: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCaptureSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.stopRunning()
            }
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        
        self.previewLayer = preview
        self.captureSession = session
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }
        
        hasScanned = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onCodeDetected?(stringValue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.hasScanned = false
        }
    }
}
