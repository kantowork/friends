import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

// MARK: - Apple Auth Coordinator (Sign in with Apple)

/// Apple ID 認証リクエストの構築、暗号学的 Nonce 管理、および Firebase Auth Credential 生成を担うコーディネーター
@MainActor
public final class AppleAuthCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    public static let shared = AppleAuthCoordinator()
    
    private var currentNonce: String?
    private var completion: ((Result<(credential: AuthCredential, displayName: String?), Error>) -> Void)?
    
    private override init() {
        super.init()
    }
    
    /// Sign in with Apple フローを開始
    public func startSignIn(completion: @escaping (Result<(credential: AuthCredential, displayName: String?), Error>) -> Void) {
        self.completion = completion
        
        let nonce = randomNonceString()
        self.currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            let error = NSError(
                domain: "AppleAuthCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Apple ID Credential received."]
            )
            completion?(.failure(error))
            completion = nil
            return
        }
        
        guard let nonce = currentNonce else {
            let error = NSError(
                domain: "AppleAuthCoordinator",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Security nonce context missing."]
            )
            completion?(.failure(error))
            completion = nil
            return
        }
        
        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            let error = NSError(
                domain: "AppleAuthCoordinator",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to serialize identity token string."]
            )
            completion?(.failure(error))
            completion = nil
            return
        }
        
        // 初回サインイン時のみ提供される fullName を抽出
        var extractedName: String? = nil
        if let fullName = appleIDCredential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
            if !formatted.isEmpty {
                extractedName = formatted
            }
        }
        
        // Firebase OAuthProvider Apple Credential の生成
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
        
        completion?(.success((credential: credential, displayName: extractedName)))
        completion = nil
        currentNonce = nil
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        completion = nil
        currentNonce = nil
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }),
           let keyWindow = activeScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let firstWindow = scenes.first?.windows.first {
            return firstWindow
        }
        return ASPresentationAnchor()
    }
    
    // MARK: - Nonce & SHA256 Helpers
    
    /// 暗号論的擬似乱数を用いた安全な Nonce 文字列（32 bytes）を生成
    nonisolated public static func generateRandomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        Self.generateRandomNonceString(length: length)
    }
    
    /// 文字列の SHA256 ハッシュ文字列（16進数小文字）を生成
    nonisolated public static func sha256Hex(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func sha256(_ input: String) -> String {
        Self.sha256Hex(input)
    }
}
