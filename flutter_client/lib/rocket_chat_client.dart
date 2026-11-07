import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'request_log.dart';

enum PassError { authorization, network, timeout, bot, response, rateLimit }

class PassException implements Exception {
  const PassException(this.kind, {this.retryAt});

  final PassError kind;
  final DateTime? retryAt;
}

typedef QrPass = ({Uint8List image, DateTime? expiresOn});

class RocketChatClient {
  RocketChatClient({Uri? endpoint})
    : endpoint =
          endpoint ??
          Uri.parse('wss://rocketchat-student.21-school.ru/websocket');

  final Uri endpoint;

  Future<QrPass> requestPass(String token) async {
    final traceTimer = Stopwatch()..start();
    RequestLog.instance.webSocketState(endpoint, 'opening');
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    WebSocket? socket;
    var cancelled = false;
    try {
      final opening = WebSocket.connect(endpoint.toString(), customClient: http)
          .then((connection) {
            if (cancelled) {
              unawaited(connection.close());
              throw const PassException(PassError.timeout);
            }
            return connection;
          });
      socket = await opening.timeout(const Duration(seconds: 8));
      RequestLog.instance.webSocketState(endpoint, 'connected');
      final connection = socket;
      void send(Map<String, Object?> message) {
        RequestLog.instance.webSocketFrame(endpoint, message, incoming: false);
        connection.add(jsonEncode(message));
      }

      void method(String id, String name, List<Object> params) =>
          send({'msg': 'method', 'id': id, 'method': name, 'params': params});

      final reply = Completer<QrPass>();
      DateTime? expiresOn;
      Uint8List? image;
      Timer? expiryWait;
      var receivingImage = false;
      void completePass() {
        if (!reply.isCompleted && image != null) {
          reply.complete((image: image!, expiresOn: expiresOn));
        }
      }

      void receiveImage(Future<Uint8List> download) {
        receivingImage = true;
        unawaited(
          download.then(
            (bytes) {
              if (reply.isCompleted) return;
              image = bytes;
              if (expiresOn != null) {
                completePass();
              } else {
                expiryWait = Timer(const Duration(seconds: 2), completePass);
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!reply.isCompleted) reply.completeError(error, stack);
            },
          ),
        );
      }

      String? room;
      String? userId;
      var commandSent = false;
      final subscription = connection.listen(
        (frame) {
          if (reply.isCompleted || frame is! String) return;
          try {
            final message = jsonDecode(frame);
            if (message is! Map<String, dynamic>) return;
            RequestLog.instance.webSocketFrame(
              endpoint,
              message,
              incoming: true,
            );
            final limited = _rateLimitError(message['error']);
            if (limited != null) throw limited;
            switch (message['msg']) {
              case 'ping':
                send({
                  'msg': 'pong',
                  if (message.containsKey('id')) 'id': message['id'],
                });
              case 'connected':
                method('login', 'login', [
                  {'resume': token},
                ]);
              case 'failed':
                throw const PassException(PassError.response);
              case 'result':
                switch (message['id']) {
                  case 'login':
                    if (message['error'] != null) {
                      throw const PassException(PassError.authorization);
                    }
                    final result = message['result'];
                    final id = result is Map ? result['id'] : null;
                    if (id is String) userId = id;
                    method('dm', 'createDirectMessage', [
                      'qr-code-generator.bot',
                    ]);
                  case 'dm':
                    final result = message['result'];
                    if (message['error'] != null ||
                        result is! Map ||
                        result['rid'] is! String ||
                        (result['rid'] as String).isEmpty) {
                      throw const PassException(PassError.bot);
                    }
                    room = result['rid'] as String;
                    send({
                      'msg': 'sub',
                      'id': 'room',
                      'name': 'stream-room-messages',
                      'params': [room, true],
                    });
                  case 'enter':
                    if (message['error'] != null) {
                      throw const PassException(PassError.bot);
                    }
                }
              case 'ready':
                final subs = message['subs'];
                if (room != null &&
                    !commandSent &&
                    subs is List &&
                    subs.contains('room')) {
                  commandSent = true;
                  method('enter', 'slashCommand', [
                    {
                      'cmd': 'enter',
                      'params': '',
                      'msg': {'rid': room},
                    },
                  ]);
                }
              case 'nosub':
                if (message['id'] == 'room') {
                  throw const PassException(PassError.bot);
                }
              case 'changed':
                if (!commandSent ||
                    message['collection'] != 'stream-room-messages') {
                  return;
                }
                final fields = message['fields'];
                final args = fields is Map ? fields['args'] : null;
                final event = args is List && args.isNotEmpty
                    ? args.first
                    : null;
                if (event is! Map ||
                    (event['rid'] ?? fields['eventName']) != room) {
                  return;
                }
                final sender = event['u'];
                if (sender is Map &&
                    sender['username'] != 'qr-code-generator.bot') {
                  return;
                }
                final body = event['msg'];
                if (body is String) {
                  final date = _readExpiryDate(body);
                  if (date != null) {
                    expiresOn = date;
                    completePass();
                  }
                  final encoded = RegExp(
                    r'data:image/png;base64,([A-Za-z0-9+/]+={0,2})',
                  ).firstMatch(body)?.group(1);
                  if (encoded != null && !receivingImage) {
                    receiveImage(
                      Future.value(_validatePng(base64Decode(encoded))),
                    );
                    return;
                  }
                }

                final attachments = event['attachments'];
                if (receivingImage ||
                    attachments is! List ||
                    sender is! Map ||
                    sender['username'] != 'qr-code-generator.bot') {
                  return;
                }
                for (final attachment in attachments) {
                  if (attachment is! Map ||
                      attachment['image_type'] != 'image/png') {
                    continue;
                  }
                  final url = attachment['image_url'];
                  if (url is! String || url.isEmpty) continue;
                  final id = userId;
                  if (id == null) throw const PassException(PassError.response);
                  receiveImage(_downloadPng(http, url, token, id));
                  return;
                }
            }
          } on PassException catch (error) {
            reply.completeError(error);
          } on FormatException {
            reply.completeError(const PassException(PassError.response));
          }
        },
        onError: (Object error) {
          if (!reply.isCompleted) {
            reply.completeError(const PassException(PassError.network));
          }
        },
        onDone: () {
          if (!reply.isCompleted) {
            reply.completeError(const PassException(PassError.network));
          }
        },
      );
      try {
        send({
          'msg': 'connect',
          'version': '1',
          'support': ['1', 'pre2', 'pre1'],
        });
        return await reply.future.timeout(const Duration(seconds: 15));
      } finally {
        expiryWait?.cancel();
        await subscription.cancel();
      }
    } on TimeoutException {
      RequestLog.instance.webSocketState(endpoint, 'timeout', failed: true);
      throw const PassException(PassError.timeout);
    } on WebSocketException catch (error) {
      final limited = error.httpStatusCode == HttpStatus.tooManyRequests;
      RequestLog.instance.webSocketState(
        endpoint,
        limited ? 'rateLimit' : 'network',
        failed: true,
      );
      throw PassException(limited ? PassError.rateLimit : PassError.network);
    } on IOException {
      RequestLog.instance.webSocketState(endpoint, 'network', failed: true);
      throw const PassException(PassError.network);
    } on PassException catch (failure) {
      RequestLog.instance.webSocketState(
        endpoint,
        failure.kind.name,
        failed: true,
      );
      rethrow;
    } finally {
      traceTimer.stop();
      RequestLog.instance.webSocketState(
        endpoint,
        'closed',
        durationMs: traceTimer.elapsedMilliseconds,
      );
      cancelled = true;
      http.close(force: true);
      if (socket != null) unawaited(socket.close());
    }
  }

  PassException? _rateLimitError(Object? error) {
    if (error is! Map) return null;
    final code = '${error['error'] ?? error['errorType'] ?? ''}'.toLowerCase();
    if (code != '429' &&
        code != 'too-many-requests' &&
        code != 'error-too-many-requests') {
      return null;
    }
    Object? details = error['details'];
    if (details is String) {
      try {
        details = jsonDecode(details);
      } on FormatException {
        details = null;
      }
    }
    final delay = details is Map ? details['timeToReset'] : null;
    return PassException(
      PassError.rateLimit,
      retryAt: delay is num && delay.isFinite && delay > 0
          ? DateTime.now().add(Duration(milliseconds: delay.ceil()))
          : null,
    );
  }

  DateTime? _httpRetryAt(HttpHeaders headers) {
    DateTime? deadline;
    final retry = headers.value(HttpHeaders.retryAfterHeader);
    if (retry != null) {
      final seconds = int.tryParse(retry);
      if (seconds != null && seconds >= 0) {
        deadline = DateTime.now().add(Duration(seconds: seconds));
      } else {
        try {
          deadline = HttpDate.parse(retry);
        } on FormatException {
          /* Ignore invalid date. */
        }
      }
    }
    final reset = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
    if (reset != null) {
      // Rocket.Chat specifies UTC epoch milliseconds for this header.
      final candidate = DateTime.fromMillisecondsSinceEpoch(reset);
      if (deadline == null || candidate.isAfter(deadline)) deadline = candidate;
    }
    return deadline;
  }

  DateTime? _readExpiryDate(String body) {
    final match = RegExp(
      r'^The QR code will expire on (\d{2})\.(\d{2})\.(\d{4})\.?$',
    ).firstMatch(body.trim());
    if (match == null) return null;
    final day = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final year = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  Future<Uint8List> _downloadPng(
    HttpClient http,
    String url,
    String token,
    String userId,
  ) async {
    final origin = endpoint.replace(
      scheme: endpoint.scheme == 'wss' ? 'https' : 'http',
    );
    final image = origin.resolve(url);
    if (image.origin != origin.origin ||
        image.userInfo.isNotEmpty ||
        !image.path.startsWith('/file-upload/')) {
      throw const PassException(PassError.response);
    }
    final timer = Stopwatch()..start();
    final trace = RequestLog.instance.beginHttp(
      image,
      'GET',
      headers: {
        'X-Auth-Token': token,
        'X-User-Id': userId,
        'Cookie': '[скрыто]',
      },
    );
    int? traceStatus;
    try {
      final request = await http.getUrl(image);
      request.followRedirects = false;
      request.headers.set('X-Auth-Token', token);
      request.headers.set('X-User-Id', userId);
      request.cookies.addAll([
        Cookie('rc_token', token),
        Cookie('rc_uid', userId),
      ]);
      final response = await request.close();
      traceStatus = response.statusCode;
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw PassException(
          PassError.rateLimit,
          retryAt: _httpRetryAt(response.headers),
        );
      }
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const PassException(PassError.authorization);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const PassException(PassError.response);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const PassException(PassError.response);
        }
      }
      final png = _validatePng(bytes.takeBytes());
      RequestLog.instance.endHttp(
        trace,
        statusCode: traceStatus,
        response: {
          'Content-Type': response.headers.contentType?.toString(),
          'bytes': png.length,
          'pngValid': true,
        },
        durationMs: timer.elapsedMilliseconds,
      );
      return png;
    } on PassException catch (failure) {
      RequestLog.instance.endHttp(
        trace,
        statusCode: traceStatus,
        failure: failure.kind.name,
        durationMs: timer.elapsedMilliseconds,
      );
      rethrow;
    } on IOException {
      RequestLog.instance.endHttp(
        trace,
        statusCode: traceStatus,
        failure: 'network',
        durationMs: timer.elapsedMilliseconds,
      );
      rethrow;
    } finally {
      timer.stop();
    }
  }

  Uint8List _validatePng(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length <= signature.length ||
        !Iterable<int>.generate(signature.length)
            .every((index) => bytes[index] == signature[index])) {
      throw const PassException(PassError.response);
    }
    return bytes;
  }
}
