import Flutter
import UIKit
import WidgetKit

final class PassWidgetBridge {
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "s21.campus_pass/widgets", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterMethodNotImplemented); return }
            self.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "publish":
                guard let args = call.arguments as? [String: Any],
                      let bytes = args["image"] as? FlutterStandardTypedData,
                      let expiry = args["expiresAt"] as? NSNumber else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try WidgetPassStore.publish(StoredWidgetPass(
                    image: bytes.data, expiresAt: expiry.int64Value,
                    expiresOn: (args["expiresOn"] as? NSNumber)?.int64Value,
                    boostBrightness: args["boostBrightness"] as? Bool ?? true,
                    scanSize: min(1, max(0.75, args["scanSize"] as? Double ?? 1))
                ))
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetPassStore.kind)
                result(nil)
            case "clear":
                try WidgetPassStore.clear()
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetPassStore.kind)
                result(nil)
            case "read":
                guard let pass = WidgetPassStore.read() else { result(nil); return }
                let expiryDate: Any = pass.expiresOn.map { $0 as Any } ?? NSNull()
                result([
                    "image": FlutterStandardTypedData(bytes: pass.image),
                    "expiresAt": pass.expiresAt, "expiresOn": expiryDate,
                    "boostBrightness": pass.boostBrightness, "scanSize": pass.scanSize,
                ])
            case "capabilities":
                let supported: Bool
                if #available(iOS 17.0, *) { supported = true } else { supported = false }
                WidgetCenter.shared.getCurrentConfigurations { configurations in
                    let count = (try? configurations.get().filter { $0.kind == WidgetPassStore.kind }.count) ?? 0
                    DispatchQueue.main.async {
                        result(["platform": "ios", "supported": supported,
                                "pinSupported": false, "overlayAllowed": false,
                                "installedCount": count])
                    }
                }
            case "requestPin": result(false)
            default: result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "widget_storage", message: "Не удалось обновить виджет", details: nil))
        }
    }
}
