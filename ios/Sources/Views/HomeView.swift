import SwiftUI

// MARK: - B01 HomeView (ホーム画面)
// クイックアクセス・お知らせを提供するホーム画面

public struct HomeView: View {
    @ObservedObject var chatService = ChatService.shared
    @ObservedObject var tenantManager = TenantManager.shared
    @State private var showingAddFriendSheet = false
    @State private var showingTenantSwitchSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Action Buttons (最上段・セカンダリボタン)
                    quickActionsSection
                    
                    // Notifications / Activity Section
                    notificationSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.Tab.home)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // ⚙️ 設定ボタン
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingAddFriendSheet) {
                AddFriendView()
            }
            .sheet(isPresented: $showingTenantSwitchSheet) {
                TenantSwitcherView()
            }
            .onAppear {
                tenantManager.refreshUnreadCounts()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Home.quickActionTitle)
                .font(.footnote)
                .bold()
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button {
                    showingAddFriendSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.headline)
                        Text(L10n.Home.quickActionAddFriend)
                            .font(.subheadline)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Home.notificationTitle)
                .font(.footnote)
                .bold()
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 16)
                
                Text(L10n.Home.notificationEmpty)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}
