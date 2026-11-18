import 'dart:io';

import 'package:debug_browser/core/downloads.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('file names', () {
    test('RFC 6266 filename* (UTF-8) wins over filename', () {
      expect(
        fileNameFromContentDisposition("attachment; filename=\"fallback.pdf\"; filename*=UTF-8''r%C3%A9sum%C3%A9.pdf"),
        'résumé.pdf',
      );
      expect(fileNameFromContentDisposition('attachment; filename="report 2026.xlsx"'), 'report 2026.xlsx');
      expect(fileNameFromContentDisposition('attachment; filename=plain.txt'), 'plain.txt');
      expect(fileNameFromContentDisposition('inline'), isNull);
      expect(fileNameFromContentDisposition(null), isNull);
    });

    test('suggestFileName falls back to URL, then MIME extension', () {
      expect(suggestFileName('https://x.test/files/a%20b.zip?sig=1', null, null), 'a b.zip');
      expect(suggestFileName('https://x.test/export', null, 'application/pdf'), 'export.pdf');
      expect(suggestFileName('https://x.test/', null, 'image/png; charset=binary'), 'download.png');
    });

    test('sanitizeFileName blocks traversal and reserved characters', () {
      final n = suggestFileName('https://x.test/', 'attachment; filename="../../etc/passwd"', null);
      expect(n.contains('/'), isFalse);
      expect(n.contains('..'), isFalse);
      expect(sanitizeFileName(r'a:b*c?"d<e>f|g\h.txt'), 'a_b_c__d_e_f_g_h.txt');
      expect(sanitizeFileName('...'), 'download');
      final long = sanitizeFileName('${'x' * 300}.pdf');
      expect(long.length, 150);
      expect(long, endsWith('.pdf'));
    });
  });

  test('looksLikePage: HTML is a page unless sent as an attachment', () {
    expect(looksLikePage('text/html', null), isTrue);
    expect(looksLikePage('text/html', 'attachment; filename=a.html'), isFalse);
    expect(looksLikePage('application/pdf', null), isFalse);
    expect(looksLikePage(null, null), isFalse);
  });

  test('DownloadItem JSON: a running download restores as interrupted', () {
    final d = DownloadItem(id: '1', url: 'https://a/b.zip', fileName: 'b.zip', startedAt: DateTime.utc(2026));
    final back = DownloadItem.fromJson(d.toJson())!;
    expect(back.status, DownloadStatus.failed);
    expect(back.error, 'Interrupted');
    expect(DownloadItem.fromJson('junk'), isNull);
  });

  group('download probe against a real HTTP server', () {
    late HttpServer server;
    late ProviderContainer container;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final r = req.response;
        switch (req.uri.path) {
          case '/page':
            r.headers.contentType = ContentType.html;
            r.write('<html>hi</html>');
          case '/missing':
            r.statusCode = 404;
            r.headers.contentType = ContentType.binary;
          default:
            r.statusCode = 500;
        }
        r.close();
      });
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await server.close(force: true);
    });

    test('an ordinary page is not downloaded (caller opens it instead)', () async {
      final ok = await container
          .read(downloadsProvider.notifier)
          .start('http://127.0.0.1:${server.port}/page');
      expect(ok, isFalse);
      expect(container.read(downloadsProvider), isEmpty);
    });

    test('an HTTP error is recorded as a failed download', () async {
      final ok = await container
          .read(downloadsProvider.notifier)
          .start('http://127.0.0.1:${server.port}/missing');
      expect(ok, isTrue);
      final item = container.read(downloadsProvider).single;
      expect(item.status, DownloadStatus.failed);
      expect(item.error, 'HTTP 404');
      expect(item.fileName, 'missing');
    });

    test('unsupported schemes are rejected', () async {
      expect(await container.read(downloadsProvider.notifier).start('ftp://x/y'), isFalse);
    });
  });
}
