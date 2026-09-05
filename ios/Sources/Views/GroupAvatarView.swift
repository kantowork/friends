import SwiftUI

// MARK: - GroupAvatarView
// グループ用アバター画像（R2/キャッシュ）を表示し、未設定時はグラデーション背景とグループアイコンを表示する共通コンポーネント

public struct GroupAvatarView: View {
    let chatId: String
    let avatarNonce: String
    let avatarUpdatedAt: Date?
    let size: CGFloat
    
    @ObservedObject private var chatService = ChatService.shared
    @State private var loadedImage: UIImage? = nil
    
    public init(
        chatId: String,
        avatarNonce: String = "",
        avatarUpdatedAt: Date? = nil,
        size: CGFloat = 48
    ) {
        self.chatId = chatId
        self.avatarNonce = avatarNonce
        self.avatarUpdatedAt = avatarUpdatedAt
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            if let image = effectiveImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                // デフォルト: オレンジ・ピンクグラデーション + person.3.fill
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.8), Color.pink.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: size, height: size)
                
                Image(systemName: "person.3.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .id("\(chatId)_\(avatarNonce)_\(avatarUpdatedAt?.timeIntervalSince1970 ?? 0)")
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: avatarUpdatedAt) { _ in
            self.loadedImage = nil
            loadImageIfNeeded()
        }
        .onChange(of: avatarNonce) { newNonce in
            self.loadedImage = nil
            if !newNonce.isEmpty {
                loadImageIfNeeded()
            }
        }
    }
    
    private var effectiveImage: UIImage? {
        if avatarNonce.isEmpty && avatarUpdatedAt == nil {
            return nil
        }
        if let loaded = loadedImage {
            return loaded
        }
        return AvatarRepository.shared.getCachedGroupAvatar(chatId: chatId, updatedAt: avatarUpdatedAt)
    }
    
    private func loadImageIfNeeded() {
        guard !avatarNonce.isEmpty else { return }
        if let cached = AvatarRepository.shared.getCachedGroupAvatar(chatId: chatId, updatedAt: avatarUpdatedAt) {
            self.loadedImage = cached
            return
        }
        
        guard let tenantId = chatService.currentTenant?.tenantID else { return }
        
        AvatarRepository.shared.getGroupAvatar(
            tenantId: tenantId,
            chatId: chatId,
            avatarNonce: avatarNonce,
            updatedAt: avatarUpdatedAt
        ) { result in
            DispatchQueue.main.async {
                if case .success(let image) = result {
                    self.loadedImage = image
                }
            }
        }
    }
}
