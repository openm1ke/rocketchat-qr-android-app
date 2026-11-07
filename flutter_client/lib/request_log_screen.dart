import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'request_log.dart';

enum _LogFilter { all, http, webSocket, errors }

class RequestLogScreen extends StatefulWidget {
  const RequestLogScreen({super.key, this.log});
  final RequestLog? log;

  @override
  State<RequestLogScreen> createState() => _RequestLogScreenState();
}

class _RequestLogScreenState extends State<RequestLogScreen> {
  late final _log = widget.log ?? RequestLog.instance;
  _LogFilter _filter = _LogFilter.all;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал запросов'),
        actions: [
          IconButton(
            tooltip: 'Очистить журнал',
            onPressed: _log.clear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _log,
          builder: (context, _) {
            final entries = _log.events
                .where(
                  (entry) => switch (_filter) {
                    _LogFilter.all => true,
                    _LogFilter.http => entry.transport == TraceTransport.http,
                    _LogFilter.webSocket =>
                      entry.transport == TraceTransport.webSocket,
                    _LogFilter.errors => entry.failed,
                  },
                )
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          _counter('HTTP', _log.httpRequests),
                          _counter('Методы WS', _log.webSocketMethods),
                          _counter('События с ошибкой', _log.errors),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Последние ${_log.capacity} событий · только в памяти',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Логины, пароли, коды 2FA, токены и содержимое QR скрыты.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final filter in _LogFilter.values)
                            ChoiceChip(
                              label: Text(switch (filter) {
                                _LogFilter.all => 'Все',
                                _LogFilter.http => 'HTTP',
                                _LogFilter.webSocket => 'WebSocket',
                                _LogFilter.errors => 'Ошибки',
                              }),
                              selected: filter == _filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _log.events.isEmpty
                                  ? 'Запросов пока нет. Получите QR или подключитесь к Rocket.Chat — события появятся здесь.'
                                  : 'Для этого фильтра событий нет.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _event(entries[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _counter(String label, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$value',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _event(RequestEvent entry) {
    final colors = Theme.of(context).colorScheme;
    final time = entry.time;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    final transport = switch (entry.transport) {
      TraceTransport.http => 'HTTP',
      TraceTransport.webSocket => 'WS',
      TraceTransport.app => 'APP',
    };
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey(entry.id),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          '$transport ${entry.incoming ? '←' : '→'} ${entry.title}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$stamp · ${entry.status}${entry.durationMs == null ? '' : ' · ${entry.durationMs} мс'}',
                style: TextStyle(
                  fontSize: 12,
                  color: entry.failed ? colors.error : colors.onSurfaceVariant,
                ),
              ),
              if (entry.url.isNotEmpty)
                Text(
                  entry.url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: entry.details),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Запись скопирована. Секретные данные скрыты.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Копировать запись'),
                  ),
                ),
                SelectableText(
                  entry.details,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
