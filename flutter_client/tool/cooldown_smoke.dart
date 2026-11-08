// Run with --debug --target tool/cooldown_smoke.dart. All requests, credentials
// and QR state are synthetic and in memory; no Rocket.Chat or native stores.
import 'package:campus_pass/pass_appearance.dart';
import 'package:campus_pass/pass_home.dart';
import 'package:campus_pass/pass_repository.dart';
import 'package:campus_pass/pass_theme.dart';
import 'package:campus_pass/rocket_chat_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'widget_smoke.dart' as fixture;

class _MemoryStore implements PassStore {
  CachedPass? pass;
  DateTime? retryAt;
  @override
  Future<CachedPass?> readPass() async => pass;
  @override
  Future<DateTime?> readRetryAt() async => retryAt;
  @override
  Future<void> writePass(CachedPass? value) async => pass = value;
  @override
  Future<void> writeRetryAt(DateTime value) async => retryAt = value;
}

class _FixtureClient extends RocketChatClient {
  int requests = 0;
  @override
  Future<QrPass> requestPass(String token) async {
    requests++;
    return (
      image: fixture.image,
      expiresOn: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

void main() {
  if (!kDebugMode) throw StateError('Use the debug build for this smoke test');
  runApp(MaterialApp(theme: passTheme(), home: const _CooldownSmoke()));
}

class _CooldownSmoke extends StatefulWidget {
  const _CooldownSmoke();
  @override
  State<_CooldownSmoke> createState() => _CooldownSmokeState();
}

class _CooldownSmokeState extends State<_CooldownSmoke> {
  final client = _FixtureClient();
  late final passes = PassRepository(client: client, store: _MemoryStore());
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await passes.request('synthetic-smoke-token');
    } on PassException {
      error = 'Запрос заблокирован';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'ТЕСТ • Запросов: ${client.requests}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Expanded(
          child: PassHome(
            appearance: const PassAppearance(backdrop: PassBackdrop.solid),
            loading: loading,
            error: error,
            qr: Image.memory(
              fixture.image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
            nextRequestAt: passes.nextRequestAt,
            onRefresh: refresh,
            onConnect: () {},
            onSettings: () {},
          ),
        ),
      ],
    ),
  );
}
