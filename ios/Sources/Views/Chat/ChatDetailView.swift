import SwiftUI
import PhotosUI

struct ChatDetailView: View {
    let chat: FriendsChatUIModel
    @ObservedObject var chatService = ChatService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedMessageForReactions: DecryptedMessage? = nil
    
    // 写真・添付ファイル用ステート
    @State private var showingAttachmentActionSheet: Bool = false
    @State private var showingCameraPicker: Bool = false
    @State private var showingPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isSendingImages: Bool = false
    @State private var cameraUnavailableAlert: Bool = false
    
    // 全体スワイプによる詳細・ユーザー名の一括表示状態
    @State private var isAllDetailsRevealed: Bool = false
    @GestureState private var globalDragOffset: CGFloat = 0
    
    init(chat: FriendsChatUIModel) {
        self.chat = chat
    }
    
    @ObservedObject var blockManager = BlockManager.shared
    
    var currentMessages: [DecryptedMessage] {
        let all = chatService.messages[chat.chatID] ?? []
        return all.filter { !blockManager.isBlocked(userId: $0.senderID) }
    }
    
    @State private var lastBottomMessageId: String? = nil
    @State private var isAtBottom: Bool = true
    @State private var hasUnseenNewMessages: Bool = false
    @State private var isInitialScrollDone: Bool = false
    @State private var showingEditFriendNameAlert: Bool = false
    @State private var editingFriendNameText: String = ""
    @State private var showingBlockConfirmAlert: Bool = false
    @State private var showingUnblockConfirmAlert: Bool = false
    
    private var peerFriend: FriendsPublicUserProfile? {
        if chat.chatType == .direct {
            let myUserId = chatService.currentUser?.userID ?? ""
            let peerId = chat.chat.members.first(where: { $0 != myUserId }) ?? ""
            if !peerId.isEmpty, let friend = chatService.friends.first(where: { $0.userID == peerId }) {
                return friend
            }
            if chat.chatID.hasPrefix("dm_") {
                let rawStr = String(chat.chatID.dropFirst(3))
                let parts = rawStr.components(separatedBy: "_u_")
                if parts.count == 2 {
                    let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                    let userB = "u_" + parts[1]
                    let foundPeerId = [userA, userB].first(where: { $0 != myUserId }) ?? ""
                    return chatService.friends.first(where: { $0.userID == foundPeerId })
                }
            }
        }
        return nil
    }
    
    private var resolvedTitle: String {
        if chat.chatType == .direct, let friend = peerFriend {
            return friend.displayName
        }
        return chat.displayTitle
    }
    
    private var isPeerBlocked: Bool {
        guard chat.chatType == .direct, let peer = peerFriend else { return false }
        return blockManager.isBlocked(userId: peer.userID)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Messages Scroll
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            // 過去メッセージのオンデマンド遡りロード領域
                            if (chatService.hasMoreMessages[chat.chatID] ?? false) && !currentMessages.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.85)
                                    Text(L10n.Common.loading)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .onAppear {
                                    if isInitialScrollDone {
                                        chatService.loadMoreMessages(chatId: chat.chatID)
                                    }
                                }
                            }
                            
                            if currentMessages.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary.opacity(0.6))
                                    Text(L10n.Chat.detailEmpty)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else {
                                ForEach(currentMessages) { message in
                                    MessageBubbleView(
                                        message: message,
                                        chatId: chat.chatID,
                                        isFromMe: message.senderID == chatService.currentUser?.userID || message.senderID == chatService.currentUser?.uid,
                                        isGroup: chat.chatType == .group,
                                        isAllDetailsRevealed: isAllDetailsRevealed,
                                        globalDragOffset: globalDragOffset,
                                        onShowReactionDetails: {
                                            selectedMessageForReactions = message
                                        }
                                    )
                                    .id(message.id)
                                }
                            }
                            
                            // 最下部検知用アンカー
                            Color.clear
                                .frame(height: 1)
                                .id("bottom_anchor")
                                .onAppear {
                                    isAtBottom = true
                                    hasUnseenNewMessages = false
                                }
                                .onDisappear {
                                    isAtBottom = false
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: currentMessages.count) { _ in
                        guard let lastMsg = currentMessages.last else { return }
                        let isNewBottom = (lastBottomMessageId == nil || lastBottomMessageId != lastMsg.id)
                        lastBottomMessageId = lastMsg.id
                        
                        if !isInitialScrollDone {
                            isInitialScrollDone = true
                            withAnimation {
                                proxy.scrollTo("bottom_anchor", anchor: .bottom)
                            }
                            chatService.markAsRead(
                                chatId: chat.chatID,
                                lastMessageId: lastMsg.id,
                                lastMessageDate: lastMsg.createdDate
                            )
                        } else if isNewBottom {
                            if isAtBottom {
                                // 画面下部にいる場合は最新メッセージを表示し既読化
                                withAnimation {
                                    proxy.scrollTo("bottom_anchor", anchor: .bottom)
                                }
                                chatService.markAsRead(
                                    chatId: chat.chatID,
                                    lastMessageId: lastMsg.id,
                                    lastMessageDate: lastMsg.createdDate
                                )
                            } else {
                                // 過去メッセージを閲覧中の場合は勝手にスクロールさせず新着バナーを表示
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    hasUnseenNewMessages = true
                                }
                            }
                        }
                    }
                    .onChange(of: currentMessages.last?.id) { _ in
                        guard let lastMsg = currentMessages.last else { return }
                        let isNewBottom = (lastBottomMessageId == nil || lastBottomMessageId != lastMsg.id)
                        lastBottomMessageId = lastMsg.id
                        
                        if isAtBottom || !isInitialScrollDone {
                            isInitialScrollDone = true
                            chatService.markAsRead(
                                chatId: chat.chatID,
                                lastMessageId: lastMsg.id,
                                lastMessageDate: lastMsg.createdDate
                            )
                        } else if isNewBottom {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                hasUnseenNewMessages = true
                            }
                        }
                    }
                    
                    // 新着メッセージ通知フローティングバナー (タップで最新メッセージ/既読位置へスクロール)
                    if hasUnseenNewMessages, let lastMsg = currentMessages.last {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo("bottom_anchor", anchor: .bottom)
                                hasUnseenNewMessages = false
                            }
                            chatService.markAsRead(
                                chatId: chat.chatID,
                                lastMessageId: lastMsg.id,
                                lastMessageDate: lastMsg.createdDate
                            )
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(L10n.Chat.newMessagesBadge)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                        }
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(10)
                    }
                }
            }
            
            Divider()
            
            // Message Input Bar or Blocked Banner
            if isPeerBlocked {
                HStack(spacing: 12) {
                    Image(systemName: "shield.slash.fill")
                        .foregroundColor(.secondary)
                    Text(L10n.Block.blockedBanner)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(L10n.Block.unblockAction) {
                        showingUnblockConfirmAlert = true
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))
            } else {
                if isSendingImages {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(L10n.Chat.sendingImages)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.8))
                }
                
                HStack(spacing: 8) {
                    // [ 写真アイコン ]
                    Button {
                        showingAttachmentActionSheet = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 38, height: 38)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .disabled(isSendingImages)
                    
                    // [ テキスト入力欄 ]
                    TextField(L10n.Chat.inputPlaceholder, text: $messageText, axis: .vertical)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit {
                            performSendMessage()
                        }
                    
                    // [ 送信アイコン ]
                    Button {
                        performSendMessage()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingImages)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
            }
        }
        .navigationTitle(resolvedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if chat.chatType == .group {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: GroupDetailView(chat: chat)) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                    }
                }
            } else if let friend = peerFriend {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            editingFriendNameText = friend.displayName
                            showingEditFriendNameAlert = true
                        } label: {
                            Label(L10n.Friend.editNameAction, systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        if isPeerBlocked {
                            Button {
                                showingUnblockConfirmAlert = true
                            } label: {
                                Label(L10n.Block.unblockAction, systemImage: "shield.slash")
                            }
                        } else {
                            Button(role: .destructive) {
                                showingBlockConfirmAlert = true
                            } label: {
                                Label(L10n.Block.action, systemImage: "shield.slash.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                    }
                }
            }
        }
        .alert(L10n.Friend.editNameTitle, isPresented: $showingEditFriendNameAlert) {
            TextField(L10n.Friend.editNamePlaceholder, text: $editingFriendNameText)
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Friend.editNameSave) {
                if let friend = peerFriend {
                    let trimmed = editingFriendNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        chatService.updateFriendDisplayName(friendUserId: friend.userID, newDisplayName: trimmed) { _ in }
                    }
                }
            }
        } message: {
            Text(L10n.Friend.editNameMessage)
        }
        .alert(L10n.Block.confirmTitle(peerFriend?.displayName ?? ""), isPresented: $showingBlockConfirmAlert) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Block.execute, role: .destructive) {
                if let peer = peerFriend {
                    blockManager.block(userId: peer.userID)
                }
            }
        } message: {
            Text(L10n.Block.confirmMsg)
        }
        .alert(L10n.Block.unblockConfirmTitle(peerFriend?.displayName ?? ""), isPresented: $showingUnblockConfirmAlert) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Block.unblockExecute) {
                if let peer = peerFriend {
                    blockManager.unblock(userId: peer.userID)
                }
            }
        } message: {
            Text(L10n.Block.unblockConfirmMsg)
        }
        .sheet(item: $selectedMessageForReactions) { message in
            ReactionDetailSheetView(chatId: chat.chatID, message: message)
        }
        .confirmationDialog(L10n.Chat.attachmentActionTitle, isPresented: $showingAttachmentActionSheet, titleVisibility: .visible) {
            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showingCameraPicker = true
                } else {
                    cameraUnavailableAlert = true
                }
            } label: {
                Text(L10n.Chat.takePhoto)
            }
            Button {
                showingPhotoPicker = true
            } label: {
                Text(L10n.Chat.chooseFromLibrary)
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .sheet(isPresented: $showingCameraPicker) {
            ImagePickerView(sourceType: .camera) { capturedImage in
                handleSendImages(images: [capturedImage])
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { newItems in
            guard !newItems.isEmpty else { return }
            loadAndSendSelectedPhotos(newItems)
        }
        .alert(L10n.Chat.cameraNotAvailable, isPresented: $cameraUnavailableAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        }
        .alert(L10n.Chat.uploadFailed, isPresented: $showingUploadErrorAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        }
        .onAppear {
            chatService.activeChatId = chat.chatID
            chatService.watchMessages(chatId: chat.chatID)
            chatService.watchReadReceipts(chatId: chat.chatID)
            
            if let lastMsg = currentMessages.last {
                chatService.markAsRead(
                    chatId: chat.chatID,
                    lastMessageId: lastMsg.id,
                    lastMessageDate: lastMsg.createdDate
                )
            }
        }
        .onDisappear {
            if let lastMsg = currentMessages.last {
                chatService.markAsRead(
                    chatId: chat.chatID,
                    lastMessageId: lastMsg.id,
                    lastMessageDate: lastMsg.createdDate
                )
            }
            if chatService.activeChatId == chat.chatID {
                chatService.activeChatId = nil
            }
        }
    }
    
    private func performSendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        
        chatService.createMessage(chatId: chat.chatID, text: text) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.messageText = ""
                    self.hasUnseenNewMessages = false
                case .failure(let error):
                    AppLogger.error("Failed to send message in chat \(self.chat.chatID): \(error.localizedDescription)", category: .chat)
                }
            }
        }
    }
    
    @State private var showingUploadErrorAlert: Bool = false
    
    private func handleSendImages(images: [UIImage]) {
        guard !images.isEmpty else { return }
        let currentText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSendingImages = true
        self.messageText = ""
        
        chatService.sendImageMessage(chatId: chat.chatID, images: images, text: currentText) { result in
            DispatchQueue.main.async {
                self.isSendingImages = false
                switch result {
                case .success:
                    self.hasUnseenNewMessages = false
                case .failure(let error):
                    AppLogger.error("Failed to send images: \(error.localizedDescription)", category: .chat)
                    self.showingUploadErrorAlert = true
                }
            }
        }
    }
    
    private func loadAndSendSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isSendingImages = true
        
        Task {
            var loadedImages: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    loadedImages.append(img)
                }
            }
            await MainActor.run {
                self.selectedPhotoItems = []
                if !loadedImages.isEmpty {
                    self.handleSendImages(images: loadedImages)
                } else {
                    self.isSendingImages = false
                }
            }
        }
    }
    
    private func isMessageRead(_ message: DecryptedMessage) -> Bool {
        chatService.isMessageRead(
            chatId: chat.chatID,
            messageDate: message.createdDate,
            senderId: message.senderID
        )
    }
    
    private func readCountFor(_ message: DecryptedMessage) -> Int {
        chatService.readCountForMessage(
            chatId: chat.chatID,
            messageDate: message.createdDate,
            senderId: message.senderID
        )
    }
}

// MARK: - Message Bubble View (相手アイコン・吹き出し & 長押しリアクションピッカー & バッジ)

struct MessageBubbleView: View {
    let message: DecryptedMessage
    let chatId: String
    let isFromMe: Bool
    var isGroup: Bool = false
    var isAllDetailsRevealed: Bool = false
    var globalDragOffset: CGFloat = 0
    var onShowReactionDetails: () -> Void = {}
    
    @ObservedObject private var chatService = ChatService.shared
    @State private var showActionMenu: Bool = false
    @State private var selectedViewerImage: UIImage? = nil
    
    private var isRead: Bool {
        chatService.isMessageRead(
            chatId: chatId,
            messageDate: message.createdDate,
            senderId: message.senderID
        )
    }
    
    private var readCount: Int {
        chatService.readCountForMessage(
            chatId: chatId,
            messageDate: message.createdDate,
            senderId: message.senderID
        )
    }
    
    var isInfoVisible: Bool {
        if !isFromMe {
            return isAllDetailsRevealed || globalDragOffset > 20
        }
        return false
    }
    
    var effectiveOffset: CGFloat {
        if !isFromMe {
            return isAllDetailsRevealed ? 10 : globalDragOffset
        }
        return 0
    }
    
    var currentMyReaction: FriendsReactionType? {
        chatService.userReactions["\(chatId)_\(message.id)"] ?? message.myReaction
    }
    
    var activeReactionCounts: [(type: FriendsReactionType, count: Int32)] {
        FriendsReactionType.allActiveTypes.compactMap { type in
            if let count = message.reactionCounts[type.key], count > 0 {
                return (type, count)
            }
            return nil
        }
    }
    
    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if !isFromMe {
                    // 相手のアイコン (アバター)
                    avatarView(name: message.senderName)
                        .padding(.top, 2)
                }
                
                HStack(alignment: .bottom, spacing: 6) {
                    if isFromMe {
                        Spacer(minLength: 24)
                        
                        // 自分のメッセージのメタデータ (左側: 上段に既読状態、下段に送信時刻)
                        VStack(alignment: .trailing, spacing: 2) {
                            Spacer()
                            
                            if isGroup {
                                if readCount > 0 {
                                    Text(L10n.Chat.readCount(readCount))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                if isRead {
                                    Text(L10n.Chat.readStatus)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(timeString(from: message.createdDate))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        // 吹き出し本文バブル (自分: 青色)
                        messageBubble(isMe: true)
                    } else {
                        // 吹き出し本文バブル (相手: グレー, 上部にユーザー名は常時非表示)
                        messageBubble(isMe: false)
                        
                        // 相手メッセージのメタデータ (右側: スワイプ時にユーザー名・時刻・鍵バージョン等を表示)
                        VStack(alignment: .leading, spacing: 2) {
                            Spacer()
                            
                            if isInfoVisible {
                                Text(message.senderName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                                
                                HStack(spacing: 4) {
                                    Text("\(timeString(from: message.createdDate)) • \(message.message.keyVersion)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.green)
                                }
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            } else {
                                Text(timeString(from: message.createdDate))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer(minLength: 24)
                    }
                }
            }
            .contentShape(Rectangle())
            .offset(x: effectiveOffset)
            
            // 長押しクイックアクションメニュー (メッセージ直下に表示)
            if showActionMenu {
                HStack {
                    if isFromMe {
                        Spacer(minLength: 24)
                        actionMenuCard
                    } else {
                        // 相手アバター分のスペースインデント (36 + 8)
                        Spacer().frame(width: 44)
                        actionMenuCard
                        Spacer(minLength: 24)
                    }
                }
                .transition(.scale(scale: 0.95, anchor: isFromMe ? .topTrailing : .topLeading).combined(with: .opacity))
                .zIndex(10)
            }
            
            // リアクション集計バッジ表示 (吹き出し下部)
            if !activeReactionCounts.isEmpty {
                HStack(spacing: 6) {
                    if isFromMe {
                        Spacer()
                    } else {
                        // 相手アバター分のスペースインデント (36 + 8)
                        Spacer().frame(width: 44)
                    }
                    
                    HStack(spacing: 4) {
                        ForEach(activeReactionCounts, id: \.type.id) { item in
                            Button {
                                onShowReactionDetails()
                            } label: {
                                HStack(spacing: 3) {
                                    Text(item.type.emoji)
                                        .font(.system(size: 13))
                                    Text("\(item.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(currentMyReaction == item.type ? .blue : .secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(currentMyReaction == item.type ? Color.blue.opacity(0.12) : Color(uiColor: .tertiarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(currentMyReaction == item.type ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    if !isFromMe {
                        Spacer()
                    }
                }
                .padding(.top, -2)
            }
        }
        .onTapGesture {
            if showActionMenu {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    showActionMenu = false
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isInfoVisible)
    }
    
    // MARK: - Subviews
    
    /// メッセージ長押し時に直下に表示するアクションメニューカード（絵文字7種 ＋ コピー）
    private var actionMenuCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 絵文字リアクション行: 👍 ❤️ 🆗 😊 🤣 😢 😱
            HStack(spacing: 6) {
                ForEach(FriendsReactionType.quickActionTypes) { type in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            showActionMenu = false
                        }
                        chatService.toggleReaction(chatId: chatId, messageId: message.id, reactionType: type)
                    } label: {
                        Text(type.emoji)
                            .font(.system(size: 22))
                            .padding(4)
                            .background(currentMyReaction == type ? Color.blue.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                            .scaleEffect(currentMyReaction == type ? 1.15 : 1.0)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                // ※「…」（その他の絵文字一覧展開）は今後の実装フェーズで提供予定
            }
            
            Divider()
                .padding(.vertical, 1)
            
            // コピー行
            Button {
                UIPasteboard.general.string = message.decryptedText
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    showActionMenu = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                    Text(L10n.Common.copy)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
    }
    
    private func avatarView(name: String) -> some View {
        let senderId = message.senderID
        let profile = chatService.userProfile(for: senderId)
        
        return UserAvatarView(
            userId: profile?.userID ?? senderId,
            displayName: name,
            avatarNonce: profile?.avatarNonce ?? "",
            avatarUpdatedAt: profile?.avatarUpdatedDate,
            size: 36
        )
    }

    private func messageBubble(isMe: Bool) -> some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
            if message.hasAttachments {
                MessageAttachmentsGridView(attachments: message.attachments) { tappedImg in
                    selectedViewerImage = tappedImg
                }
            }
            if !message.decryptedText.isEmpty {
                Text(message.decryptedText)
                    .font(.system(size: 15))
                    .foregroundColor(isMe ? .white : .primary)
                    .padding(.horizontal, message.hasAttachments ? 6 : 14)
                    .padding(.vertical, message.hasAttachments ? 4 : 9)
            }
        }
        .padding(.horizontal, message.hasAttachments && message.decryptedText.isEmpty ? 4 : (message.hasAttachments ? 4 : 0))
        .padding(.vertical, message.hasAttachments && message.decryptedText.isEmpty ? 4 : (message.hasAttachments ? 4 : 0))
        .background(isMe ? Color.blue : Color(uiColor: .secondarySystemBackground))
        .clipShape(BubbleShape(isFromMe: isMe))
        .onLongPressGesture(minimumDuration: 0.35) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                showActionMenu.toggle()
            }
        }
        .fullScreenCover(item: Binding<ViewerImageItem?>(
            get: { selectedViewerImage.map { ViewerImageItem(image: $0) } },
            set: { selectedViewerImage = $0?.image }
        )) { item in
            ImageViewerView(image: item.image)
        }
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Bubble Shape (LINE/iMessage 風の吹き出し角丸)

struct BubbleShape: Shape {
    let isFromMe: Bool
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [
                .topLeft,
                .topRight,
                isFromMe ? .bottomLeft : .bottomRight
            ],
            cornerRadii: CGSize(width: 16, height: 16)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Reaction Detail Sheet View (リアクション詳細モーダル)

struct ReactionDetailSheetView: View {
    let chatId: String
    let message: DecryptedMessage
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var chatService = ChatService.shared
    
    @State private var reactions: [FriendsMessageReaction] = []
    @State private var isLoading: Bool = true
    @State private var selectedTab: FriendsReactionType? = nil
    
    var filteredReactions: [FriendsMessageReaction] {
        guard let tab = selectedTab else { return reactions }
        return reactions.filter { $0.reactionType == tab }
    }
    
    var activeReactionTypesInMessage: [FriendsReactionType] {
        let types = Set(reactions.map { $0.reactionType })
        return FriendsReactionType.allActiveTypes.filter { types.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // リアクション種別セレクタータブ
                if !reactions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                selectedTab = nil
                            } label: {
                                HStack(spacing: 4) {
                                    Text(L10n.Reaction.allTab)
                                    Text("\(reactions.count)")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(selectedTab == nil ? Color.blue : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(selectedTab == nil ? .white : .primary)
                                .cornerRadius(18)
                            }
                            
                            ForEach(activeReactionTypesInMessage) { type in
                                let count = reactions.filter { $0.reactionType == type }.count
                                Button {
                                    selectedTab = type
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(type.emoji)
                                        Text("\(count)")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedTab == type ? Color.blue : Color(uiColor: .secondarySystemBackground))
                                    .foregroundColor(selectedTab == type ? .white : .primary)
                                    .cornerRadius(18)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider()
                }
                
                if isLoading {
                    Spacer()
                    ProgressView(L10n.Common.loading)
                    Spacer()
                } else if filteredReactions.isEmpty {
                    Spacer()
                    Text(L10n.Reaction.emptyList)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredReactions) { reaction in
                            HStack(spacing: 12) {
                                // アバター
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 38, height: 38)
                                    Text(reaction.userName.prefix(1).uppercased())
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(reaction.userName)
                                            .font(.system(size: 15, weight: .medium))
                                        if reaction.userID == chatService.currentUser?.userID || reaction.userID == chatService.currentUser?.uid {
                                            Text("(\(L10n.Reaction.you))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Text(reaction.createdDate, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(reaction.reactionType.emoji)
                                    .font(.system(size: 24))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L10n.Reaction.detailsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchDetails()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func fetchDetails() {
        chatService.fetchReactionDetails(chatId: chatId, messageId: message.id) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let items):
                    self.reactions = items
                case .failure:
                    break
                }
            }
        }
    }
}

// MARK: - Message Attachment Grid & Thumbnail Views

struct ViewerImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct MessageAttachmentsGridView: View {
    let attachments: [MessageAttachment]
    let onImageTapped: (UIImage) -> Void
    
    var body: some View {
        Group {
            if attachments.count == 1 {
                AttachmentSingleThumbnailView(
                    attachment: attachments[0],
                    size: CGSize(width: 220, height: 220),
                    onTap: onImageTapped
                )
            } else if attachments.count == 2 {
                HStack(spacing: 4) {
                    ForEach(attachments) { att in
                        AttachmentSingleThumbnailView(
                            attachment: att,
                            size: CGSize(width: 108, height: 108),
                            onTap: onImageTapped
                        )
                    }
                }
            } else {
                let columns = [
                    GridItem(.fixed(108), spacing: 4),
                    GridItem(.fixed(108), spacing: 4)
                ]
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(attachments) { att in
                        AttachmentSingleThumbnailView(
                            attachment: att,
                            size: CGSize(width: 108, height: 108),
                            onTap: onImageTapped
                        )
                    }
                }
            }
        }
    }
}

struct AttachmentSingleThumbnailView: View {
    let attachment: MessageAttachment
    let size: CGSize
    let onTap: (UIImage) -> Void
    
    @State private var loadedImage: UIImage? = nil
    @State private var isLoading: Bool = true
    
    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap(img)
                    }
            } else if isLoading {
                ZStack {
                    Color.gray.opacity(0.15)
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .frame(width: size.width, height: size.height)
                .cornerRadius(10)
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
                .frame(width: size.width, height: size.height)
                .cornerRadius(10)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        if let cached = AttachmentRepository.shared.getCachedImage(attachmentId: attachment.attachmentId) {
            self.loadedImage = cached
            self.isLoading = false
            return
        }
        
        AttachmentRepository.shared.fetchAttachmentImage(attachment: attachment) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if case .success(let img) = result {
                    self.loadedImage = img
                }
            }
        }
    }
}



