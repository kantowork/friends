import SwiftUI

public struct LoginView: View {
    @ObservedObject var chatService = ChatService.shared
    
    @State private var showingRecoverySheet = false
    @State private var showingTenantAddSheet = false
    @State private var showingResetConfirmAlert = false
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    
    @State private var isLoggingIn = false
    @State private var errorMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 1. App Icon & Branding Header
                    headerView
                    
                    // 2. Main Content Area
                    VStack(spacing: 16) {
                        // テナント選択カード
                        tenantSelectorCard
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        
                        // 認証操作エリア
                        mainAuthOptionsView
                        
                        // 利用規約・プライバシーポリシー
                        termsAndPrivacyNotice
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingRecoverySheet) {
                RecoveryLoginSheetView()
            }
            .sheet(isPresented: $showingTenantAddSheet) {
                TenantSelectionView()
            }
            .sheet(isPresented: $showingTerms) {
                TermsOfServiceView(isPresentedInModal: true)
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacyPolicyView(isPresentedInModal: true)
            }
            .alert(L10n.Auth.resetDeviceConfirmTitle, isPresented: $showingResetConfirmAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.delete, role: .destructive) {
                    chatService.resetDeviceAndKeychain()
                }
            } message: {
                Text(L10n.Auth.resetDeviceConfirmMsg)
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 12) {
            Image("FriendsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            
            Text(L10n.Auth.title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.top, 60)
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    private var tenantSelectorCard: some View {
        Button {
            showingTenantAddSheet = true
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chatService.currentTenant?.tenantName ?? PresetTenantConfig.tenantName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(chatService.currentTenant?.tenantCode ?? PresetTenantConfig.tenantCode)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 16, weight: .medium))
                    Text(L10n.Auth.tenantChange)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var mainAuthOptionsView: some View {
        VStack(spacing: 14) {
            // 匿名ログインボタン
            Button {
                performAnonymousLogin()
            } label: {
                HStack(spacing: 8) {
                    if isLoggingIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.body.weight(.bold))
                    }
                    Text(L10n.Auth.guestBtn)
                        .font(.body)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(13)
            }
            .disabled(isLoggingIn)
            
            // 復活の呪文ログイン
            Button {
                showingRecoverySheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.caption)
                    Text(L10n.Auth.recoveryBtn)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            
            // 端末データ・鍵の完全リセット
            Button(role: .destructive) {
                showingResetConfirmAlert = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash.circle.fill")
                        .font(.caption2)
                    Text(L10n.Auth.resetDeviceBtn)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.top, 2)
        }
    }
    
    @ViewBuilder
    private var termsAndPrivacyNotice: some View {
        VStack(spacing: 4) {
            Text(L10n.Legal.termsAgreeNotice)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 8) {
                Button {
                    showingTerms = true
                } label: {
                    Text(L10n.Legal.termsTitle)
                        .font(.system(size: 11, weight: .medium))
                        .underline()
                        .foregroundColor(.blue)
                }
                
                Text("•")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Button {
                    showingPrivacy = true
                } label: {
                    Text(L10n.Legal.privacyTitle)
                        .font(.system(size: 11, weight: .medium))
                        .underline()
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    // MARK: - Actions
    
    private func performAnonymousLogin() {
        isLoggingIn = true
        errorMessage = nil
        
        chatService.signInAnonymously(displayName: "ゲストユーザー") { result in
            DispatchQueue.main.async {
                isLoggingIn = false
                switch result {
                case .success:
                    break
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Recovery Login Sheet View

struct RecoveryLoginSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chatService = ChatService.shared
    @State private var phraseInput: String = ""
    @State private var isRestoring = false
    @State private var errorText: String? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "key.viewfinder")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    Text(L10n.Settings.recoveryTitle)
                        .font(.title2)
                        .bold()
                    
                    Text(L10n.Settings.recoveryDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 16)
                
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $phraseInput)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .frame(height: 120)
                    
                    if let error = errorText {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                
                Button {
                    restoreAccount()
                } label: {
                    HStack {
                        if isRestoring {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 8)
                        }
                        Text(L10n.Auth.recoveryRestoreButton)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.blue.opacity(0.5) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .disabled(phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRestoring)
                
                Spacer()
            }
            .navigationTitle(L10n.Settings.recoveryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func restoreAccount() {
        let words = phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 12 else {
            errorText = L10n.Auth.recoveryWordCountError(count: words.count)
            return
        }
        
        isRestoring = true
        errorText = nil
        
        chatService.restoreWithRecoveryPhrase(words: words) { result in
            DispatchQueue.main.async {
                isRestoring = false
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }
}
