import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';
import 'shared_downloads.dart';

enum DownloadStatus { running, completed, failed, cancelled }

@immutable
class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  final String? path;

  /// content:// URI in the shared Downloads folder (Android 10+).
  final String? contentUri;
  final String? mimeType;
  final int received;
  final int total; // -1 when unknown
  final DownloadStatus status;
  final String? error;
  final DateTime startedAt;

  const DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    this.path,
    this.contentUri,
    this.mimeType,
    this.received = 0,
    this.total = -1,
    this.status = DownloadStatus.running,
    this.error,
    required this.startedAt,
  });

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  /// Whether the file is available to open/share.
  bool get hasFile => contentUri != null || path != null;

  DownloadItem copyWith({
    String? fileName,
    String? path,
    String? Function()? contentUri,
    String? mimeType,
    int? received,
    int? total,
    DownloadStatus? status,
    String? error,
  }) =>
      DownloadItem(
        id: id,
        url: url,
        fileName: fileName ?? this.fileName,
        path: path ?? this.path,
        contentUri: contentUri != null ? contentUri() : this.contentUri,
        mimeType: mimeType ?? this.mimeType,
        received: received ?? this.received,
        total: total ?? this.total,
        status: status ?? this.status,
        error: error ?? this.error,
        startedAt: startedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'path': path,
        'contentUri': contentUri,
        'mimeType': mimeType,
        'received': received,
        'total': total,
        'status': status.name,
        'error': error,
        'startedAt': startedAt.toIso8601String(),
      };

  static DownloadItem? fromJson(Object? j) {
    if (j is! Map || j['id'] == null) return null;
    var status = DownloadStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => DownloadStatus.failed);
    String? error = j['error']?.toString();
    // A download that was running when the app closed can't resume.
    if (status == DownloadStatus.running) {
      status = DownloadStatus.failed;
      error = 'Interrupted';
    }
    int asInt(Object? v, int d) => v is num ? v.toInt() : d;
    return DownloadItem(
      id: '${j['id']}',
      url: '${j['url'] ?? ''}',
      fileName: '${j['fileName'] ?? 'download'}',
      path: j['path']?.toString(),
      contentUri: j['contentUri']?.toString(),
      mimeType: j['mimeType']?.toString(),
      received: asInt(j['received'], 0),
      total: asInt(j['total'], -1),
      status: status,
      error: error,
      startedAt: DateTime.tryParse('${j['startedAt']}') ?? DateTime.now(),
    );
  }
}

/// Strips path separators and reserved characters so a server-supplied name
/// can never escape the download folder.
String sanitizeFileName(String name, {String fallback = 'download'}) {
  var s = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\.{2,}'), '.')
      .trim()
      .replaceFirst(RegExp(r'^[.\s]+'), '');
  if (s.isEmpty) s = fallback;
  if (s.length > 150) {
    final dot = s.lastIndexOf('.');
    final ext = (dot > 0 && s.length - dot <= 10) ? s.substring(dot) : '';
    s = s.substring(0, 150 - ext.length) + ext;
  }
  return s;
}

/// Parses RFC 6266 `Content-Disposition`: prefers `filename*=UTF-8''…`.
String? fileNameFromContentDisposition(String? header) {
  if (header == null || header.isEmpty) return null;
  final star = RegExp(r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)", caseSensitive: false).firstMatch(header);
  if (star != null) {
    try {
      return Uri.decodeComponent(star.group(2)!.trim().replaceAll('"', ''));
    } catch (_) {}
  }
  final plain = RegExp(r'filename\s*=\s*("([^"]*)"|[^;]+)', caseSensitive: false).firstMatch(header);
  if (plain != null) {
    final v = (plain.group(2) ?? plain.group(1)!).trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

const _extForMime = {
  'application/pdf': '.pdf',
  'application/zip': '.zip',
  'application/vnd.android.package-archive': '.apk',
  'application/json': '.json',
  'text/plain': '.txt',
  'text/csv': '.csv',
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/gif': '.gif',
  'image/webp': '.webp',
  'image/svg+xml': '.svg',
  'audio/mpeg': '.mp3',
  'video/mp4': '.mp4',
  'application/msword': '.doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
  'application/vnd.ms-excel': '.xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
};

/// Chooses a file name from the header, then the URL, then the MIME type.
String suggestFileName(String url, String? contentDisposition, String? mimeType) {
  var name = fileNameFromContentDisposition(contentDisposition);
  if (name == null || name.isEmpty) {
    final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
    name = segs.isNotEmpty ? Uri.decodeComponent(segs.last) : 'download';
  }
  if (!name.contains('.') && mimeType != null) {
    name += _extForMime[mimeType.split(';').first.trim().toLowerCase()] ?? '';
  }
  return sanitizeFileName(name);
}

/// Whether a response should be shown as a page rather than saved.
bool looksLikePage(String? mimeType, String? contentDisposition) {
  if (contentDisposition != null && contentDisposition.toLowerCase().contains('attachment')) return false;
  final m = (mimeType ?? '').toLowerCase();
  return m.startsWith('text/html') || m.startsWith('application/xhtml');
}

class DownloadsNotifier extends Notifier<List<DownloadItem>> {
  static const _key = 'downloads';
  static const _maxItems = 200;
  final Map<String, HttpClient> _clients = {};
  final Map<String, DateTime> _lastTick = {};
  int _seq = 0;

  Box? get _box => Hive.isBoxOpen(settingsBoxName) ? Hive.box(settingsBoxName) : null;

  @override
  List<DownloadItem> build() {
    ref.onDispose(() {
      for (final c in _clients.values) {
        c.close(force: true);
      }
    });
    final saved = _box?.get(_key);
    if (saved is! List) return [];
    return saved.map(DownloadItem.fromJson).whereType<DownloadItem>().toList();
  }

  static Future<Directory> downloadDir() async {
    Directory? base;
    if (Platform.isAndroid) base = await getExternalStorageDirectory();
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/Download');
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _uniquePath(Directory dir, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var candidate = '${dir.path}/$fileName';
    var n = 1;
    while (await File(candidate).exists() || await File('$candidate.part').exists()) {
      candidate = '${dir.path}/$stem ($n)$ext';
      n++;
    }
    return candidate;
  }

  /// Starts downloading [url]. Returns false (and downloads nothing) when the
  /// server answers with an ordinary web page, so the caller can open it.
  Future<bool> start(
    String url, {
    String? userAgent,
    String? cookie,
    String? referer,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme == 'data') return _saveDataUri(uri);
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;

    final id = 'd${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    if (userAgent != null && userAgent.isNotEmpty) client.userAgent = userAgent;
    HttpClientResponse response;
    try {
      final req = await client.getUrl(uri);
      if (cookie != null && cookie.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, cookie);
      if (referer != null && referer.startsWith('http')) req.headers.set(HttpHeaders.refererHeader, referer);
      response = await req.close();
    } catch (e) {
      client.close(force: true);
      _add(DownloadItem(
        id: id,
        url: url,
        fileName: suggestFileName(url, null, null),
        status: DownloadStatus.failed,
        error: '$e',
        startedAt: DateTime.now(),
      ));
      return true;
    }

    final cd = response.headers.value('content-disposition');
    final mime = response.headers.contentType?.mimeType;
    if (response.statusCode < 400 && looksLikePage(mime, cd)) {
      client.close(force: true);
      return false;
    }

    final fileName = suggestFileName(url, cd, mime);
    final item = DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      mimeType: mime,
      total: response.contentLength,
      startedAt: DateTime.now(),
    );
    _add(item);

    if (response.statusCode >= 400) {
      client.close(force: true);
      _update(id, (d) => d.copyWith(status: DownloadStatus.failed, error: 'HTTP ${response.statusCode}'));
      return true;
    }

    _clients[id] = client;
    unawaited(_stream(id, response, fileName));
    return true;
  }

  Future<void> _stream(String id, HttpClientResponse response, String fileName) async {
    IOSink? sink;
    File? part;
    try {
      final dir = await downloadDir();
      final path = await _uniquePath(dir, fileName);
      part = File('$path.part');
      sink = part.openWrite();
      _update(id, (d) => d.copyWith(path: path, fileName: path.split('/').last));
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(_lastTick[id] ?? DateTime(0)) > const Duration(milliseconds: 150)) {
          _lastTick[id] = now;
          _update(id, (d) => d.copyWith(received: received));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await part.rename(path);
      _update(id, (d) => d.copyWith(received: received, total: received, status: DownloadStatus.completed));
      await _publish(id, path);
    } catch (e) {
      await sink?.close();
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
      final cancelled = _find(id)?.status == DownloadStatus.cancelled;
      if (!cancelled) _update(id, (d) => d.copyWith(status: DownloadStatus.failed, error: '$e'));
    } finally {
      _clients.remove(id)?.close(force: true);
      _lastTick.remove(id);
      _persist();
    }
  }

  Future<bool> _saveDataUri(Uri uri) async {
    final data = uri.data;
    if (data == null) return false;
    final id = 'd${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
    final name = suggestFileName('', null, data.mimeType);
    try {
      final dir = await downloadDir();
      final path = await _uniquePath(dir, name);
      final bytes = data.contentAsBytes();
      await File(path).writeAsBytes(bytes);
      final publishId = id;
      _add(DownloadItem(
        id: id,
        url: 'data:${data.mimeType}',
        fileName: path.split('/').last,
        path: path,
        mimeType: data.mimeType,
        received: bytes.length,
        total: bytes.length,
        status: DownloadStatus.completed,
        startedAt: DateTime.now(),
      ));
      await _publish(publishId, path);
    } catch (e) {
      _add(DownloadItem(
          id: id, url: 'data:', fileName: name, status: DownloadStatus.failed, error: '$e', startedAt: DateTime.now()));
    }
    return true;
  }

  /// Copies a finished file into the shared Downloads folder (Android 10+)
  /// and removes the private copy. Keeps the private file if that fails.
  Future<void> _publish(String id, String path) async {
    final item = _find(id);
    if (item == null) return;
    final uri = await SharedDownloads.save(path, item.fileName, item.mimeType);
    if (uri == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
    state = [
      for (final d in state)
        if (d.id == id)
          DownloadItem(
            id: d.id,
            url: d.url,
            fileName: d.fileName,
            contentUri: uri,
            mimeType: d.mimeType,
            received: d.received,
            total: d.total,
            status: d.status,
            error: d.error,
            startedAt: d.startedAt,
          )
        else
          d,
    ];
    _persist();
  }

  void cancel(String id) {
    _update(id, (d) => d.copyWith(status: DownloadStatus.cancelled));
    _clients.remove(id)?.close(force: true);
    _persist();
  }

  /// Removes from the list; with [deleteFile] also deletes the file.
  Future<void> remove(String id, {bool deleteFile = false}) async {
    final item = _find(id);
    if (item == null) return;
    if (item.status == DownloadStatus.running) cancel(id);
    if (deleteFile && item.contentUri != null) {
      await SharedDownloads.delete(item.contentUri!);
    }
    if (deleteFile && item.path != null) {
      try {
        final f = File(item.path!);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Delete failed: $e');
      }
    }
    state = state.where((d) => d.id != id).toList();
    _persist();
  }

  Future<void> retry(String id) async {
    final item = _find(id);
    if (item == null || item.url.startsWith('data:')) return;
    await remove(id);
    await start(item.url);
  }

  void clearFinished() {
    state = state.where((d) => d.status == DownloadStatus.running).toList();
    _persist();
  }

  DownloadItem? _find(String id) {
    for (final d in state) {
      if (d.id == id) return d;
    }
    return null;
  }

  void _add(DownloadItem item) {
    final next = [item, ...state];
    state = next.length > _maxItems ? next.sublist(0, _maxItems) : next;
    _persist();
  }

  void _update(String id, DownloadItem Function(DownloadItem) change) {
    state = [for (final d in state) d.id == id ? change(d) : d];
  }

  void _persist() => _box?.put(_key, jsonDecode(jsonEncode(state.map((d) => d.toJson()).toList())));
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, List<DownloadItem>>(DownloadsNotifier.new);
