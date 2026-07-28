import SwiftUI

public struct SettingsView: View {
    @ObservedObject var chatService = ChatService.shared
    @State private var showingEditProfile = false
    @State private var showingRecoveryPhrase = false
    @State private var showingSecurityResetAlert = false
    @State private var resetSuccessAlert = false
    @State private var showingSignOutAlert = false
    
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
            Section(L10n.Settings.sectionAbout) {
                HStack {
                    Text(L10n.Settings.aboutVersion)
                    Spacer()
                    Text("1.0.0 (Build 1)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(L10n.Settings.aboutEncryption)
                    Spacer()
                    Text("AES-256-GCM / ECDH")
                        .foregroundColor(.secondary)
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
                resetSuccessAlert = true
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
    
    private let words = [
        "apple", "river", "mountain", "cloud", "ocean", "forest",
        "stone", "silent", "breeze", "crystal", "silver", "echo"
    ]
    
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
                
                Spacer()
            }
            .navigationTitle(L10n.Settings.recoveryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.ok) {
                        dismiss()
                    }
                }
            }
        }
    }
}
