import SwiftUI

/// フルスクリーンで画像を閲覧・拡大縮小（ピンチイン/アウト）・複数画像のスワイプおよびダウンロード保存ができるビューアーモーダル
struct ImageViewerView: View {
    let attachments: [MessageAttachment]
    let initialIndex: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var feedbackMessage: String? = nil
    @State private var isSaving: Bool = false
    
    // 各画像ごとのキャッシュ/ロード済みイメージ保持用
    @State private var loadedImages: [Int: UIImage] = [:]
    
    init(attachments: [MessageAttachment], initialIndex: Int = 0) {
        self.attachments = attachments
        self.initialIndex = max(0, min(initialIndex, max(0, attachments.count - 1)))
        self._currentIndex = State(initialValue: max(0, min(initialIndex, max(0, attachments.count - 1))))
    }
    
    // 単一UIImageから開く場合のフォールバックイニシャライザ
    init(image: UIImage) {
        self.attachments = []
        self.initialIndex = 0
        self._currentIndex = State(initialValue: 0)
        self._loadedImages = State(initialValue: [0: image])
    }
    
    private var isMultiple: Bool {
        attachments.count > 1
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 画像スワイプページャー
            if attachments.isEmpty {
                if let singleImg = loadedImages[0] {
                    ZoomableImageView(image: singleImg, onDismiss: { dismiss() })
                }
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(0..<attachments.count, id: \.self) { idx in
                        AttachmentViewerPage(
                            attachment: attachments[idx],
                            onImageLoaded: { img in
                                loadedImages[idx] = img
                            },
                            onDismiss: { dismiss() }
                        )
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            
            // 上部ツールバー（左上: ✕閉じる、右上: ダウンロードボタン）
            VStack {
                HStack(spacing: 16) {
                    // 左上: 閉じるボタン (xmark.circle.fill)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(16)
                    }
                    .accessibilityLabel(L10n.Common.close)
                    
                    Spacer()
                    
                    // 右上: 保存ボタン（アイコンは1つ）
                    Group {
                        if isMultiple {
                            // 複数枚時: メニュー表示（「この写真を保存」/「写真(n)を保存」）
                            Menu {
                                Button {
                                    saveCurrentPhoto()
                                } label: {
                                    Label(L10n.Chat.viewerSaveCurrent, systemImage: "photo")
                                }
                                
                                Button {
                                    saveAllPhotos()
                                } label: {
                                    Label(L10n.Chat.viewerSaveAll(attachments.count), systemImage: "photo.stack")
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(8)
                                    .background(Color.black.opacity(0.45))
                                    .clipShape(Circle())
                            }
                            .disabled(isSaving)
                            .accessibilityLabel(L10n.Chat.viewerSaveCurrent)
                        } else {
                            // 単一画像時: タップでそのまま保存
                            Button {
                                saveCurrentPhoto()
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(8)
                                    .background(Color.black.opacity(0.45))
                                    .clipShape(Circle())
                            }
                            .disabled(isSaving)
                            .accessibilityLabel(L10n.Chat.viewerSaveCurrent)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // 下部バー（左下: ◀前へ、中央: ページ番号、右下: ▶次へ）
                if isMultiple {
                    HStack {
                        // 左下: 前へボタン
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if currentIndex > 0 {
                                    currentIndex -= 1
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(currentIndex > 0 ? .white.opacity(0.9) : .white.opacity(0.25))
                                .padding(16)
                        }
                        .disabled(currentIndex == 0)
                        .accessibilityLabel(L10n.Chat.viewerPrevious)
                        
                        Spacer()
                        
                        // 中央: ページ表示 (例: 1 / 3)
                        Text(L10n.Chat.viewerPageFormat(currentIndex + 1, attachments.count))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(12)
                        
                        Spacer()
                        
                        // 右下: 次へボタン
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if currentIndex < attachments.count - 1 {
                                    currentIndex += 1
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(currentIndex < attachments.count - 1 ? .white.opacity(0.9) : .white.opacity(0.25))
                                .padding(16)
                        }
                        .disabled(currentIndex >= attachments.count - 1)
                        .accessibilityLabel(L10n.Chat.viewerNext)
                    }
                    .padding(.bottom, 20)
                }
            }
            
            // フィードバックトースト表示
            if let msg = feedbackMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                        .padding(.bottom, isMultiple ? 80 : 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                .zIndex(100)
            }
        }
    }
    
    // MARK: - Save Handlers
    
    private func saveCurrentPhoto() {
        guard !isSaving else { return }
        
        let targetImage: UIImage?
        if attachments.isEmpty {
            targetImage = loadedImages[0]
        } else if let img = loadedImages[currentIndex] {
            targetImage = img
        } else if let cached = AttachmentRepository.shared.getCachedImage(attachmentId: attachments[currentIndex].attachmentId) {
            targetImage = cached
        } else {
            targetImage = nil
        }
        
        guard let img = targetImage else {
            // 画像がまだロードされていない場合は取得して保存
            if !attachments.isEmpty {
                isSaving = true
                AttachmentRepository.shared.fetchAttachmentImage(attachment: attachments[currentIndex]) { result in
                    DispatchQueue.main.async {
                        self.isSaving = false
                        switch result {
                        case .success(let fetchedImg):
                            self.loadedImages[self.currentIndex] = fetchedImg
                            self.executeSave(image: fetchedImg)
                        case .failure:
                            self.showToast(L10n.Chat.viewerSaveFailed)
                        }
                    }
                }
            }
            return
        }
        
        executeSave(image: img)
    }
    
    private func executeSave(image: UIImage) {
        isSaving = true
        ImageSaveHelper.shared.saveImage(image) { result in
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success:
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    self.showToast(L10n.Chat.viewerSaveSuccess)
                case .failure:
                    self.showToast(L10n.Chat.viewerSaveFailed)
                }
            }
        }
    }
    
    private func saveAllPhotos() {
        guard !attachments.isEmpty, !isSaving else { return }
        isSaving = true
        
        let group = DispatchGroup()
        var imagesToSave: [UIImage] = []
        let lock = NSLock()
        
        for att in attachments {
            if let cached = loadedImages[attachments.firstIndex(where: { $0.id == att.id }) ?? -1] ?? AttachmentRepository.shared.getCachedImage(attachmentId: att.attachmentId) {
                lock.lock()
                imagesToSave.append(cached)
                lock.unlock()
            } else {
                group.enter()
                AttachmentRepository.shared.fetchAttachmentImage(attachment: att) { result in
                    if case .success(let img) = result {
                        lock.lock()
                        imagesToSave.append(img)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            guard !imagesToSave.isEmpty else {
                self.isSaving = false
                self.showToast(L10n.Chat.viewerSaveFailed)
                return
            }
            
            let saveGroup = DispatchGroup()
            var saveCount = 0
            
            for img in imagesToSave {
                saveGroup.enter()
                ImageSaveHelper.shared.saveImage(img) { res in
                    if case .success = res {
                        lock.lock()
                        saveCount += 1
                        lock.unlock()
                    }
                    saveGroup.leave()
                }
            }
            
            saveGroup.notify(queue: .main) {
                self.isSaving = false
                if saveCount > 0 {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    self.showToast(L10n.Chat.viewerSaveAllSuccess(saveCount))
                } else {
                    self.showToast(L10n.Chat.viewerSaveFailed)
                }
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation {
            feedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if self.feedbackMessage == text {
                    self.feedbackMessage = nil
                }
            }
        }
    }
}

// MARK: - Individual Attachment Page

private struct AttachmentViewerPage: View {
    let attachment: MessageAttachment
    let onImageLoaded: (UIImage) -> Void
    let onDismiss: () -> Void
    
    @State private var image: UIImage? = nil
    @State private var isLoading: Bool = true
    
    var body: some View {
        Group {
            if let img = image {
                ZoomableImageView(image: img, onDismiss: onDismiss)
            } else if isLoading {
                ZStack {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.6))
                    Text(L10n.Chat.uploadFailed)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        if let cached = AttachmentRepository.shared.getCachedImage(attachmentId: attachment.attachmentId) {
            self.image = cached
            self.isLoading = false
            self.onImageLoaded(cached)
            return
        }
        
        AttachmentRepository.shared.fetchAttachmentImage(attachment: attachment) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if case .success(let fetched) = result {
                    self.image = fetched
                    self.onImageLoaded(fetched)
                }
            }
        }
    }
}

// MARK: - Zoomable & Pannable Image View

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let onDismiss: () -> Void
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.isScrollEnabled = false // 等倍時はスクロール無効化し親の左右スワイプを最優先
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        
        // ダブルタップでズームイン/アウト
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        // 等倍時の下スワイプで閉じるジェスチャー
        let swipeDown = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeDown(_:)))
        swipeDown.delegate = context.coordinator
        scrollView.addGestureRecognizer(swipeDown)
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image != image {
            context.coordinator.imageView?.image = image
            uiView.setZoomScale(1.0, animated: false)
            uiView.isScrollEnabled = false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        let onDismiss: () -> Void
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.isScrollEnabled = scrollView.zoomScale > 1.01
        }
        
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            if scale <= 1.01 {
                scrollView.setZoomScale(1.0, animated: true)
                scrollView.isScrollEnabled = false
            } else {
                scrollView.isScrollEnabled = true
            }
        }
        
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1.0, animated: true)
                scrollView.isScrollEnabled = false
            } else {
                let point = recognizer.location(in: imageView)
                let targetScale: CGFloat = 2.5
                let w = scrollView.bounds.width / targetScale
                let h = scrollView.bounds.height / targetScale
                let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
                scrollView.zoom(to: rect, animated: true)
                scrollView.isScrollEnabled = true
            }
        }
        
        @objc func handleSwipeDown(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = scrollView, scrollView.zoomScale <= 1.01 else { return }
            let translation = recognizer.translation(in: scrollView)
            let velocity = recognizer.velocity(in: scrollView)
            
            if recognizer.state == .ended {
                if translation.y > 60 && velocity.y > 150 {
                    onDismiss()
                }
            }
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView = scrollView else { return false }
            if scrollView.zoomScale > 1.01 { return false }
            let velocity = pan.velocity(in: scrollView)
            // 下方向のドラッグのみを認識し、水平ドラッグは親の TabView に譲る
            return velocity.y > 50 && abs(velocity.y) > abs(velocity.x) * 1.5
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
    }
}
