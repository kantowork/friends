//
//  TwoDimensionalCodeScannerView.swift
//  Friends
//
//  共通二次元コード（QRコード）スキャナーコンポーネント
//  無駄なアニメーションを排除し、シンプルなガイド枠と安定したカメラ読み取りを提供します。
//

import SwiftUI
import AVFoundation
import AudioToolbox

// MARK: - Public Component

/// 二次元コード（QRコード）をカメラから読み取る共通ビュー
public struct TwoDimensionalCodeScannerView: View {
    /// ガイド枠のサイズ（正方形の一辺の長さ）
    public let guideSize: CGFloat
    /// ガイド枠を表示するかどうか
    public let showsGuide: Bool
    /// コード検出時のコールバック
    public let onCodeDetected: (String) -> Void

    @StateObject private var scanner = TwoDimensionalCodeScannerEngine()

    public init(
        guideSize: CGFloat = 200,
        showsGuide: Bool = true,
        onCodeDetected: @escaping (String) -> Void
    ) {
        self.guideSize = guideSize
        self.showsGuide = showsGuide
        self.onCodeDetected = onCodeDetected
    }

    public var body: some View {
        ZStack {
            Color.black

            #if targetEnvironment(simulator)
            SimulatorCameraPlaceholder()
            #else
            CameraPreviewRepresentable(session: scanner.session)
                .ignoresSafeArea()
            #endif

            if showsGuide {
                SimpleScanGuideArea(size: guideSize)
            }
        }
        .clipped()
        .onAppear {
            scanner.onCodeDetected = { code in
                onCodeDetected(code)
            }
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
    }
}

// MARK: - Scan Guide Area (シンプルなガイド枠)

private struct SimpleScanGuideArea: View {
    let size: CGFloat
    private let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            // 背景の薄暗い半透明マスク（ガイド領域のみくり抜き）
            ScanHoleShape(holeSize: CGSize(width: size, height: size), cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))

            // シンプルな角丸ガイド枠線（アニメーションなし）
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.85), lineWidth: 2)
                .frame(width: size, height: size)
        }
    }
}

/// 中央の読み取り領域をくり抜くシェイプ
private struct ScanHoleShape: Shape {
    let holeSize: CGSize
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let holeRect = CGRect(
            x: rect.midX - holeSize.width / 2,
            y: rect.midY - holeSize.height / 2,
            width: holeSize.width,
            height: holeSize.height
        )
        path.addRoundedRect(in: holeRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

// MARK: - Simulator Placeholder

private struct SimulatorCameraPlaceholder: View {
    var body: some View {
        ZStack {
            Color.black
            Image(systemName: "camera.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

// MARK: - Camera Preview Representable

#if !targetEnvironment(simulator)
private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Layer must be AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
#endif

// MARK: - Scanner Engine

@MainActor
private final class TwoDimensionalCodeScannerEngine: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    var onCodeDetected: ((String) -> Void)?
    private var isConfigured = false
    private var isCoolingDown = false

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        #if !targetEnvironment(simulator)
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        #endif
    }

    func start() {
        configureSessionIfNeeded()
        guard !session.isRunning else { return }
        let captureSession = session
        Task.detached {
            captureSession.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        let captureSession = session
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
              let code = obj.stringValue else { return }

        Task { @MainActor [weak self] in
            guard let self = self, !self.isCoolingDown else { return }
            self.isCoolingDown = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            self.onCodeDetected?(code)

            // 1.5秒間のクールダウン（連続誤検知防止）
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.isCoolingDown = false
        }
    }
}
