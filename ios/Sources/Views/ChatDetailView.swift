import SwiftUI

struct ChatDetailView: View {
    let chat: FriendsChatUIModel
    @ObservedObject var chatService = ChatService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedMessageForReactions: DecryptedMessage? = nil
    
    // 全体スワイプによる詳細・ユーザー名の一括表示状態
    @State private var isAllDetailsRevealed: Bool = false
    @GestureState private var globalDragOffset: CGFloat = 0
    
    init(chat: FriendsChatUIModel) {
        self.chat = chat
    }
    
    var currentMessages: [DecryptedMessage] {
        chatService.messages[chat.chatID] ?? []
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Messages Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(currentMessages) { message in
                            MessageBubbleView(
                                message: message,
                                chatId: chat.chatID,
                                isFromMe: message.senderID == chatService.currentUser?.uid,
                                isRead: isMessageRead(message),
                                readCount: readCountFor(message),
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: currentMessages.count) { _ in
                    if let lastMsg = currentMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                        // Mark latest as read
                        chatService.markAsRead(
                            chatId: chat.chatID,
                            lastMessageId: lastMsg.id,
                            lastMessageDate: lastMsg.createdDate
                        )
                    }
                }
            }
            
            Divider()
            
            // Message Input Bar
            HStack(spacing: 10) {
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
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle(chat.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if chat.chatType == .group {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: GroupDetailView(chat: chat)) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .sheet(item: $selectedMessageForReactions) { message in
            ReactionDetailSheetView(chatId: chat.chatID, message: message)
        }
        .onAppear {
            chatService.activeChatId = chat.chatID
            chatService.listenToMessages(chatId: chat.chatID)
            chatService.listenToReadReceipts(chatId: chat.chatID)
            
            if let lastMsg = currentMessages.last {
                chatService.markAsRead(
                    chatId: chat.chatID,
                    lastMessageId: lastMsg.id,
                    lastMessageDate: lastMsg.createdDate
                )
            }
        }
        .onDisappear {
            if chatService.activeChatId == chat.chatID {
                chatService.activeChatId = nil
            }
        }
    }
    
    private func performSendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        chatService.sendMessage(chatId: chat.chatID, text: text) { result in
            DispatchQueue.main.async {
                if case .success = result {
                    self.messageText = ""
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
    var isRead: Bool = false
    var readCount: Int = 0
    var isGroup: Bool = false
    var isAllDetailsRevealed: Bool = false
    var globalDragOffset: CGFloat = 0
    var onShowReactionDetails: () -> Void = {}
    
    @ObservedObject private var chatService = ChatService.shared
    @State private var showReactionPicker: Bool = false
    
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
            // クイックリアクションピッカー (長押し時にふわっと表示)
            if showReactionPicker {
                HStack(spacing: 8) {
                    ForEach(FriendsReactionType.allActiveTypes) { type in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showReactionPicker = false
                            }
                            chatService.toggleReaction(chatId: chatId, messageId: message.id, reactionType: type)
                        } label: {
                            Text(type.emoji)
                                .font(.system(size: 24))
                                .padding(6)
                                .background(currentMyReaction == type ? Color.blue.opacity(0.2) : Color.clear)
                                .clipShape(Circle())
                                .scaleEffect(currentMyReaction == type ? 1.2 : 1.0)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 3)
                .transition(.scale.combined(with: .opacity))
                .zIndex(10)
            }
            
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
            if showReactionPicker {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    showReactionPicker = false
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isInfoVisible)
    }
    
    // MARK: - Subviews
    
    private func avatarView(name: String) -> some View {
        let senderId = message.senderID
        let senderFriend = chatService.friends.first { $0.uid == senderId || $0.userID == senderId }
        
        return UserAvatarView(
            userId: senderFriend?.userID ?? senderId,
            displayName: name,
            avatarNonce: senderFriend?.avatarNonce ?? "",
            avatarUpdatedAt: senderFriend?.avatarUpdatedDate,
            size: 36
        )
    }

    
    private func messageBubble(isMe: Bool) -> some View {
        Text(message.decryptedText)
            .font(.system(size: 15))
            .foregroundColor(isMe ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isMe ? Color.blue : Color(uiColor: .secondarySystemBackground))
            .clipShape(BubbleShape(isFromMe: isMe))
            .onLongPressGesture(minimumDuration: 0.35) {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showReactionPicker.toggle()
                }
            }
            .contextMenu {
                // コンテキストメニューからもリアクションや詳細閲覧が可能
                Menu {
                    ForEach(FriendsReactionType.allActiveTypes) { type in
                        Button {
                            chatService.toggleReaction(chatId: chatId, messageId: message.id, reactionType: type)
                        } label: {
                            Label("\(type.emoji) \(type.title)", systemImage: currentMyReaction == type ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(L10n.Reaction.detailsTitle, systemImage: "face.smiling")
                }
                
                Button {
                    onShowReactionDetails()
                } label: {
                    Label(L10n.Reaction.detailsTitle, systemImage: "person.2")
                }
                
                Button {
                    UIPasteboard.general.string = message.decryptedText
                } label: {
                    Label(L10n.Common.copy, systemImage: "doc.on.doc")
                }
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
                                        if reaction.userID == chatService.currentUser?.uid {
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
                case .failure(let err):
                    print("⚠️ Failed to load reaction details: \(err.localizedDescription)")
                }
            }
        }
    }
}


