import 'dart:convert';

import 'package:flutter/foundation.dart';

enum TraceTransport { http, webSocket, app }

class RequestEvent {
  const RequestEvent({
    required this.id,
    required this.time,
    required this.transport,
    required this.title,
    required this.url,
    required this.status,
    this.incoming = false,
    this.failed = false,
    this.durationMs,
    this.request,
    this.response,
  });

  final int id;
  final DateTime time;
  final TraceTransport transport;
  final String title;
  final String url;
  final String status;
  final bool incoming;
  final bool failed;
  final int? durationMs;
  // Only sanitized, bounded strings reach the retained log.
  final String? request;
  final String? response;

  String get details => const JsonEncoder.withIndent('  ').convert({
    'event': id,
    'time': time.toIso8601String(),
    'transport': transport.name,
    'direction': incoming ? 'incoming' : 'outgoing',
    'operation': title,
    if (url.isNotEmpty) 'url': url,
    'status': status,
    if (durationMs != null) 'durationMs': durationMs,
    if (request != null) 'request': jsonDecode(request!),
    if (response != null) 'response': jsonDecode(response!),
  });
}

class RequestLog extends ChangeNotifier {
  RequestLog({this.capacity = 200});

  static final instance = RequestLog();
  final int capacity;
  final _events = <RequestEvent>[];
  final _pendingWs = <String, Stopwatch>{};
  int _sequence = 0;
  int httpRequests = 0;
  int webSocketMethods = 0;
  int totalEvents = 0;
  int errors = 0;

  List<RequestEvent> get events => List.unmodifiable(_events.reversed);

  int beginHttp(Uri uri, String method, {Object? headers, Object? body}) {
    httpRequests++;
    final event = RequestEvent(
      id: ++_sequence,
      time: DateTime.now(),
      transport: TraceTransport.http,
      title: method,
      url: safeUrl(uri),
      status: 'Ожидание',
      request: _encode({'headers': headers, 'body': body}),
    );
    _append(event);
    return event.id;
  }

  void endHttp(
    int id, {
    int? statusCode,
    Object? response,
    String? failure,
    int? durationMs,
    bool challenge = false,
  }) {
    final index = _events.indexWhere((event) => event.id == id);
    if (index < 0) return;
    final old = _events[index];
    final failed =
        failure != null ||
        (!challenge &&
            statusCode != null &&
            (statusCode < 200 || statusCode >= 300));
    if (failed && !old.failed) errors++;
    _events[index] = RequestEvent(
      id: old.id,
      time: old.time,
      transport: old.transport,
      title: old.title,
      url: old.url,
      request: old.request,
      response: _encode(response),
      status: failure != null
          ? '${statusCode == null ? '' : 'HTTP $statusCode · '}Ошибка · ${_safeCategory(failure)}'
          : challenge
          ? 'HTTP $statusCode · подтверждение'
          : 'HTTP $statusCode',
      failed: failed,
      durationMs: durationMs,
    );
    notifyListeners();
  }

  void webSocketFrame(
    Uri uri,
    Map<String, dynamic> frame, {
    required bool incoming,
  }) {
    final type = frame['msg'];
    const types = {
      'connect',
      'connected',
      'method',
      'ping',
      'pong',
      'sub',
      'ready',
      'nosub',
      'changed',
      'result',
      'failed',
      'added',
      'removed',
      'updated',
      'error',
    };
    final safeType = types.contains(type) ? type as String : 'frame';
    const methods = {'login', 'createDirectMessage', 'slashCommand'};
    final method = methods.contains(frame['method'])
        ? frame['method'] as String
        : null;
    const ids = {'login', 'dm', 'enter', 'room'};
    final id = ids.contains(frame['id']) ? frame['id'] as String : null;
    final key = '${safeUrl(uri)}|$id';
    int? durationMs;
    if (!incoming && type == 'method' && id != null) {
      _pendingWs[key] = Stopwatch()..start();
    } else if (incoming && type == 'result' && id != null) {
      final timer = _pendingWs.remove(key);
      timer?.stop();
      durationMs = timer?.elapsedMilliseconds;
    }
    if (!incoming && type == 'method') webSocketMethods++;
    final failed =
        frame['error'] != null ||
        type == 'failed' ||
        type == 'nosub' ||
        type == 'error';
    _append(
      RequestEvent(
        id: ++_sequence,
        time: DateTime.now(),
        transport: TraceTransport.webSocket,
        title: [safeType, ?(method ?? id)].join(' · '),
        url: safeUrl(uri),
        status: incoming ? 'Получено' : 'Отправлено',
        incoming: incoming,
        failed: failed,
        durationMs: durationMs,
        request: incoming ? null : _encode(frame),
        response: incoming ? _encode(frame) : null,
      ),
    );
  }

  void webSocketState(
    Uri uri,
    String state, {
    bool failed = false,
    int? durationMs,
  }) {
    if (state == 'closed') {
      final prefix = '${safeUrl(uri)}|';
      for (final key
          in _pendingWs.keys.where((key) => key.startsWith(prefix)).toList()) {
        _pendingWs.remove(key)?.stop();
      }
    }
    _append(
      RequestEvent(
        id: ++_sequence,
        time: DateTime.now(),
        transport: TraceTransport.webSocket,
        title: 'Соединение',
        url: safeUrl(uri),
        status: _safeCategory(state),
        failed: failed,
        durationMs: durationMs,
      ),
    );
  }

  void credentialSaved({required bool success}) {
    _append(
      RequestEvent(
        id: ++_sequence,
        time: DateTime.now(),
        transport: TraceTransport.app,
        title: 'Защищённое хранилище',
        url: '',
        status: success ? 'Токен сохранён' : 'Не удалось сохранить токен',
        failed: !success,
      ),
    );
  }

  void clear() {
    for (final timer in _pendingWs.values) {
      timer.stop();
    }
    _pendingWs.clear();
    _events.clear();
    httpRequests = 0;
    webSocketMethods = 0;
    totalEvents = 0;
    errors = 0;
    notifyListeners();
  }

  void _append(RequestEvent event) {
    _events.add(event);
    totalEvents++;
    if (event.failed) errors++;
    if (_events.length > capacity) _events.removeAt(0);
    notifyListeners();
  }

  static String _safeCategory(String value) {
    const values = {
      'connected',
      'closed',
      'opening',
      'network',
      'timeout',
      'response',
      'authorization',
      'bot',
      'credentials',
      'forbidden',
      'rateLimit',
      'storage',
      'invalid-json',
      'cancelled',
    };
    return values.contains(value) ? value : 'unknown';
  }

  static String safeUrl(Uri uri) {
    final path = uri.path.startsWith('/file-upload/')
        ? '/file-upload/redacted'
        : uri.path;
    return uri
        .replace(
          userInfo: '',
          path: path,
          fragment: '',
          queryParameters: uri.hasQuery
              ? {for (final key in uri.queryParameters.keys) key: 'redacted'}
              : null,
        )
        .toString()
        .split('#')
        .first;
  }

  static String _encode(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(sanitize(value));

  static Object? sanitize(Object? value, {String key = '', int depth = 0}) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    const identities = {
      'user',
      'username',
      'login',
      'email',
      'emails',
      'userid',
      'xuserid',
      'rcuid',
      'u',
      'me',
      'name',
      'realname',
      'displayname',
      'rid',
    };
    if (identities.contains(normalized) ||
        normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('authorization') ||
        normalized.contains('cookie') ||
        normalized.contains('digest') ||
        normalized.contains('hash') ||
        normalized == 'resume' ||
        normalized == 'code' ||
        normalized == 'x2facode') {
      return '[скрыто]';
    }
    if (depth >= 8) return '[глубина ограничена]';
    if (value is Uint8List || value is List<int> && value.length > 32) {
      return '[бинарные данные скрыты]';
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries.take(40)) {
        final name = entry.key.toString();
        result[name] = sanitize(entry.value, key: name, depth: depth + 1);
      }
      if (value.length > 40) result['truncatedFields'] = value.length - 40;
      return result;
    }
    if (value is List) {
      return [
        ...value
            .take(12)
            .map((item) => sanitize(item, key: key, depth: depth + 1)),
        if (value.length > 12) '[ещё ${value.length - 12} элементов]',
      ];
    }
    if (value is String) {
      if (value.contains('data:image/') ||
          RegExp(r'^[A-Za-z0-9+/_=-]{96,}$').hasMatch(value)) {
        return '[изображение или длинное содержимое скрыто]';
      }
      if (normalized == 'msg') {
        const types = {
          'connect',
          'connected',
          'method',
          'ping',
          'pong',
          'sub',
          'ready',
          'nosub',
          'changed',
          'result',
          'failed',
          'added',
          'removed',
          'updated',
          'error',
        };
        return types.contains(value) ? value : '[текст сообщения скрыт]';
      }
      if (normalized == 'id') {
        return const {'login', 'dm', 'enter', 'room'}.contains(value)
            ? value
            : '[скрыто]';
      }
      if (normalized == 'url' ||
          normalized == 'imageurl' ||
          normalized == 'location') {
        final uri = Uri.tryParse(value);
        return uri == null ? '[адрес скрыт]' : safeUrl(uri);
      }
      // Preserve protocol metadata. Unknown free text is never retained: servers
      // may echo credentials in error messages or embed a QR in a bot message.
      const metadata = {
        'method',
        'algorithm',
        'collection',
        'cmd',
        'status',
        'type',
        'state',
        'stage',
        'kind',
        'errortype',
        'contenttype',
        'x2famethod',
        'imagetype',
        'availablemethods',
        'support',
        'version',
      };
      if (metadata.contains(normalized) ||
          const {
            'qr-code-generator.bot',
            'stream-room-messages',
            '1',
            'pre1',
            'pre2',
            '',
          }.contains(value)) {
        return value.length > 160 ? '${value.substring(0, 160)}…' : value;
      }
      return '[содержимое скрыто]';
    }
    if (value == null || value is num || value is bool) return value;
    return '[данные скрыты]';
  }
}
