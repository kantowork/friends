import SwiftUI

public struct LoginView: View {
    @ObservedObject var authService = AuthService.shared
    
    @State private var showingRecoverySheet = false
    @State private var showingTenantAddSheet = false
    @State private var showingResetConfirmAlert = false
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    
    @State private var displayName: String = ""
    @FocusState private var isDisplayNameFocused: Bool
    
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
                        
                        // 表示名入力カード
                        displayNameInputCard
                        
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
                    authService.resetDeviceAndKeychain()
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
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
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
                    Text(authService.currentTenant?.tenantName ?? PresetTenantConfig.tenantName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(authService.currentTenant?.tenantCode ?? PresetTenantConfig.tenantCode)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.subheadline.weight(.medium))
                    Text(L10n.Auth.tenantChange)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
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
    private var displayNameInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Auth.displayNameLabel)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.body)
                    .foregroundColor(isDisplayNameFocused ? .appAccent : .secondary)
                
                TextField(L10n.Auth.displayNamePlaceholder, text: $displayName)
                    .font(.body)
                    .focused($isDisplayNameFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit {
                        if !isLoggingIn {
                            performAnonymousLogin()
                        }
                    }
                
                if !displayName.isEmpty {
                    Button {
                        displayName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDisplayNameFocused ? Color.appAccent : Color.primary.opacity(0.1), lineWidth: isDisplayNameFocused ? 1.5 : 1)
            )
        }
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
                .frame(minHeight: 50)
                .padding(.vertical, 4)
                .background(Color.appAccent)
                .foregroundColor(.white)
                .cornerRadius(13)
            }
            .disabled(isLoggingIn)
            
            // ふっかつのじゅもん
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
            
            // この端末から鍵を完全に消す
            Button(role: .destructive) {
                showingResetConfirmAlert = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash.circle.fill")
                        .font(.caption)
                    Text(L10n.Auth.resetDeviceBtn)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
    }
    
    @ViewBuilder
    private var termsAndPrivacyNotice: some View {
        VStack(spacing: 6) {
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
                        .foregroundColor(.appAccent)
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
                        .foregroundColor(.appAccent)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.small)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    // MARK: - Actions
    
    private func performAnonymousLogin() {
        isLoggingIn = true
        errorMessage = nil
        isDisplayNameFocused = false
        
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameToUse = trimmed.isEmpty ? L10n.Common.guestUser : trimmed
        
        authService.signInAnonymously(displayName: nameToUse) { result in
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
    @ObservedObject var authService = AuthService.shared
    @State private var phraseInput: String = ""
    @State private var isRestoring = false
    @State private var errorText: String? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "key.viewfinder")
                            .font(.system(.largeTitle))
                            .foregroundColor(.secondary)
                        
                        Text(L10n.Settings.recoveryDesc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $phraseInput)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                            .frame(minHeight: 120)
                        
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
                                .font(.body.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .padding(.vertical, 4)
                        .background(phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.appAccent.opacity(0.5) : Color.appAccent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .disabled(phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRestoring)
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
        
        authService.restoreWithRecoveryPhrase(words: words) { result in
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
