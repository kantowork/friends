import UIKit
import Foundation
import FirebaseFirestore
import CommonCrypto

final class AvatarRepository {
    static let shared = AvatarRepository()
    private let db = Firestore.firestore()
    private let memoryCache = NSCache<NSString, UIImage>()
    
    private init() {}
    
    // MARK: - AWS SigV4 Helper
    
    private func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBytes.baseAddress, key.count, dataBytes.baseAddress, data.count, &hash)
            }
        }
        return Data(hash)
    }
    
    private func sha256Hex(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func sha256Hex(string: String) -> String {
        return sha256Hex(data: Data(string.utf8))
    }
    
    /// R2 への暗号化バイナリアップロード (AWS SigV4 PUT)
    private func uploadToR2(
        encryptedData: Data,
        storagePath: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard R2Config.isConfigured,
              let _ = URL(string: R2Config.endpointURL),
              !R2Config.bucketName.isEmpty,
              !R2Config.accessKeyId.isEmpty,
              !R2Config.secretAccessKey.isEmpty else {
            completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.configIncomplete])))
            return
        }
        
        let bucket = R2Config.bucketName
        let accessKey = R2Config.accessKeyId
        let secretKey = R2Config.secretAccessKey
        let region = "auto"
        let service = "s3"
        
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)
        
        let payloadHash = sha256Hex(data: encryptedData)
        guard let requestUrl = URL(string: "\(R2Config.endpointURL)/\(bucket)/\(storagePath)"),
              let host = requestUrl.host else {
            completion(.failure(NSError(domain: "AvatarError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.invalidEndpoint])))
            return
        }
        
        let canonicalUri = "/\(bucket)/\(storagePath)"
        let canonicalQuerystring = ""
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = "PUT\n\(canonicalUri)\n\(canonicalQuerystring)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "\(algorithm)\n\(amzDate)\n\(credentialScope)\n\(sha256Hex(string: canonicalRequest))"
        
        let kDate = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()
        
        let authorizationHeader = "\(algorithm) Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "PUT"
        request.httpBody = encryptedData
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                completion(.success(()))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                completion(.failure(NSError(domain: "AvatarError", code: status, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.uploadFailed(status)])))
            }
        }
        task.resume()
    }
    
    /// アバター画像の暗号化アップロード (AP-01 / Cloudflare R2 + Firestore)
    func uploadAvatarByUserId(
        image: UIImage,
        tenantId: String,
        userId: String,
        completion: @escaping (Result<(Date, String), Error>) -> Void
    ) {
        guard let resizedImage = resizeImage(image: image, targetSize: CGSize(width: 256, height: 256)),
              let rawData = resizedImage.jpegData(compressionQuality: 0.75) else {
            completion(.failure(NSError(domain: "AvatarError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.imageCompressFailed])))
            return
        }
        
        // 1. MK_T でバイナリを AES-GCM 暗号化
        guard let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: rawData.base64EncodedString(), tenantId: tenantId) else {
            completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.imageEncryptFailed])))
            return
        }
        
        let now = Date()
        let cacheKey = "avatar_\(userId)_\(now.timeIntervalSince1970)" as NSString
        self.memoryCache.setObject(resizedImage, forKey: cacheKey)
        let userLatestKey = "avatar_\(userId)" as NSString
        self.memoryCache.setObject(resizedImage, forKey: userLatestKey)
        
        let storagePath = "tenants/\(tenantId)/users/\(userId)/avatar.enc"
        let encDataToUpload = Data(enc.encryptedData.utf8)
        
        // 2. Cloudflare R2 へアップロード
        uploadToR2(encryptedData: encDataToUpload, storagePath: storagePath) { [weak self] r2Result in
            guard let self = self else { return }
            switch r2Result {
            case .success:
                // 3. Firestore メタデータの更新
                let userDocRef = self.db.collection("tenants").document(tenantId).collection("users").document(userId)
                let updates: [String: Any] = [
                    "avatarNonce": enc.nonce,
                    "avatarUpdatedAt": Timestamp(date: now),
                    "updatedBy": userId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                
                userDocRef.updateData(updates) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success((now, enc.nonce)))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// アバター画像の取得・復号 (AP-02 / 2層キャッシュ優先 + R2 CDN)
    func getAvatarByUserId(
        tenantId: String,
        userId: String,
        avatarNonce: String,
        updatedAt: Date?,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        let cacheKey = "avatar_\(userId)_\(updatedAt?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            completion(.success(cached))
            return
        }
        
        guard !avatarNonce.isEmpty else {
            completion(.failure(NSError(domain: "AvatarError", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.avatarNotSet])))
            return
        }
        
        // 1. R2 公開 CDN URL からの高速 GET 取得
        let storagePath = "tenants/\(tenantId)/users/\(userId)/avatar.enc"
        guard !R2Config.publicBaseURL.isEmpty, let cdnUrl = URL(string: "\(R2Config.publicBaseURL)/\(storagePath)") else {
            completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.cdnUrlInvalid])))
            return
        }
        
        var req = URLRequest(url: cdnUrl)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        
        let cdnTask = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let data = data, let encString = String(data: data, encoding: .utf8), !encString.isEmpty else {
                completion(.failure(NSError(domain: "AvatarError", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.cdnFetchFailed])))
                return
            }
            
            do {
                let decryptedBase64 = try CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encString, nonce: avatarNonce, tenantId: tenantId)
                guard let imgData = Data(base64Encoded: decryptedBase64),
                      let img = UIImage(data: imgData) else {
                    completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.imageDecodeFailed])))
                    return
                }
                self.memoryCache.setObject(img, forKey: cacheKey)
                let userLatestKey = "avatar_\(userId)" as NSString
                self.memoryCache.setObject(img, forKey: userLatestKey)
                completion(.success(img))
            } catch {
                completion(.failure(error))
            }
        }
        cdnTask.resume()
    }
    
    /// キャッシュから同期的にアバター画像を取得（存在する場合）
    func getCachedAvatar(userId: String, updatedAt: Date?) -> UIImage? {
        let cacheKey = "avatar_\(userId)_\(updatedAt?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }
        let userLatestKey = "avatar_\(userId)" as NSString
        return memoryCache.object(forKey: userLatestKey)
    }
    
    /// メモリキャッシュにアバターを保存
    func cacheAvatar(_ image: UIImage, userId: String, updatedAt: Date? = nil) {
        let cacheKey = "avatar_\(userId)_\(updatedAt?.timeIntervalSince1970 ?? 0)" as NSString
        memoryCache.setObject(image, forKey: cacheKey)
        let userLatestKey = "avatar_\(userId)" as NSString
        memoryCache.setObject(image, forKey: userLatestKey)
    }
    
    /// アバター削除 (AP-03)
    func deleteAvatarByUserId(
        tenantId: String,
        userId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let userDocRef = db.collection("tenants").document(tenantId).collection("users").document(userId)
        let updates: [String: Any] = [
            "encryptedAvatar": FieldValue.delete(),
            "avatarStoragePath": FieldValue.delete(),
            "avatarNonce": FieldValue.delete(),
            "avatarUpdatedAt": FieldValue.delete(),
            "updatedBy": userId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        userDocRef.updateData(updates) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Group Avatar Operations
    
    /// グループアバターの暗号化・R2アップロード・Firestore更新
    func uploadGroupAvatar(
        tenantId: String,
        chatId: String,
        image: UIImage,
        updatedBy: String,
        completion: @escaping (Result<(Date, String), Error>) -> Void
    ) {
        guard let resizedImage = resizeImage(image: image, targetSize: CGSize(width: 256, height: 256)),
              let rawData = resizedImage.jpegData(compressionQuality: 0.75) else {
            completion(.failure(NSError(domain: "AvatarError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.imageCompressFailed])))
            return
        }
        
        // 1. MK_T でバイナリを AES-GCM 暗号化
        guard let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: rawData.base64EncodedString(), tenantId: tenantId) else {
            completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.imageEncryptFailed])))
            return
        }
        
        let now = Date()
        let cacheKey = "avatar_group_\(chatId)_\(now.timeIntervalSince1970)" as NSString
        self.memoryCache.setObject(resizedImage, forKey: cacheKey)
        let groupLatestKey = "avatar_group_\(chatId)" as NSString
        self.memoryCache.setObject(resizedImage, forKey: groupLatestKey)
        
        let storagePath = "tenants/\(tenantId)/chats/\(chatId)/avatar.enc"
        let encDataToUpload = Data(enc.encryptedData.utf8)
        
        // 2. Cloudflare R2 へアップロード
        uploadToR2(encryptedData: encDataToUpload, storagePath: storagePath) { [weak self] r2Result in
            guard let self = self else { return }
            switch r2Result {
            case .success:
                // 3. Firestore メタデータの更新
                let chatDocRef = self.db.collection("tenants").document(tenantId).collection("chats").document(chatId)
                let updates: [String: Any] = [
                    "avatarNonce": enc.nonce,
                    "avatarUpdatedAt": Timestamp(date: now),
                    "updatedBy": updatedBy,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                
                chatDocRef.updateData(updates) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success((now, enc.nonce)))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// グループアバター画像の取得・復号
    func getGroupAvatar(
        tenantId: String,
        chatId: String,
        avatarNonce: String,
        updatedAt: Date?,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        let cacheKey = "avatar_group_\(chatId)_\(updatedAt?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            completion(.success(cached))
            return
        }
        
        guard !avatarNonce.isEmpty else {
            completion(.failure(NSError(domain: "AvatarError", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.avatarNotSet])))
            return
        }
        
        let storagePath = "tenants/\(tenantId)/chats/\(chatId)/avatar.enc"
        guard !R2Config.publicBaseURL.isEmpty, let cdnUrl = URL(string: "\(R2Config.publicBaseURL)/\(storagePath)") else {
            completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.cdnUrlInvalid])))
            return
        }
        
        var req = URLRequest(url: cdnUrl)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        
        let cdnTask = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200, let data = data, !data.isEmpty {
                guard let encString = String(data: data, encoding: .utf8),
                      let decryptedBase64 = try? CryptoKeyManager.shared.decryptWithTenantKey(
                        encryptedData: encString,
                        nonce: avatarNonce,
                        tenantId: tenantId
                      ),
                      let rawImageData = Data(base64Encoded: decryptedBase64),
                      let image = UIImage(data: rawImageData) else {
                    completion(.failure(NSError(domain: "AvatarError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.imageDecodeFailed])))
                    return
                }
                
                self.memoryCache.setObject(image, forKey: cacheKey)
                let groupLatestKey = "avatar_group_\(chatId)" as NSString
                self.memoryCache.setObject(image, forKey: groupLatestKey)
                completion(.success(image))
                return
            }
            
            completion(.failure(error ?? NSError(domain: "AvatarError", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Storage.cdnFetchFailed])))
        }
        cdnTask.resume()
    }
    
    /// キャッシュから同期的にグループアバター画像を取得
    func getCachedGroupAvatar(chatId: String, updatedAt: Date?) -> UIImage? {
        let cacheKey = "avatar_group_\(chatId)_\(updatedAt?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }
        let groupLatestKey = "avatar_group_\(chatId)" as NSString
        return memoryCache.object(forKey: groupLatestKey)
    }
    
    /// グループアバター削除
    func deleteGroupAvatar(
        tenantId: String,
        chatId: String,
        updatedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatDocRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        let updates: [String: Any] = [
            "avatarNonce": FieldValue.delete(),
            "avatarUpdatedAt": FieldValue.delete(),
            "updatedBy": updatedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        chatDocRef.updateData(updates) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage? {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let scale = min(widthRatio, heightRatio)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
}
