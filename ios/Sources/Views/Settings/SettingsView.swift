import SwiftUI

public struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    @AppStorage(ChatFontSize.defaultKey) private var chatFontSizeRaw: String = ChatFontSize.default.rawValue
    @State private var showingEditProfile = false
    @State private var showingRecoveryPhrase = false
    @State private var showingSecurityResetAlert = false
    @State private var resetSuccessAlert = false
    @State private var showingSignOutAlert = false
    @State private var showingAccountDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var accountDeleteError: String? = nil
    @State private var showingDeleteErrorAlert = false
    
    public init() {}
    
    public var body: some View {
        List {
            // Profile Section
            Section {
                Button {
                    showingEditProfile = true
                } label: {
                    HStack(spacing: 16) {
                        if let user = authService.currentUser {
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
                                .fill(Color.appAccent.opacity(0.15))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.title2)
                                        .foregroundColor(.appAccent)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authService.currentUser?.displayName ?? L10n.Settings.profileDefaultUser)
                                .font(.title3)
                                .bold()
                                .foregroundColor(.primary)
                            Text("@\(authService.currentUser?.effectiveUsername ?? "-")")
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

            
            // Security Section (ブロックしたともだち -> ふっかつのじゅもん -> セキュリティリセット)
            Section(L10n.Settings.sectionSecurity) {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    Label(L10n.Block.listTitle, systemImage: "shield.slash.fill")
                        .foregroundColor(.primary)
                }
                
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
            
            // Display Section (メッセージ文字サイズ)
            Section(L10n.Settings.sectionDisplay) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.Settings.chatFontSizeLabel)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Picker(L10n.Settings.chatFontSizeLabel, selection: $chatFontSizeRaw) {
                        ForEach(ChatFontSize.allCases, id: \.rawValue) { size in
                            Text(size.localizedLabel).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
            
            // About Section
            Section {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Text(L10n.AppInfo.title)
                        .foregroundColor(.primary)
                }
            }
            
            // Account & Destructive Actions Section
            Section {
                Button(role: .destructive) {
                    showingSignOutAlert = true
                } label: {
                    Label(L10n.Settings.logout, systemImage: "rectangle.portrait.and.arrow.right")
                }
                
                Button(role: .destructive) {
                    showingAccountDeleteAlert = true
                } label: {
                    Label(L10n.Settings.accountDelete, systemImage: "person.crop.circle.badge.xmark")
                        .foregroundColor(.red)
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
        .alert(L10n.Settings.securityResetConfirmTitle, isPresented: $showingSecurityResetAlert) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Settings.securityResetExecute, role: .destructive) {
                authService.performSecurityReset { result in
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
                authService.signOut()
            }
        } message: {
            Text(L10n.Settings.logoutConfirmMsg)
        }
        .alert(L10n.Settings.accountDeleteConfirmTitle, isPresented: $showingAccountDeleteAlert) {
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Settings.accountDeleteExecute, role: .destructive) {
                isDeletingAccount = true
                authService.deleteAccount { result in
                    DispatchQueue.main.async {
                        isDeletingAccount = false
                        if case .failure(let error) = result {
                            accountDeleteError = error.localizedDescription
                            showingDeleteErrorAlert = true
                        }
                    }
                }
            }
        } message: {
            Text(L10n.Settings.accountDeleteConfirmMsg)
        }
        .alert(L10n.Common.error, isPresented: $showingDeleteErrorAlert) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(accountDeleteError ?? L10n.Common.error)
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
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text(L10n.Settings.recoveryDesc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
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
                        .frame(minHeight: 200)
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
                                .foregroundColor(isCopied ? .green : .appAccent)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
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
                                .foregroundColor(.secondary)
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
        AuthService.shared.regenerateRecoveryPhrase { result in
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
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        if let savedWords = CryptoKeyManager.shared.getMnemonicPhrase(uid: uid), !savedWords.isEmpty {
            self.words = savedWords
            return
        }
        
        // Keychain にまだ未保存の場合、秘密鍵を取得して新規生成 & バックアップ
        if let privKey = CryptoKeyManager.shared.getPrivateKey(uid: uid) {
            AuthService.shared.backupPrivateKeyWithRecoveryPhrase(uid: uid, privateKey: privKey) { result in
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
