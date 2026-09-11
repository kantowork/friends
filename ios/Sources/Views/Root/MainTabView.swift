import SwiftUI

public struct MainTabView: View {
    @ObservedObject private var directChatService = DirectChatService.shared
    @ObservedObject private var groupChatService = GroupChatService.shared
    @ObservedObject private var messageService = MessageService.shared
    @ObservedObject private var toastManager = ToastNotificationManager.shared
    @State private var selectedTab: Tab = .home
    
    @State private var friendNavigationPath = NavigationPath()
    @State private var groupNavigationPath = NavigationPath()
    
    public enum Tab {
        case home
        case friends
        case groups
    }
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(L10n.Tab.home, systemImage: "house.fill")
                }
                .tag(Tab.home)
            
            FriendListView(navigationPath: $friendNavigationPath)
                .tabItem {
                    Label(L10n.Tab.friends, systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(directChatService.totalDmUnreadCount > 0 ? directChatService.totalDmUnreadCount : 0)
                .tag(Tab.friends)
            
            GroupListView(navigationPath: $groupNavigationPath)
                .tabItem {
                    Label(L10n.Tab.groups, systemImage: "person.3.fill")
                }
                .badge(groupChatService.totalGroupUnreadCount > 0 ? groupChatService.totalGroupUnreadCount : 0)
                .tag(Tab.groups)
        }
        .tint(.appAccent)
        .onChange(of: toastManager.navigationTargetChat) { targetChat in
            guard let chat = targetChat else { return }
            let isGroup = chat.chatType == .group || chat.chatID.hasPrefix("gm_")
            
            if isGroup {
                selectedTab = .groups
                groupNavigationPath = NavigationPath([chat])
            } else {
                selectedTab = .friends
                friendNavigationPath = NavigationPath([chat])
            }
            
            toastManager.navigationTargetChat = nil
        }
    }
}

