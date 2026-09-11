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

private struct ZoomableImageView: View {
    let image: UIImage
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1.0 {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { value in
                        if scale > 1.0 {
                            lastOffset = offset
                        } else if abs(value.translation.height) > 100 {
                            onDismiss()
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                    }
                }
            }
    }
}
