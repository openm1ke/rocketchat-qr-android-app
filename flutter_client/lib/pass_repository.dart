import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'rocket_chat_client.dart';

class CachedPass {
  const CachedPass({
    required this.owner,
    required this.image,
    required this.receivedAt,
    required this.expiresAt,
    this.expiresOn,
  });

  final String owner;
  final Uint8List image;
  final DateTime receivedAt;
  final DateTime expiresAt;
  final DateTime? expiresOn;

  static String ownerFor(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  bool isValidAt(DateTime now) => now.isBefore(expiresAt);

  Map<String, Object?> toJson() => {
    'version': 1,
    'owner': owner,
    'image': base64Encode(image),
    'receivedAt': receivedAt.millisecondsSinceEpoch,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'expiresOn': expiresOn?.millisecondsSinceEpoch,
  };

  factory CachedPass.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1 ||
        value['owner'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['owner'] as String)) {
      throw const FormatException('Invalid cached pass');
    }
    final image = base64Decode(value['image'] as String);
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (image.length <= 8 ||
        image.length > 4 * 1024 * 1024 ||
        !List.generate(8, (i) => image[i] == signature[i]).every((v) => v)) {
      throw const FormatException('Invalid cached PNG');
    }
    return CachedPass(
      owner: value['owner'] as String,
      image: image,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        value['receivedAt'] as int,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(value['expiresAt'] as int),
      expiresOn: value['expiresOn'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value['expiresOn'] as int),
    );
  }
}

abstract class PassStore {
  Future<CachedPass?> readPass();
  Future<void> writePass(CachedPass? pass);
  Future<DateTime?> readRetryAt();
  Future<void> writeRetryAt(DateTime value);
}

/// The PNG is disposable, private cache data. The small request deadline lives
/// in secure storage, so clearing/evicting the image never removes throttling.
class LocalPassStore implements PassStore {
  LocalPassStore({
    FlutterSecureStorage? storage,
    Future<File> Function()? cacheFile,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _cacheFile = cacheFile ?? _defaultCacheFile;

  static const _retryKey = 'pass_next_request_at_v1';
  final FlutterSecureStorage _storage;
  final Future<File> Function() _cacheFile;
  Future<void> _writes = Future.value();

  static Future<File> _defaultCacheFile() async {
    final directory = await getApplicationCacheDirectory();
    return File('${directory.path}/pass-cache-v1.json');
  }

  @override
  Future<CachedPass?> readPass() async {
    await _writes;
    final file = await _cacheFile();
    if (!await file.exists()) return null;
    if (await file.length() > 6 * 1024 * 1024) return null;
    try {
      return CachedPass.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  Future<void> writePass(CachedPass? pass) {
    final next = _writes.then((_) async {
      final file = await _cacheFile();
      if (pass == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.tmp');
      await pending.writeAsString(jsonEncode(pass.toJson()), flush: true);
      await pending.rename(file.path);
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<DateTime?> readRetryAt() async {
    final value = await _storage.read(key: _retryKey);
    if (value == null) return null;
    // Invalid throttle data must never enable another network request.
    return DateTime.fromMillisecondsSinceEpoch(int.parse(value));
  }

  @override
  Future<void> writeRetryAt(DateTime value) =>
      _storage.write(key: _retryKey, value: '${value.millisecondsSinceEpoch}');
}

class PassRepository {
  PassRepository({
    RocketChatClient? client,
    PassStore? store,
    DateTime Function()? now,
  }) : _client = client ?? RocketChatClient(),
       _store = store ?? LocalPassStore(),
       now = now ?? DateTime.now;

  static const minimumInterval = Duration(seconds: 30);
  static const _requestTimeout = Duration(seconds: 30);
  static const _fallbackLifetime = Duration(seconds: 30);
  final RocketChatClient _client;
  final PassStore _store;
  final DateTime Function() now;
  Future<void>? _initializing;
  Future<CachedPass>? _request;
  String? _requestOwner;
  CachedPass? _pass;
  DateTime? nextRequestAt;
  bool cachePersisted = true;

  Future<void> _initialize() => _initializing ??= (() async {
    nextRequestAt = await _store.readRetryAt();
    _pass = await _store.readPass();
  })();

  /// Restoration never opens a socket, including for an expired/missing cache.
  Future<CachedPass?> restore(String token) async {
    await _initialize();
    final pass = _pass;
    return pass != null &&
            pass.owner == CachedPass.ownerFor(token) &&
            pass.isValidAt(now())
        ? pass
        : null;
  }

  Future<void> clearPass() async {
    await _initialize();
    _pass = null;
    await _store.writePass(null);
    // Account changes and expiry never reset the request deadline.
  }

  Future<void> _setRetryAt(DateTime value) async {
    nextRequestAt = value;
    await _store.writeRetryAt(value);
  }

  Future<CachedPass> request(String token) {
    final owner = CachedPass.ownerFor(token);
    final pending = _request;
    if (pending != null) {
      if (_requestOwner == owner) return pending;
      return Future.error(
        PassException(PassError.rateLimit, retryAt: nextRequestAt),
      );
    }
    _requestOwner = owner;
    return _request = _fetch(token, owner).whenComplete(() {
      _request = null;
      _requestOwner = null;
    });
  }

  Future<CachedPass> _fetch(String token, String owner) async {
    await _initialize();
    final retry = nextRequestAt;
    if (retry != null && now().isBefore(retry)) {
      throw PassException(PassError.rateLimit, retryAt: retry);
    }
    // Persist BEFORE any network traffic. Reserve the request timeout too: if
    // the process dies mid-request, relaunching cannot immediately hit the bot.
    await _setRetryAt(now().add(_requestTimeout + minimumInterval));
    QrPass response;
    try {
      response = await _client.requestPass(token).timeout(_requestTimeout);
    } catch (error) {
      var retry = now().add(minimumInterval);
      if (error is PassException &&
          error.retryAt != null &&
          error.retryAt!.isAfter(retry)) {
        retry = error.retryAt!;
      }
      await _setRetryAt(retry);
      if (error is TimeoutException) {
        throw const PassException(PassError.timeout);
      }
      if (error is PassException && error.kind == PassError.rateLimit) {
        throw PassException(PassError.rateLimit, retryAt: retry);
      }
      rethrow;
    }
    final received = now();
    final pass = CachedPass(
      owner: owner,
      image: response.image,
      receivedAt: received,
      expiresAt: response.expiresOn ?? received.add(_fallbackLifetime),
      expiresOn: response.expiresOn,
    );
    await _setRetryAt(received.add(minimumInterval));
    if (!pass.isValidAt(received)) {
      throw const PassException(PassError.response);
    }
    _pass = pass;
    try {
      await _store.writePass(pass);
      cachePersisted = true;
    } catch (_) {
      // A cache failure must not discard an otherwise usable QR. The request
      // deadline has already been saved independently above.
      cachePersisted = false;
    }
    return pass;
  }
}
