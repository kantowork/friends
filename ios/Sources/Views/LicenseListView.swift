import SwiftUI

// MARK: - LicenseListView (B06-a オープンソースライセンス一覧画面)
// i18n (L10n) 完全対応 / 検索機能付き

public struct LicenseListView: View {
    @State private var licenses: [LicenseItem] = []
    @State private var searchText = ""
    
    public init() {}
    
    private var filteredLicenses: [LicenseItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return licenses
        }
        return licenses.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    public var body: some View {
        List {
            if filteredLicenses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(L10n.AppInfo.licenseEmpty)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredLicenses) { item in
                    NavigationLink {
                        LicenseDetailView(license: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.body)
                                .bold()
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 8) {
                                Text("v\(item.version)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                    .cornerRadius(4)
                                
                                Text(item.id)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.AppInfo.licenseListTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L10n.AppInfo.licenseSearchPlaceholder)
        .onAppear {
            if licenses.isEmpty {
                licenses = LicenseLoader.shared.loadLicenses()
            }
        }
    }
}

// MARK: - LicenseDetailView (B06-a オープンソースライセンス詳細画面)

public struct LicenseDetailView: View {
    public let license: LicenseItem
    
    public init(license: LicenseItem) {
        self.license = license
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Card
                VStack(alignment: .leading, spacing: 8) {
                    Text(license.name)
                        .font(.title2)
                        .bold()
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text("Version: \(license.version)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let url = URL(string: license.url), !license.url.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                Text(L10n.AppInfo.licenseViewSource)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(14)
                
                // License Full Text Box
                VStack(alignment: .leading, spacing: 12) {
                    Text("LICENSE")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.secondary)
                    
                    Text(license.license)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(14)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
