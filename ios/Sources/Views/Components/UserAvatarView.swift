import SwiftUI

// MARK: - UserAvatarView
// キャッシュ優先で暗号化アバター画像を表示し、画像がない場合はグラデーション背景と頭文字イニシャルを表示する共通コンポーネント

public struct UserAvatarView: View {
    let userId: String
    let displayName: String
    let avatarNonce: String
    let avatarUpdatedAt: Date?
    let size: CGFloat
    
    @ObservedObject private var chatService = ChatService.shared
    @State private var loadedImage: UIImage? = nil
    
    public init(
        userId: String,
        displayName: String,
        avatarNonce: String = "",
        avatarUpdatedAt: Date? = nil,
        size: CGFloat = 48
    ) {
        self.userId = userId
        self.displayName = displayName
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
                // フォールバック: 頭文字イニシャル + モダングラデーション
                Circle()
                    .fill(avatarGradient)
                    .frame(width: size, height: size)
                
                Text(initialLetter)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .id("\(userId)_\(avatarNonce)_\(avatarUpdatedAt?.timeIntervalSince1970 ?? 0)")
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
        return loadedImage ?? chatService.getCachedAvatar(userId: userId, updatedAt: avatarUpdatedAt)
    }


    
    private var initialLetter: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }
    
    private var avatarGradient: LinearGradient {
        // ユーザーIDに基づいた決定論的で美しいカラーグラデーション
        let hash = abs(userId.hashValue)
        let gradients: [[Color]] = [
            [Color.blue.opacity(0.85), Color.indigo.opacity(0.9)],
            [Color.teal.opacity(0.85), Color.cyan.opacity(0.9)],
            [Color.purple.opacity(0.85), Color.pink.opacity(0.9)],
            [Color.orange.opacity(0.85), Color.red.opacity(0.9)],
            [Color.green.opacity(0.85), Color.mint.opacity(0.9)],
            [Color.indigo.opacity(0.85), Color.blue.opacity(0.9)]
        ]
        let colors = gradients[hash % gradients.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    private func loadImageIfNeeded() {
        // キャッシュに存在するか確認
        if let cached = chatService.getCachedAvatar(userId: userId, updatedAt: avatarUpdatedAt) {
            self.loadedImage = cached
            return
        }
        
        guard !avatarNonce.isEmpty else { return }
        
        chatService.loadAvatarImage(userId: userId, avatarNonce: avatarNonce, updatedAt: avatarUpdatedAt) { result in
            DispatchQueue.main.async {
                if case .success(let image) = result {
                    self.loadedImage = image
                }
            }
        }
    }
}
