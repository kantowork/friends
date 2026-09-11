import SwiftUI

// MARK: - B03m TenantSwitcherView (テナント切り替えシート)
// 複数テナントの保持・切り替え・新規追加および各テナントの未読バッジ表示を提供します。

struct TenantSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tenantManager = TenantManager.shared
    @ObservedObject private var authService = AuthService.shared
    
    @State private var showingAddTenantSheet = false
    @State private var tenantToDelete: StoredTenant? = nil
    @State private var isSwitching = false
    @State private var errorMessage: String? = nil
    
    init() {}
    
    /// 現在のアクティブテナントを先頭（一番上）に並べたテナント一覧
    private var sortedTenants: [StoredTenant] {
        let activeId = tenantManager.activeTenantId
        var list = tenantManager.registeredTenants
        if let activeIndex = list.firstIndex(where: { $0.tenantID == activeId }) {
            let active = list.remove(at: activeIndex)
            list.insert(active, at: 0)
        }
        return list
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Section 1: テナント一覧（現在アクティブなテナントを一番上に表示）
                Section(header: Text(L10n.Tenant.switchListHeader)) {
                    ForEach(sortedTenants) { tenant in
                        let isCurrent = tenant.tenantID == tenantManager.activeTenantId
                        tenantRow(tenant: tenant, isCurrent: isCurrent)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isCurrent && !isSwitching {
                                    switchTo(tenant: tenant)
                                }
                            }
                    }
                    .onDelete(perform: deleteTenants)
                }
                
                // Section 2: 別のテナントを追加
                Section {
                    Button {
                        showingAddTenantSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.appAccent)
                            
                            Text(L10n.Tenant.switchAddBtn)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.appAccent)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(L10n.Tenant.switchTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddTenantSheet) {
                TenantSelectionView()
            }
            .alert(L10n.Tenant.switchLeaveConfirmTitle, isPresented: Binding<Bool>(
                get: { tenantToDelete != nil },
                set: { if !$0 { tenantToDelete = nil } }
            )) {
                Button(L10n.Common.cancel, role: .cancel) {
                    tenantToDelete = nil
                }
                Button(L10n.Tenant.switchLeave, role: .destructive) {
                    if let target = tenantToDelete {
                        tenantManager.removeTenant(tenantId: target.tenantID)
                        tenantToDelete = nil
                    }
                }
            } message: {
                if let target = tenantToDelete {
                    Text(L10n.Tenant.switchLeaveConfirmMsg(name: target.tenantName))
                }
            }
            .overlay {
                if isSwitching {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView()
                            .tint(.white)
                            .padding(20)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    // MARK: - Row Subview
    
    private func tenantRow(tenant: StoredTenant, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            // アイコン
            Circle()
                .fill(isCurrent ? Color.appAccent.opacity(0.15) : Color.gray.opacity(0.15))
                .frame(width: 40, height: 40)
                .fixedSize()
                .overlay(
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isCurrent ? .appAccent : .secondary)
                )
            
            // テナント名 & コード
            VStack(alignment: .leading, spacing: 2) {
                Text(tenant.tenantName.isEmpty ? L10n.Tenant.defaultNameFormat(tenant.tenantCode) : tenant.tenantName)
                    .font(.body)
                    .fontWeight(isCurrent ? .bold : .medium)
                    .foregroundColor(.primary)
                
                Text("@\(tenant.tenantCode)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 現在のテナント: 「利用中」識別バッジとチェックマークで明示
            if isCurrent {
                HStack(spacing: 6) {
                    Text(L10n.Tenant.switchCurrentBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.appAccent.opacity(0.35), lineWidth: 1)
                        )
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.appAccent)
                        .font(.system(size: 18))
                }
            } else {
                // 他テナント: 未読バッジ（0より大きい場合のみ表示）
                let unread = tenantManager.tenantUnreadCounts[tenant.tenantID] ?? 0
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func switchTo(tenant: StoredTenant) {
        isSwitching = true
        errorMessage = nil
        
        authService.switchToTenant(tenantId: tenant.tenantID) { result in
            DispatchQueue.main.async {
                self.isSwitching = false
                switch result {
                case .success:
                    self.dismiss()
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                }
            }
        }
    }
    
    private func deleteTenants(at offsets: IndexSet) {
        for index in offsets {
            let target = sortedTenants[index]
            // デフォルトテナントまたは利用中テナントはスワイプ削除不可
            if target.tenantID == PresetTenantConfig.tenantId || target.isDefaultTenant || target.tenantID == tenantManager.activeTenantId {
                continue
            }
            tenantToDelete = target
        }
    }
}
