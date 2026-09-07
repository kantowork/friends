import SwiftUI

public struct LoginView: View {
    @ObservedObject var chatService = ChatService.shared
    
    @State private var showingRecoverySheet = false
    @State private var showingTenantAddSheet = false
    @State private var showingResetConfirmAlert = false
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    
    @State private var isLoggingIn = false
    @State private var isLoggingInWithApple = false
    @State private var isLoggingInWithGoogle = false
    @State private var errorMessage: String? = nil
    
    // メール認証インライン展開用の状態
    @State private var isEmailAuthMode = false
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoadingEmailAuth = false
    
    private var isAnyLoading: Bool {
        isLoggingIn || isLoggingInWithApple || isLoggingInWithGoogle || isLoadingEmailAuth
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 1. App Icon & Branding Header
                    headerView
                    
                    // 2. Main Content Area
                    VStack(spacing: 12) {
                        // テナント選択カード
                        tenantSelectorCard
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        
                        // 認証操作エリア（初期ボタン群 または メールインライン入力フォーム）
                        if isEmailAuthMode {
                            emailInlineAuthView
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            mainAuthOptionsView
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // 利用規約・プライバシーポリシー
                        termsAndPrivacyNotice
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, isEmailAuthMode ? 6 : 12)
                    .padding(.bottom, 16)
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
        if isEmailAuthMode {
            // メールサインイン選択時: アイコンとFriendsを横並びに配置し上部スペースを圧縮
            HStack(spacing: 10) {
                Image("FriendsIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                
                Text(L10n.Auth.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEmailAuthMode = false
                        errorMessage = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        } else {
            // 初期状態: アイコン <改行> Friends を中央に縦並び配置
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
            .padding(.vertical, 10)
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
        VStack(spacing: 11) {
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
            .disabled(isAnyLoading)
            
            // または 仕切り線
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                Text(L10n.Auth.orDivider)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.vertical, 2)
            
            // サインインボタン群 (メール、Apple、Google)
            VStack(spacing: 10) {
                // メールでサインイン (上段)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEmailAuthMode = true
                        errorMessage = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                            .font(.body.weight(.semibold))
                        Text(L10n.Auth.emailSignInBtn)
                            .font(.body)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .disabled(isAnyLoading)
                
                // メールの左下にApple・右下にGoogle (下段)
                HStack(spacing: 8) {
                    // Apple (左下)
                    Button {
                        performAppleLogin()
                    } label: {
                        HStack(spacing: 6) {
                            if isLoggingInWithApple {
                                ProgressView()
                                    .tint(Color(uiColor: .systemBackground))
                            } else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            Text(L10n.Auth.appleBtn)
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.primary)
                        .foregroundColor(Color(uiColor: .systemBackground))
                        .cornerRadius(12)
                    }
                    .disabled(isAnyLoading)
                    
                    // Google (右下)
                    Button {
                        performGoogleLogin()
                    } label: {
                        HStack(spacing: 6) {
                            if isLoggingInWithGoogle {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            Text(L10n.Auth.googleBtn)
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .disabled(isAnyLoading)
                }
            }
            
            // 復活の呪文ログイン (1行)
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
            
            // 端末データ・鍵の完全リセット (1行)
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
            .padding(.top, 1)
        }
    }
    
    @ViewBuilder
    private var emailInlineAuthView: some View {
        VStack(spacing: 12) {
            // ログイン / 新規登録 セグメント
            Picker("", selection: $isSignUp) {
                Text(L10n.Auth.modeSignIn).tag(false)
                Text(L10n.Auth.modeSignUp).tag(true)
            }
            .pickerStyle(.segmented)
            
            // 入力フィールド群
            VStack(spacing: 10) {
                if isSignUp {
                    TextField(L10n.Auth.displayNamePlaceholder, text: $displayName)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }
                
                TextField(L10n.Auth.emailPlaceholder, text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                
                SecureField(L10n.Auth.passwordPlaceholder, text: $password)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            
            // 認証実行ボタン
            Button {
                performEmailAuth()
            } label: {
                HStack(spacing: 8) {
                    if isLoadingEmailAuth {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSignUp ? L10n.Auth.signUpAction : L10n.Auth.signInAction)
                        .font(.body)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(13)
            }
            .disabled(isLoadingEmailAuth || email.isEmpty || password.isEmpty || (isSignUp && displayName.isEmpty))
            
            // ほかのログイン方法に戻る
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isEmailAuthMode = false
                    errorMessage = nil
                }
            } label: {
                Text(L10n.Auth.backToOptions)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
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
        .padding(.top, 4)
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
    
    private func performAppleLogin() {
        isLoggingInWithApple = true
        errorMessage = nil
        
        chatService.signInWithApple { result in
            DispatchQueue.main.async {
                isLoggingInWithApple = false
                switch result {
                case .success:
                    break
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 {
                        // ユーザーによるキャンセル
                        return
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func performGoogleLogin() {
        isLoggingInWithGoogle = true
        errorMessage = nil
        
        chatService.signInWithGoogle { result in
            DispatchQueue.main.async {
                isLoggingInWithGoogle = false
                switch result {
                case .success:
                    break
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17058 {
                        // ユーザーによる Safari/Web 認証キャンセル
                        return
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func performEmailAuth() {
        isLoadingEmailAuth = true
        errorMessage = nil
        
        if isSignUp {
            chatService.signUpWithEmail(email: email, password: password, displayName: displayName) { result in
                DispatchQueue.main.async {
                    isLoadingEmailAuth = false
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            chatService.signInWithEmail(email: email, password: password) { result in
                DispatchQueue.main.async {
                    isLoadingEmailAuth = false
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
