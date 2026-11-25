import 'package:debug_browser/core/providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ConsoleLog log(String m, [String level = 'log']) => ConsoleLog(level: level, message: m, timestamp: DateTime.utc(2026));

void main() {
  test('appendAllCapped keeps the newest entries in one copy', () {
    expect(appendAllCapped([1, 2, 3], [4, 5], 4), [2, 3, 4, 5]);
    expect(appendAllCapped([1, 2], [3], 10), [1, 2, 3]);
    expect(appendAllCapped([1, 2], [3, 4, 5, 6], 3), [4, 5, 6]);
    expect(appendAllCapped(<int>[], <int>[], 3), isEmpty);
  });

  test('page logs are published together, at most every 100 ms', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      var updates = 0;
      c.listen(consoleLogsProvider, (_, __) => updates++);
      final n = c.read(consoleLogsProvider.notifier);
      for (var i = 0; i < 300; i++) {
        n.addLog(log('line $i'));
      }
      expect(c.read(consoleLogsProvider), isEmpty, reason: 'not yet published');
      async.elapse(const Duration(milliseconds: 120));
      expect(c.read(consoleLogsProvider).length, 300);
      expect(updates, 1, reason: 'one redraw for 300 lines');
      c.dispose();
    });
  });

  test('REPL input and results show immediately; clear drops pending lines', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      final n = c.read(consoleLogsProvider.notifier);
      n.addLog(log('page'));
      n.addLog(log('1+1', 'input'));
      expect(c.read(consoleLogsProvider).map((l) => l.message), ['page', '1+1'], reason: 'input flushes what was queued');
      n.addLog(log('pending'));
      n.clear();
      async.elapse(const Duration(milliseconds: 200));
      expect(c.read(consoleLogsProvider), isEmpty);
      c.dispose();
    });
  });

  test('cap still applies to batched logs and requests; flush publishes now', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      final n = c.read(consoleLogsProvider.notifier);
      for (var i = 0; i < maxConsoleLogs + 50; i++) {
        n.addLog(log('$i'));
      }
      n.flush();
      expect(c.read(consoleLogsProvider).length, maxConsoleLogs);
      expect(c.read(consoleLogsProvider).last.message, '${maxConsoleLogs + 49}');

      final r = c.read(networkRequestsProvider.notifier);
      r.addRequest(NetworkRequest(type: 'fetch', url: 'https://a.test', method: 'GET', status: 200, duration: 1, timestamp: DateTime.utc(2026)));
      expect(c.read(networkRequestsProvider), isEmpty);
      r.flush();
      expect(c.read(networkRequestsProvider).single.url, 'https://a.test');
      c.dispose();
    });
  });
}
