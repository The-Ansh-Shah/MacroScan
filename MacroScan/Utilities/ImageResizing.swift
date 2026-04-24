import SwiftUI

#if canImport(UIKit)
import UIKit

enum ImageResizing {
    /// Resize a UIImage to fit within maxDimension, preserving aspect ratio.
    /// Returns JPEG data at the specified quality.
    static func resizeForUpload(_ image: UIImage, maxDimension: CGFloat = 1024, jpegQuality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: jpegQuality)
    }

    /// Convert image Data to base64 string for API calls
    static func base64Encode(_ data: Data) -> String {
        data.base64EncodedString()
    }
}
#endif
