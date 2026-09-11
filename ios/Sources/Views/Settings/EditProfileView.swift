import SwiftUI
import PhotosUI

// MARK: - E02 EditProfileView (プロフィール編集画面)
// i18n (L10n) 完全対応
// 表示名およびアバター画像をテナントマスターキー (MK_T) で AES-256-GCM 暗号化して Firestore に保存

public struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authService = AuthService.shared
    @ObservedObject var directChatService = DirectChatService.shared
    
    @State private var displayNameText: String = ""
    @State private var usernameText: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var previewAvatarImage: UIImage? = nil
    @State private var isAvatarRemoved: Bool = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingAvatarActionSheet = false
    @State private var showingPresetSheet = false
    @State private var showingUsernameConfirmAlert = false
    
    @FocusState private var isUsernameFocused: Bool
    
    private var isUsernameTooShort: Bool {
        let raw = usernameText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        return !raw.isEmpty && raw.count < 3
    }
    
    private var isUsernameTooLong: Bool {
        let raw = usernameText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        return raw.count > 20
    }
    
    private var isSaveDisabled: Bool {
        if isSaving { return true }
        let trimmedName = displayNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUsername = usernameText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()
        if trimmedName.isEmpty || rawUsername.isEmpty || isUsernameTooShort || isUsernameTooLong { return true }
        
        let hasNameChanged = trimmedName != (authService.currentUser?.displayName ?? "")
        let hasUsernameChanged = rawUsername != (authService.currentUser?.effectiveUsername.lowercased() ?? "")
        let hasAvatarChanged = (previewAvatarImage != nil) || isAvatarRemoved
        
        return !hasNameChanged && !hasUsernameChanged && !hasAvatarChanged
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: プロフィール情報 (アバター + アカウント、名前、ID)
                Section {
                    // 1. アバターアイコン & アカウント (username)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 16) {
                            // 左: アバターサークル (64x64 固定、縮小・移動不可)
                            avatarBadgeView
                                .fixedSize()
                                .layoutPriority(1)
                            
                            // 右側: @xxxxxx アカウント入力 (フォントサイズ大・文字数増大時は文字の途中で自然に改行)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("@")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                TextField(L10n.Settings.profileUsernamePlaceholder, text: $usernameText, axis: .vertical)
                                    .font(.system(.body, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.asciiCapable)
                                    .lineLimit(1...5)
                                    .focused($isUsernameFocused)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isUsernameFocused = true
                            }
                        }
                        
                        // 文字数制限の警告表示
                        if isUsernameTooLong {
                            Text(L10n.Settings.profileUsernameTooLong)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 80)
                                .transition(.opacity)
                        } else if isUsernameTooShort {
                            Text(L10n.Settings.profileUsernameTooShort)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 80)
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // 2. 名前 (displayName)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.Settings.profileDisplayName)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        TextField(L10n.Settings.editProfilePlaceholder, text: $displayNameText, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1...4)
                            .autocorrectionDisabled()
                    }
                    
                    // 3. ID (userId)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.Settings.profileUserId)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        Text(breakableText(authService.currentUser?.userID ?? "-"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(L10n.Settings.sectionProfile)
                }
                
                // Section 2: テナント情報 (コード・テナント名・ID)
                Section(L10n.Settings.sectionTenant) {
                    // 1. コード (tenantCode)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.Settings.tenantCode)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        Text(breakableText(authService.currentTenant?.tenantCode ?? "-"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // 2. テナント名 (tenantName)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.Settings.tenantName)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        Text(authService.currentTenant?.tenantName ?? L10n.Settings.tenantUnconnected)
                            .font(.system(.body))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    // 3. ID (tenantId)
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.Settings.tenantId)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        Text(breakableText(authService.currentTenant?.tenantID ?? "-"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(L10n.Settings.editProfileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSaveTapped()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(isSaveDisabled)
                }
            }
            .alert(L10n.Settings.profileUsernameConfirmTitle, isPresented: $showingUsernameConfirmAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Settings.profileUsernameConfirmButton, role: .destructive) {
                    executeSaveProfile()
                }
            } message: {
                Text(L10n.Settings.profileUsernameConfirmMsg)
            }
            .onAppear {
                displayNameText = authService.currentUser?.displayName ?? ""
                usernameText = authService.currentUser?.effectiveUsername ?? ""
            }
            .confirmationDialog(L10n.Settings.avatarChange, isPresented: $showingAvatarActionSheet, titleVisibility: .visible) {
                Button(L10n.Settings.avatarChoosePhoto) {
                    // PhotosPicker トリガー
                    triggerPhotoPicker()
                }
                Button(L10n.Settings.avatarPresetTitle) {
                    showingPresetSheet = true
                }
                if authService.currentUser?.hasAvatarUpdatedAt == true || previewAvatarImage != nil {
                    Button(L10n.Settings.avatarRemove, role: .destructive) {
                        previewAvatarImage = nil
                        isAvatarRemoved = true
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            self.previewAvatarImage = uiImage
                            self.isAvatarRemoved = false
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPresetSheet) {
                PresetAvatarPickerSheet { presetImage in
                    self.previewAvatarImage = presetImage
                    self.isAvatarRemoved = false
                }
            }
            .onChange(of: usernameText) { newValue in
                if newValue.contains("@") {
                    usernameText = newValue.replacingOccurrences(of: "@", with: "")
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var avatarBadgeView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let preview = previewAvatarImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1.5))
            } else if isAvatarRemoved {
                // 削除プレビュー時
                Circle()
                    .fill(LinearGradient(colors: [Color.appAccent.opacity(0.8), Color.indigo.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(initialLetter(displayNameText))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
            } else if let user = authService.currentUser {
                UserAvatarView(
                    userId: user.userID,
                    displayName: user.displayName,
                    avatarNonce: user.avatarNonce,
                    avatarUpdatedAt: user.avatarUpdatedDate,
                    size: 64
                )
            }
            
            // 編集バッジ
            Circle()
                .fill(Color.appAccent)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
        .frame(width: 64, height: 64)
        .contentShape(Circle())
        .onTapGesture {
            showingAvatarActionSheet = true
        }
    }
    
    @State private var showingPhotoPicker = false
    
    private func triggerPhotoPicker() {
        showingPhotoPicker = true
    }
    
    private func initialLetter(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }
    
    private func breakableText(_ text: String) -> String {
        text.map { String($0) }.joined(separator: "\u{200B}")
    }
    
    private func onSaveTapped() {
        let rawUsername = usernameText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()
        
        if rawUsername.count < 3 {
            errorMessage = L10n.Settings.profileUsernameTooShort
            return
        }
        
        if rawUsername.count > 20 {
            errorMessage = L10n.Settings.profileUsernameTooLong
            return
        }
        
        // username バリデーション (3〜20文字、英数字とアンダースコア)
        let usernameRegex = "^[a-zA-Z0-9_]{3,20}$"
        if rawUsername.range(of: usernameRegex, options: .regularExpression) == nil {
            errorMessage = L10n.Settings.profileUsernameInvalidFormat
            return
        }
        
        let currentEffective = authService.currentUser?.effectiveUsername.lowercased() ?? ""
        if rawUsername != currentEffective {
            // ユーザー名が変更される場合は警告・確認ダイアログを表示
            showingUsernameConfirmAlert = true
        } else {
            executeSaveProfile()
        }
    }
    
    private func executeSaveProfile() {
        isSaving = true
        errorMessage = nil
        
        let trimmedName = displayNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUsername = usernameText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()
        let currentEffective = authService.currentUser?.effectiveUsername.lowercased() ?? ""
        
        // 1. ユーザー名 (username) の更新（変更がある場合は最優先で直列実行）
        if rawUsername != currentEffective {
            directChatService.updateUsername(newUsername: rawUsername) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        self.isSaving = false
                        self.errorMessage = error.localizedDescription
                        return
                    case .success:
                        self.proceedSaveOtherProfileFields(trimmedName: trimmedName)
                    }
                }
            }
        } else {
            proceedSaveOtherProfileFields(trimmedName: trimmedName)
        }
    }
    
    private func proceedSaveOtherProfileFields(trimmedName: String) {
        let group = DispatchGroup()
        var operationError: Error?
        
        // 2. 表示名の更新（変更がある場合）
        if trimmedName != authService.currentUser?.displayName {
            group.enter()
            authService.patchDisplayName(newName: trimmedName) { result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        operationError = error
                    }
                    group.leave()
                }
            }
        }
        
        // 3. アバター画像の更新または削除
        if let newImage = previewAvatarImage {
            group.enter()
            authService.uploadAvatar(image: newImage) { result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        operationError = error
                    }
                    group.leave()
                }
            }
        } else if isAvatarRemoved {
            group.enter()
            authService.deleteAvatar { result in
                DispatchQueue.main.async {
                    if case .failure(let error) = result {
                        operationError = error
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            self.isSaving = false
            if let error = operationError {
                self.errorMessage = error.localizedDescription
            } else {
                self.directChatService.listFriendsProfiles(force: true) {
                    // 同期完了
                }
                self.dismiss()
            }
        }
    }
}

// MARK: - PresetAvatarPickerSheet (プリセットアイコン選択シート)

struct PresetAvatarPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (UIImage) -> Void
    
    let presets: [PresetAvatar] = [
        PresetAvatar(symbol: "face.smiling.inverse", bgColors: [.orange, .yellow]),
        PresetAvatar(symbol: "sparkles", bgColors: [.purple, .blue]),
        PresetAvatar(symbol: "star.fill", bgColors: [.yellow, .orange]),
        PresetAvatar(symbol: "heart.fill", bgColors: [.pink, .red]),
        PresetAvatar(symbol: "bolt.fill", bgColors: [.cyan, .blue]),
        PresetAvatar(symbol: "leaf.fill", bgColors: [.green, .mint]),
        PresetAvatar(symbol: "flame.fill", bgColors: [.red, .orange]),
        PresetAvatar(symbol: "moon.stars.fill", bgColors: [.indigo, .purple]),
        PresetAvatar(symbol: "sun.max.fill", bgColors: [.orange, .yellow])
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 20)], spacing: 20) {
                    ForEach(presets) { preset in
                        Button {
                            if let image = renderPresetToImage(preset: preset) {
                                onSelect(image)
                                dismiss()
                            }
                        } label: {
                            Circle()
                                .fill(LinearGradient(colors: preset.bgColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 76, height: 76)
                                .overlay(
                                    Image(systemName: preset.symbol)
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: preset.bgColors.first?.opacity(0.3) ?? .clear, radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle(L10n.Settings.avatarPresetTitle)
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
    
    private func renderPresetToImage(preset: PresetAvatar) -> UIImage? {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Background Circle with Gradient
            let path = UIBezierPath(ovalIn: rect)
            path.addClip()
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let cgColors = preset.bgColors.map { UIColor($0).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            
            // Symbol
            let config = UIImage.SymbolConfiguration(pointSize: 110, weight: .bold)
            if let symbolImg = UIImage(systemName: preset.symbol, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                let symbolRect = CGRect(
                    x: (size.width - symbolImg.size.width) / 2,
                    y: (size.height - symbolImg.size.height) / 2,
                    width: symbolImg.size.width,
                    height: symbolImg.size.height
                )
                symbolImg.draw(in: symbolRect)
            }
        }
    }
}

struct PresetAvatar: Identifiable {
    let id = UUID()
    let symbol: String
    let bgColors: [Color]
}

