import UIKit

/// 画像を端末の「写真（カメラロール）」へ保存するためのヘルパー
final class ImageSaveHelper: NSObject {
    static let shared = ImageSaveHelper()
    
    private var singleCompletion: ((Result<Void, Error>) -> Void)?
    
    func saveImage(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        self.singleCompletion = completion
        UIImageWriteToSavedPhotosAlbum(
            image,
            self,
            #selector(imageSaved(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }
    
    @objc private func imageSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        if let error = error {
            singleCompletion?(.failure(error))
        } else {
            singleCompletion?(.success(()))
        }
        singleCompletion = nil
    }
}
