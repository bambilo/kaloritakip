import UIKit

enum ImageProcessing {
    static let maxEdge: CGFloat = 1024      // Gemini'ye gonderilen gorselin uzun kenari
    static let thumbEdge: CGFloat = 320     // gecmiste gosterilen kucuk onizleme
    static let jpegQuality: CGFloat = 0.85

    /// EXIF/orientation'i piksellere gomup kucultur, JPEG'e cevirir.
    /// UIImage.draw(in:) imageOrientation'i otomatik uyguladigi icin
    /// ayrica donme islemi gerekmez -- Python tarafindaki ImageOps.exif_transpose
    /// ile ayni isi gorur.
    static func prepare(_ image: UIImage, maxEdge: CGFloat = maxEdge, quality: CGFloat = jpegQuality) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1.0, maxEdge / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.jpegData(compressionQuality: quality)
    }

    static func thumbnail(_ image: UIImage) -> Data? {
        prepare(image, maxEdge: thumbEdge, quality: jpegQuality)
    }
}
