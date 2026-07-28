import SwiftUI

public struct LoginView: View {
    @ObservedObject var chatService = ChatService.shared
    
    @State private var showingRecoverySheet = false
    @State private var showingTenantAddSheet = false
    @State private var showingEmailAuthSheet = false
    @State private var showingResetConfirmAlert = false
    @State private var isLoggingIn = false
    @State private var errorMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                // 1. App Icon & Branding
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(spacing: 12) {
                        Text(L10n.Auth.title)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(L10n.Auth.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 2. Tenant Selection Card & Action Buttons
                VStack(spacing: 16) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    
                    // Tenant Selector Card (タップでテナント変更)
                    Button {
                        showingTenantAddSheet = true
                    } label: {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chatService.currentTenant?.tenantName ?? PresetTenantConfig.tenantName)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text(chatService.currentTenant?.tenantCode ?? PresetTenantConfig.tenantCode)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 18, weight: .medium))
                                Text(L10n.Auth.tenantChange)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Button 1: 匿名でログイン
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
                        .frame(height: 52)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .disabled(isLoggingIn)
                    
                    // Button 2: メールアドレスでログイン
                    Button {
                        showingEmailAuthSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.body.weight(.semibold))
                            Text(L10n.Auth.emailBtn)
                                .font(.body)
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.clear)
                        .foregroundColor(.blue)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.blue.opacity(0.8), lineWidth: 1.5)
                        )
                    }
                    
                    // Button 3: 復活の呪文
                    Button {
                        showingRecoverySheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.subheadline)
                            Text(L10n.Auth.recoveryBtn)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                    
                    // Button 4: 端末データ・鍵の完全リセット (Keychainクリア)
                    Button(role: .destructive) {
                        showingResetConfirmAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash.circle.fill")
                                .font(.caption)
                            Text(L10n.Auth.resetDeviceBtn)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingRecoverySheet) {
                RecoveryLoginSheetView()
            }
            .sheet(isPresented: $showingTenantAddSheet) {
                TenantSelectionView()
            }
            .sheet(isPresented: $showingEmailAuthSheet) {
                EmailAuthSheetView()
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
    
    private func performAnonymousLogin() {
        isLoggingIn = true
        errorMessage = nil
        
        chatService.signInAnonymously(displayName: "ゲストユーザー") { result in
            DispatchQueue.main.async {
                isLoggingIn = false
                switch result {
                case .success:
                    print("✅ Logged in successfully!")
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Email Auth Sheet View

struct EmailAuthSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chatService = ChatService.shared
    
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("モード", selection: $isSignUp) {
                        Text(L10n.Auth.emailBtn).tag(false)
                        Text("新規登録").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("アカウント情報")) {
                    if isSignUp {
                        TextField(L10n.Auth.displayNamePlaceholder, text: $displayName)
                    }
                    
                    TextField("メールアドレス", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    SecureField("パスワード", text: $password)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(isSignUp ? "アカウント新規作成" : L10n.Auth.emailBtn)
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle(isSignUp ? "メールで新規登録" : L10n.Auth.emailBtn)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func submit() {
        isLoading = true
        errorMessage = nil
        
        if isSignUp {
            chatService.signUpWithEmail(email: email, password: password, displayName: displayName) { result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        dismiss()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            chatService.signInWithEmail(email: email, password: password) { result in
                DispatchQueue.main.async {
                    isLoading = false
                    switch result {
                    case .success:
                        dismiss()
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
                        Text("アカウントと鍵を復元")
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
            errorText = "12個の英単語を入力してください (現在 \(words.count) 単語)"
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
