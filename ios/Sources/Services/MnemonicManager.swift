import Foundation
import CryptoKit
import Security
import SwiftMnemonic

// MARK: - MnemonicManager
/// BIP-39 互換の「ふっかつのじゅもん（12単語）」生成・検証、および HKDF による
/// 復旧鍵 (K_recovery_id)・秘密鍵暗号化鍵 (K_priv_enc) の確定導出と秘密鍵暗号化・復号を担当する暗号エンジン
public final class MnemonicManager {
    public static let shared = MnemonicManager()

    private init() {}

    // MARK: - Mnemonic Generation & Validation

    /// 128-bit 暗号論的エントロピーから 12 単語の「ふっかつのじゅもん」を新規生成する
    /// - Parameter language: 生成言語（デフォルト: .japanese 日本語ひらがな12語）
    public func generateMnemonic(language: Language = .japanese) throws -> [String] {
        let mnemonic = try Mnemonic(language: language, wordCount: .twelve)
        return mnemonic.phrase
    }

    /// 12単語のフレーズが BIP-39 規格（単語妥当性・チェックサム・言語自動判定）に適合しているかを検証する
    public func validateMnemonic(words: [String]) -> Bool {
        guard words.count == 12 else { return false }
        do {
            _ = try Mnemonic(from: words)
            return true
        } catch {
            return false
        }
    }

    /// 単語リストから Mnemonic インスタンス（言語自動判定・デリミタ等を含む）を取得する
    public func parseMnemonic(words: [String]) throws -> Mnemonic {
        return try Mnemonic(from: words)
    }

    /// 指定言語の BIP-39 公式 2048 単語リストを取得する
    public func wordList(for language: Language = .english) throws -> [String] {
        return try language.words()
    }

    // MARK: - Key Derivation (HKDF)

    /// 12単語から Master Seed を生成し、HKDF で K_recovery_id, K_priv_enc, recoveryHash を導出する
    /// 設計書 doc/07-detailed-usecases/07-04-device-recovery.md 第2節に完全準拠
    public func deriveKeys(from words: [String]) throws -> (masterSeed: Data, recoveryIdKey: SymmetricKey, privEncKey: SymmetricKey, recoveryHash: String) {
        guard validateMnemonic(words: words) else {
            throw NSError(domain: "MnemonicManager", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Auth.recoveryInvalidPhrase])
        }

        // 言語に応じた正規化フレーズの構築 (日本語は全角スペース、他は半角スペース)
        let mnemonicObj = try? Mnemonic(from: words)
        let delimiter = mnemonicObj?.delimiter ?? " "
        let normalizedPhrase = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: delimiter)
        let phraseData = Data(Mnemonic.normalizeString(normalizedPhrase).utf8)

        // 1. Master Seed = HKDF-Extract using SHA256 with fixed domain salt
        let masterSalt = Data("friends-mnemonic-master-salt-v1".utf8)
        let masterSymmetricKey = SymmetricKey(data: phraseData)
        let masterSeedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterSymmetricKey,
            salt: masterSalt,
            info: Data("friends-mnemonic-seed-v1".utf8),
            outputByteCount: 32
        )
        let masterSeed = masterSeedKey.withUnsafeBytes { Data($0) }

        // 2. K_recovery_id (info = "friends-auth-recovery-v1")
        let recoveryIdKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterSeedKey,
            salt: Data(),
            info: Data("friends-auth-recovery-v1".utf8),
            outputByteCount: 32
        )

        // 3. K_priv_enc (info = "friends-key-backup-v1")
        let privEncKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterSeedKey,
            salt: Data(),
            info: Data("friends-key-backup-v1".utf8),
            outputByteCount: 32
        )

        // 4. recoveryHash = SHA256(K_recovery_id) in Hex
        let recoveryIdRaw = recoveryIdKey.withUnsafeBytes { Data($0) }
        let hash = SHA256.hash(data: recoveryIdRaw)
        let recoveryHash = hash.compactMap { String(format: "%02x", $0) }.joined()

        return (masterSeed, recoveryIdKey, privEncKey, recoveryHash)
    }

    // MARK: - PrivateKey Encryption & Decryption (AES-256-GCM)

    /// Curve25519 秘密鍵を K_priv_enc を用いて AES-256-GCM で暗号化する
    public func encryptPrivateKey(
        _ privateKey: Curve25519.KeyAgreement.PrivateKey,
        using key: SymmetricKey
    ) throws -> (ciphertext: String, nonce: String) {
        let rawPrivKey = privateKey.rawRepresentation
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(rawPrivKey, using: key, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw NSError(domain: "MnemonicManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to seal private key payload"])
        }

        return (combined.base64EncodedString(), Data(nonce).base64EncodedString())
    }

    /// 暗号化された秘密鍵を K_priv_enc を用いて復号し、Curve25519 秘密鍵を復元する
    public func decryptPrivateKey(
        ciphertext: String,
        nonce: String,
        using key: SymmetricKey
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let combinedData = Data(base64Encoded: ciphertext), combinedData.count >= 28 else {
            throw NSError(domain: "MnemonicManager", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.decryptionFailed])
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)

            guard decryptedData.count == 32 else {
                throw NSError(domain: "MnemonicManager", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.decryptionFailed])
            }

            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: decryptedData)
        } catch {
            throw NSError(domain: "MnemonicManager", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.decryptionFailed])
        }
    }
}

