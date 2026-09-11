import SwiftUI

public struct SplashView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Gradient Background (Matching App Icon colors: #00C7B1 -> #00A2E8 -> #0066CC)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0x00 / 255.0, green: 0xC7 / 255.0, blue: 0xB1 / 255.0), location: 0.0),
                    .init(color: Color(red: 0x00 / 255.0, green: 0xA2 / 255.0, blue: 0xE8 / 255.0), location: 0.4),
                    .init(color: Color(red: 0x00 / 255.0, green: 0x66 / 255.0, blue: 0xCC / 255.0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // App Logo Icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 124, height: 124)
                    
                    SpeechBubbleShape()
                        .fill(Color.white)
                        .frame(width: 88, height: 88)
                        .shadow(
                            color: Color(red: 0x00 / 255.0, green: 0x2D / 255.0, blue: 0x5A / 255.0).opacity(0.25),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                Text(L10n.Auth.title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .opacity(textOpacity)
                
                // Progress Indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                    .padding(.top, 40)
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                textOpacity = 1.0
            }
        }
    }
}

/// Friends アプリ公式アプリアイコン（shared/data/friends.icon.svg）準拠の吹き出しシェイプ
public struct SpeechBubbleShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 512.0
        let offsetX = rect.minX + (rect.width - 512.0 * scale) / 2.0
        let offsetY = rect.minY + (rect.height - 512.0 * scale) / 2.0
        
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
        }
        
        var path = Path()
        path.move(to: pt(154, 130))
        path.addLine(to: pt(358, 130))
        path.addCurve(to: pt(419.2, 202), control1: pt(391.796, 130), control2: pt(419.2, 162.24))
        path.addLine(to: pt(419.2, 304))
        path.addCurve(to: pt(358, 376), control1: pt(419.2, 343.76), control2: pt(391.796, 376))
        path.addLine(to: pt(239, 376))
        path.addLine(to: pt(172.7, 422))
        path.addCurve(to: pt(159.1, 413), control1: pt(166.75, 426.5), control2: pt(159.1, 422))
        path.addLine(to: pt(159.1, 376))
        path.addLine(to: pt(154, 376))
        path.addCurve(to: pt(92.8, 304), control1: pt(120.204, 376), control2: pt(92.8, 343.76))
        path.addLine(to: pt(92.8, 202))
        path.addCurve(to: pt(154, 130), control1: pt(92.8, 162.24), control2: pt(120.204, 130))
        path.closeSubpath()
        
        return path
    }
}

