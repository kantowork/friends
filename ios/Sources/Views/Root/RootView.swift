import SwiftUI

public struct RootView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject var toastManager = ToastNotificationManager.shared
    @ObservedObject var notificationManager = NotificationManager.shared
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch authService.authStatus {
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
            .animation(.default, value: authService.authStatus)
            
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
        .sheet(isPresented: $notificationManager.shouldShowPermissionPrompt) {
            NotificationPermissionSheet()
        }
        .onAppear {
            if authService.authStatus == .authenticated {
                notificationManager.evaluatePermissionPromptNeed()
                notificationManager.syncCurrentDevice()
            }
        }
        .onChange(of: authService.authStatus) { newStatus in
            if newStatus == .authenticated {
                notificationManager.evaluatePermissionPromptNeed()
                notificationManager.syncCurrentDevice()
            }
        }
    }
}


