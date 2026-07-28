import Foundation
import SwiftUI
import CoreImage.CIFilterBuiltins
import CryptoKit

// MARK: - Friend Passcode Generator (3桁合言葉・30秒ローテーション TOTP)

struct FriendPasscodeGenerator {
    static let stepInterval: TimeInterval = 30.0
    
    /// 現在のタイムステップ番号を取得
    static func currentStep(date: Date = Date()) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / stepInterval))
    }
    
    /// 次の更新までの残り秒数 (1〜30)
    static func remainingSeconds(date: Date = Date()) -> Int {
        let sec = Int(date.timeIntervalSince1970) % Int(stepInterval)
        return Int(stepInterval) - sec
    }
    
    /// 進捗率 (0.0 〜 1.0)
    static func progress(date: Date = Date()) -> Double {
        let sec = date.timeIntervalSince1970.truncatingRemainder(dividingBy: stepInterval)
        return sec / stepInterval
    }
    
    /// 特定のステップ・ユーザー・テナントに対する3桁合言葉を生成
    static func code(forStep step: Int64, uid: String, tenantId: String) -> String {
        let seed = "\(uid):\(tenantId):\(step)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        
        let value = digest.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(as: UInt32.self).bigEndian
        }
        let numeric = Int(value % 1000)
        return String(format: "%03d", numeric)
    }
    
    /// 現在時刻での3桁合言葉
    static func generatePasscode(uid: String, tenantId: String, date: Date = Date()) -> String {
        let step = currentStep(date: date)
        return code(forStep: step, uid: uid, tenantId: tenantId)
    }
    
    /// 合言葉の検証 (前後 toleranceSteps ウィンドウを許容)
    static func validatePasscode(
        code inputCode: String,
        uid: String,
        tenantId: String,
        date: Date = Date(),
        toleranceSteps: Int = 1
    ) -> Bool {
        let clean = inputCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 3, clean.allSatisfy({ $0.isNumber }) else {
            return false
        }
        
        let current = currentStep(date: date)
        for offset in (-toleranceSteps)...toleranceSteps {
            let step = current + Int64(offset)
            if code(forStep: step, uid: uid, tenantId: tenantId) == clean {
                return true
            }
        }
        return false
    }
}

// MARK: - Friend Invitation Payload Encoder / Decoder

struct FriendInvitationHelper {
    static let prefix = "FRIENDS_USER:"
    
    /// ペイロードを `FRIENDS_USER:<Base64>` 文字列にエンコード
    static func encode(payload: FriendsFriendInvitationPayload) -> String {
        let dict: [String: Any] = [
            "type": "friend_invite",
            "version": 1,
            "tenantId": payload.tenantID,
            "userId": payload.userID,
            "uid": payload.uid,
            "displayName": payload.displayName,
            "publicKey": payload.publicKey,
            "passcode": payload.passcode,
            "timestamp": payload.timestamp
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let b64 = String(data: jsonData.base64EncodedData(), encoding: .utf8) else {
            return ""
        }
        return "\(prefix)\(b64)"
    }
    
    /// QR文字列 / URL / 生JSON から招待ペイロードをパース
    static func decode(rawInput: String) -> FriendsFriendInvitationPayload? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        
        var jsonDict: [String: Any]?
        
        // 1. FRIENDS_USER: base64
        if input.hasPrefix(prefix) {
            let b64 = input.replacingOccurrences(of: prefix, with: "")
            if let data = Data(base64Encoded: b64),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                jsonDict = obj
            }
        }
        // 2. friends://friend?data=base64
        else if let url = URL(string: input),
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let dataB64 = components.queryItems?.first(where: { $0.name == "data" })?.value,
                let data = Data(base64Encoded: dataB64),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonDict = obj
        }
        // 3. Raw JSON
        else if let data = input.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonDict = obj
        }
        
        guard let dict = jsonDict,
              let tenantId = dict["tenantId"] as? String,
              let userId = dict["userId"] as? String,
              let uid = dict["uid"] as? String else {
            return nil
        }
        
        let displayName = dict["displayName"] as? String ?? "ユーザー"
        let publicKey = dict["publicKey"] as? String ?? ""
        let passcode = dict["passcode"] as? String ?? ""
        let timestamp = dict["timestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970)
        
        var payload = FriendsFriendInvitationPayload()
        payload.type = "friend_invite"
        payload.version = 1
        payload.tenantID = tenantId
        payload.userID = userId
        payload.uid = uid
        payload.displayName = displayName
        payload.publicKey = publicKey
        payload.passcode = passcode
        payload.timestamp = timestamp
        return payload
    }
}

// MARK: - Crisp QR Code Generator

struct QRCodeGeneratorHelper {
    private static let context = CIContext()
    
    static func generateQRCode(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
