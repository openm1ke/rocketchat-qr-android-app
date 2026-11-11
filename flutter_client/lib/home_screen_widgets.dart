import 'dart:async';

import 'package:flutter/services.dart';

class WidgetPass {
  const WidgetPass({
    required this.image,
    required this.expiresAt,
    this.expiresOn,
    this.boostBrightness = true,
    this.scanSize = 1,
  });

  final Uint8List image;
  final DateTime expiresAt;
  final DateTime? expiresOn;
  final bool boostBrightness;
  final double scanSize;

  bool isValidAt(DateTime now) => image.isNotEmpty && now.isBefore(expiresAt);

  Map<String, Object?> toMessage() => {
    'image': image,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'expiresOn': expiresOn?.millisecondsSinceEpoch,
    'boostBrightness': boostBrightness,
    'scanSize': scanSize,
  };

  static WidgetPass? fromMessage(Map<Object?, Object?>? value) {
    if (value == null) return null;
    final image = value['image'];
    final expiresAt = value['expiresAt'];
    final expiresOn = value['expiresOn'];
    if (image is! Uint8List || image.isEmpty || expiresAt is! int) return null;
    return WidgetPass(
      image: image,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      expiresOn: expiresOn is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresOn)
          : null,
      boostBrightness: value['boostBrightness'] != false,
      scanSize: (value['scanSize'] as num?)?.toDouble().clamp(.75, 1) ?? 1,
    );
  }
}

class WidgetCapabilities {
  const WidgetCapabilities({
    this.platform = '',
    this.supported = false,
    this.pinSupported = false,
    this.overlayAllowed = false,
    this.installedCount = 0,
  });

  final String platform;
  final bool supported;
  final bool pinSupported;
  final bool overlayAllowed;
  final int installedCount;

  factory WidgetCapabilities.fromMessage(Map<Object?, Object?>? value) =>
      WidgetCapabilities(
        platform: value?['platform'] as String? ?? '',
        supported: value?['supported'] == true,
        pinSupported: value?['pinSupported'] == true,
        overlayAllowed: value?['overlayAllowed'] == true,
        installedCount: value?['installedCount'] as int? ?? 0,
      );
}

/// Transfers only the last QR image and its expiry to native widgets. Tokens,
/// credentials and Rocket.Chat sessions never enter the shared widget store.
class HomeScreenWidgets {
  HomeScreenWidgets({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('s21.campus_pass/widgets');

  final MethodChannel _channel;
  Future<void> _writes = Future.value();

  void setWidgetTapHandler(Future<void> Function()? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'widgetTapped') await handler();
            },
    );
  }

  Future<bool> takeWidgetTap() async {
    try {
      return await _channel.invokeMethod<bool>('takeWidgetTap') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<T> _ordered<T>(Future<T> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> publish(WidgetPass pass) => _ordered(() async {
    if (!pass.isValidAt(DateTime.now())) {
      await _channel.invokeMethod<void>('clear');
      return;
    }
    await _channel.invokeMethod<void>('publish', pass.toMessage());
  });

  Future<void> clear() => _ordered(() => _channel.invokeMethod<void>('clear'));

  Future<WidgetPass?> read() async {
    await _writes;
    final result = WidgetPass.fromMessage(
      await _channel.invokeMapMethod<Object?, Object?>('read'),
    );
    return result != null && result.isValidAt(DateTime.now()) ? result : null;
  }

  Future<WidgetCapabilities> capabilities() async {
    try {
      return WidgetCapabilities.fromMessage(
        await _channel.invokeMapMethod<Object?, Object?>('capabilities'),
      );
    } on MissingPluginException {
      return const WidgetCapabilities();
    }
  }

  Future<bool> requestPin() async =>
      await _channel.invokeMethod<bool>('requestPin') ?? false;

  Future<void> requestOverlayPermission() =>
      _channel.invokeMethod<void>('requestOverlayPermission');
}
