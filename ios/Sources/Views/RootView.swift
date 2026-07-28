import SwiftUI

public struct RootView: View {
    @ObservedObject var chatService = ChatService.shared
    @ObservedObject var toastManager = ToastNotificationManager.shared
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch chatService.authStatus {
                case .unknown:
                    SplashView()
                        .transition(.opacity)
                    
                case .unauthenticated:
                    LoginView()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    
                case .authenticated:
                    MainTabView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.default, value: chatService.authStatus)
            
            // アプリ内トースト通知オーバーレイ (フォアグラウンド)
            if let toast = toastManager.currentToast {
                ToastBannerView(
                    toast: toast,
                    onTap: {
                        toastManager.handleToastTap(toast)
                    },
                    onDismiss: {
                        toastManager.dismiss()
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
                .zIndex(999)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastManager.currentToast)
    }
}

