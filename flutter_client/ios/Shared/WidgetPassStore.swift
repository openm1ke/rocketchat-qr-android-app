import Foundation
import ImageIO
import UIKit

struct StoredWidgetPass: Codable {
    let image: Data
    let expiresAt: Int64
    let expiresOn: Int64?
    let boostBrightness: Bool
    let scanSize: Double

    func isValid(at date: Date = Date()) -> Bool {
        !image.isEmpty && date.timeIntervalSince1970 * 1000 < Double(expiresAt)
    }

    var expiry: Date { Date(timeIntervalSince1970: Double(expiresAt) / 1000) }
}

enum WidgetPassStore {
    static let appGroup = "group.s21.campusPass.widgets"
    static let kind = "CampusPassQR"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-pass.json")
    }

    static func read(at date: Date = Date()) -> StoredWidgetPass? {
        guard let url = fileURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 6 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let pass = try? JSONDecoder().decode(StoredWidgetPass.self, from: data),
              pass.image.count <= 4 * 1024 * 1024,
              pass.isValid(at: date) else { return nil }
        // Widget extension readers never delete: an expired timeline must not
        // race with the application's atomic replacement of a newer snapshot.
        return pass
    }

    static func publish(_ pass: StoredWidgetPass) throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        guard pass.isValid() else { try clear(); return }
        guard pass.image.count <= 4 * 1024 * 1024,
              pass.image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(pass.image as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try JSONEncoder().encode(pass)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var resource = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
    }

    static func clear() throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Opaque white quiet zone is part of the image, so iOS tint modes must not
    /// recolor the QR or turn its background transparent.
    static func qrTile(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 896,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            context.cgContext.interpolationQuality = .none
            let scale = 896 / CGFloat(max(cgImage.width, cgImage.height))
            let size = CGSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
            UIImage(cgImage: cgImage).draw(in: CGRect(
                x: (1024-size.width)/2, y: (1024-size.height)/2,
                width: size.width, height: size.height
            ))
        }
    }
}
