import Foundation

extension CGSize {
    func scaled(scale: CGFloat) -> CGSize {
        return CGSize(width: width * scale, height: height * scale)
    }
}
