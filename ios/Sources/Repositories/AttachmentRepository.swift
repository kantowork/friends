import UIKit
import Foundation
import CommonCrypto
import CryptoKit

/// チャット添付ファイル（写真・画像）の Cloudflare R2 への E2EE 暗号化アップロードおよび CDN 高速取得・2層キャッシュ管理リポジトリ
final class AttachmentRepository {
    static let shared = AttachmentRepository()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheDirectory: URL
    
    private init() {
        // メモリキャッシュの上限設定（50MB相当 / 最大100枚）
        memoryCache.totalCostLimit = 50 * 1024 * 1024
        memoryCache.countLimit = 100
        
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.diskCacheDirectory = cachesDir.appendingPathComponent("FriendsEncryptedAttachments", isDirectory: true)
        
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    // MARK: - AWS SigV4 Helpers
    
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
    
    // MARK: - Upload to Cloudflare R2 (FP-01)
    
    /// 暗号化バイナリを Cloudflare R2 へ AWS SigV4 PUT で直接アップロード
    func uploadAttachment(
        encryptedData: Data,
        storagePath: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard R2Config.isConfigured,
              let _ = URL(string: R2Config.endpointURL),
              !R2Config.bucketName.isEmpty,
              !R2Config.accessKeyId.isEmpty,
              !R2Config.secretAccessKey.isEmpty else {
            completion(.failure(NSError(domain: "AttachmentError", code: 500, userInfo: [NSLocalizedDescriptionKey: "R2 ストレージ設定が不完全です。"])))
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
            completion(.failure(NSError(domain: "AttachmentError", code: 400, userInfo: [NSLocalizedDescriptionKey: "不正なストレージエンドポイントです。"])))
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
                completion(.failure(NSError(domain: "AttachmentError", code: status, userInfo: [NSLocalizedDescriptionKey: "R2 への画像アップロードに失敗しました (HTTP \(status))"])))
            }
        }
        task.resume()
    }
    
    // MARK: - Download & Decrypt Attachment (FP-02)
    
    /// キャッシュから同期的に画像を取得（メモリまたはディスク）
    func getCachedImage(attachmentId: String) -> UIImage? {
        let key = attachmentId as NSString
        if let memoryImage = memoryCache.object(forKey: key) {
            return memoryImage
        }
        
        let diskPath = diskCacheDirectory.appendingPathComponent("\(attachmentId).cache")
        if let diskData = try? Data(contentsOf: diskPath),
           let diskImage = UIImage(data: diskData) {
            memoryCache.setObject(diskImage, forKey: key, cost: diskData.count)
            return diskImage
        }
        return nil
    }
    
    /// 添付画像の取得・復号（2層キャッシュ優先 + R2 CDN）
    func fetchAttachmentImage(
        attachment: MessageAttachment,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        let key = attachment.attachmentId as NSString
        
        // 1. メモリキャッシュ確認
        if let cached = memoryCache.object(forKey: key) {
            completion(.success(cached))
            return
        }
        
        // 2. ディスクキャッシュ確認
        let diskPath = diskCacheDirectory.appendingPathComponent("\(attachment.attachmentId).cache")
        if let diskData = try? Data(contentsOf: diskPath),
           let diskImage = UIImage(data: diskData) {
            memoryCache.setObject(diskImage, forKey: key, cost: diskData.count)
            completion(.success(diskImage))
            return
        }
        
        // 3. Cloudflare R2 CDN から暗号化バイナリを取得
        guard !R2Config.publicBaseURL.isEmpty,
              let cdnUrl = URL(string: "\(R2Config.publicBaseURL)/\(attachment.storagePath)") else {
            completion(.failure(NSError(domain: "AttachmentError", code: 500, userInfo: [NSLocalizedDescriptionKey: "R2 CDN URL の設定が無効です。"])))
            return
        }
        
        var req = URLRequest(url: cdnUrl)
        req.httpMethod = "GET"
        req.cachePolicy = .returnCacheDataElseLoad
        
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let encData = data, !encData.isEmpty else {
                completion(.failure(NSError(domain: "AttachmentError", code: 404, userInfo: [NSLocalizedDescriptionKey: "CDN から暗号化ファイルを取得できませんでした。"])))
                return
            }
            
            // 4. K_file で復号
            guard let keyData = Data(base64Encoded: attachment.fileKey) else {
                completion(.failure(NSError(domain: "AttachmentError", code: 400, userInfo: [NSLocalizedDescriptionKey: "無効なファイル暗号化鍵です。"])))
                return
            }
            let symmetricKey = SymmetricKey(data: keyData)
            
            do {
                let decryptedData = try CryptoKeyManager.shared.decryptFile(encryptedData: encData, key: symmetricKey)
                guard let image = UIImage(data: decryptedData) else {
                    completion(.failure(NSError(domain: "AttachmentError", code: 500, userInfo: [NSLocalizedDescriptionKey: "画像のデコードに失敗しました。"])))
                    return
                }
                
                // 5. 2層キャッシュに保存
                self.memoryCache.setObject(image, forKey: key, cost: decryptedData.count)
                try? decryptedData.write(to: diskPath, options: .atomic)
                
                DispatchQueue.main.async {
                    completion(.success(image))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
