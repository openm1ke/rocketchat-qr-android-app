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

struct WidgetAppearance: Codable {
    let content: String
    let background: UInt32
    let foreground: UInt32

    init(content: String = "logo", background: UInt32 = 0xFF000000,
         foreground: UInt32 = 0xFF8DF86B) {
        self.content = content == "qr" ? "qr" : "logo"
        self.background = background | 0xFF000000
        self.foreground = foreground | 0xFF000000
    }

    init(message: [String: Any]) {
        self.init(content: message["content"] as? String ?? "logo",
                  background: (message["background"] as? NSNumber)?.uint32Value ?? 0xFF000000,
                  foreground: (message["foreground"] as? NSNumber)?.uint32Value ?? 0xFF8DF86B)
    }

    var message: [String: Any] {
        ["content": content, "background": background, "foreground": foreground]
    }

    static func uiColor(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    var textColor: UIColor {
        func linear(_ value: UInt32) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear((background >> 16) & 255) +
            0.7152 * linear((background >> 8) & 255) + 0.0722 * linear(background & 255)
        return luminance > 0.179 ? .black : .white
    }
}

enum WidgetPassStore {
    static let openPassURL = URL(string: "s21-campus-pass://widget/open")!
    static let appGroup = "group.s21.campusPass.widgets"
    static let kind = "CampusPassQR"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-pass.json")
    }

    private static var appearanceURL: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("widget-appearance.json")
    }

    static func readAppearance() -> WidgetAppearance {
        guard let url = appearanceURL,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4096, let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(WidgetAppearance.self, from: data) else {
            return WidgetAppearance()
        }
        return WidgetAppearance(content: value.content, background: value.background,
                                foreground: value.foreground)
    }

    static func saveAppearance(_ appearance: WidgetAppearance) throws {
        guard let url = appearanceURL else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(appearance).write(to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var resource = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
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

    /// The quiet zone uses the same background as the widget. The source pass
    /// remains intact for the full-screen scanner view.
    static func qrTile(_ data: Data, appearance: WidgetAppearance) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 896,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colored: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            bitmap.setFillColor(UIColor.white.cgColor)
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: data.count, by: 4) {
                let light = (0.299 * Double(data[offset]) + 0.587 * Double(data[offset + 1]) +
                    0.114 * Double(data[offset + 2])) / 255
                for (channel, shift) in [16, 8, 0].enumerated() {
                    let dark = Double((appearance.foreground >> shift) & 255)
                    let bright = Double((appearance.background >> shift) & 255)
                    data[offset + channel] = UInt8(max(0, min(255, (dark + (bright - dark) * light).rounded())))
                }
                data[offset + 3] = 255
            }
            return bitmap.makeImage()
        }
        guard let colored = colored else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { context in
            WidgetAppearance.uiColor(appearance.background).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            context.cgContext.interpolationQuality = .none
            let scale = 896 / CGFloat(max(cgImage.width, cgImage.height))
            let size = CGSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
            UIImage(cgImage: colored).draw(in: CGRect(
                x: (1024-size.width)/2, y: (1024-size.height)/2,
                width: size.width, height: size.height
            ))
        }
    }
}
