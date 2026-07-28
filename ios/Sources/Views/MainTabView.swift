import SwiftUI

public struct MainTabView: View {
    @ObservedObject private var chatService = ChatService.shared
    @ObservedObject private var toastManager = ToastNotificationManager.shared
    @State private var selectedTab: Tab = .home
    
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
            
            FriendListView()
                .tabItem {
                    Label(L10n.Tab.friends, systemImage: "bubble.left.and.bubble.right.fill")
                }
                .badge(chatService.totalDmUnreadCount > 0 ? chatService.totalDmUnreadCount : 0)
                .tag(Tab.friends)
            
            GroupListView()
                .tabItem {
                    Label(L10n.Tab.groups, systemImage: "person.3.fill")
                }
                .badge(chatService.totalGroupUnreadCount > 0 ? chatService.totalGroupUnreadCount : 0)
                .tag(Tab.groups)
        }
        .tint(.blue)
        .sheet(item: $toastManager.navigationTargetChat) { chat in
            NavigationStack {
                ChatDetailView(chat: chat)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(L10n.Common.close) {
                                toastManager.navigationTargetChat = nil
                            }
                        }
                    }
            }
        }
    }
}

