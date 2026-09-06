import SwiftUI

public struct SettingsView: View {
    @ObservedObject var chatService = ChatService.shared
    @State private var showingEditProfile = false
    @State private var showingRecoveryPhrase = false
    @State private var showingSecurityResetAlert = false
    @State private var resetSuccessAlert = false
    @State private var showingSignOutAlert = false
    @State private var showingAppInfo = false
    
    public init() {}
    
    public var body: some View {
        List {
            // Profile Section
            Section {
                Button {
                    showingEditProfile = true
                } label: {
                    HStack(spacing: 16) {
                        if let user = chatService.currentUser {
                            UserAvatarView(
                                userId: user.userID,
                                displayName: user.displayName,
                                avatarNonce: user.avatarNonce,
                                avatarUpdatedAt: user.avatarUpdatedDate,
                                size: 56
                            )
                            .id("\(user.userID)_\(user.avatarNonce)_\(user.avatarUpdatedDate?.timeIntervalSince1970 ?? 0)")
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chatService.currentUser?.displayName ?? L10n.Settings.profileDefaultUser)
                                .font(.title3)
                                .bold()
                                .foregroundColor(.primary)
                            Text("@\(chatService.currentUser?.effectiveUsername ?? "-")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            
            // Security & Recovery Section
            Section(L10n.Settings.sectionSecurity) {
                Button {
                    showingRecoveryPhrase = true
                } label: {
                    HStack {
                        Label(L10n.Settings.recoveryTitle, systemImage: "key.fill")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(role: .destructive) {
                    showingSecurityResetAlert = true
                } label: {
                    Label(L10n.Settings.securityResetTitle, systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
            }
            
            // Account Sign Out Section
            Section {
                Button(role: .destructive) {
                    showingSignOutAlert = true
                } label: {
                    Label(L10n.Settings.logout, systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            
            // About Section
            Section {
                Button {
                    showingAppInfo = true
                } label: {
                    HStack {
                        Text(L10n.AppInfo.title)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
        }
        .sheet(isPresented: $showingRecoveryPhrase) {
            RecoveryPhraseSheetView()
        }
        .sheet(isPresented: $showingAppInfo) {
            AppInfoView()
        }
        .alert(L10n.Settings.securityResetConfirmTitle, isPresented: $showingSecurityResetAlert) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Settings.securityResetExecute, role: .destructive) {
                chatService.performSecurityReset { result in
                    DispatchQueue.main.async {
                        if case .success = result {
                            resetSuccessAlert = true
                        }
                    }
                }
            }
        } message: {
            Text(L10n.Settings.securityResetConfirmMsg)
        }
        .alert(L10n.Settings.securityResetSuccessTitle, isPresented: $resetSuccessAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(L10n.Settings.securityResetSuccessMsg)
        }
        .alert(L10n.Settings.logoutConfirmTitle, isPresented: $showingSignOutAlert) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Settings.logout, role: .destructive) {
                chatService.signOut()
            }
        } message: {
            Text(L10n.Settings.logoutConfirmMsg)
        }
    }
}

// MARK: - Recovery Phrase Sheet View

struct RecoveryPhraseSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var words: [String] = []
    @State private var isCopied = false
    @State private var showRegenerateAlert = false
    @State private var isRegenerating = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    Text(L10n.Settings.recoveryTitle)
                        .font(.title2)
                        .bold()
                    
                    Text(L10n.Settings.recoveryDesc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 16)
                
                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }
                
                if words.isEmpty || isRegenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(isRegenerating ? L10n.Common.loading : L10n.Common.loading)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(word)
                                    .font(.system(.body, design: .monospaced))
                                    .bold()
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Button {
                        copyWordsToClipboard()
                    } label: {
                        Label(isCopied ? L10n.Settings.recoveryCopied : L10n.Settings.recoveryCopyButton, systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .foregroundColor(isCopied ? .green : .blue)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .navigationTitle(L10n.Settings.recoveryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                    .disabled(isRegenerating)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showRegenerateAlert = true
                    } label: {
                        if isRegenerating {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .disabled(isRegenerating || words.isEmpty)
                    .accessibilityLabel(L10n.Settings.recoveryRegenerateBtn)
                }
            }
            .alert(L10n.Settings.recoveryRegenerateTitle, isPresented: $showRegenerateAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Settings.recoveryRegenerateAction, role: .destructive) {
                    executeRegenerate()
                }
            } message: {
                Text(L10n.Settings.recoveryRegeneratePrompt)
            }
            .onAppear {
                loadOrCreateRecoveryPhrase()
            }
        }
    }
    
    private func executeRegenerate() {
        isRegenerating = true
        errorMessage = nil
        ChatService.shared.regenerateRecoveryPhrase { result in
            DispatchQueue.main.async {
                self.isRegenerating = false
                switch result {
                case .success(let newWords):
                    self.words = newWords
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadOrCreateRecoveryPhrase() {
        guard let uid = ChatService.shared.currentUser?.uid else { return }
        if let savedWords = CryptoKeyManager.shared.getMnemonicPhrase(uid: uid), !savedWords.isEmpty {
            self.words = savedWords
            return
        }
        
        // Keychain にまだ未保存の場合、秘密鍵を取得して新規生成 & バックアップ
        if let privKey = CryptoKeyManager.shared.getPrivateKey(uid: uid) {
            ChatService.shared.backupPrivateKeyWithRecoveryPhrase(uid: uid, privateKey: privKey) { result in
                DispatchQueue.main.async {
                    if case .success(let generated) = result {
                        self.words = generated
                    }
                }
            }
        }
    }
    
    private func copyWordsToClipboard() {
        let phrase = words.joined(separator: " ")
        UIPasteboard.general.string = phrase
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
