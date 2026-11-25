import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tabs_provider.dart';

/// Splits text into chunks the TTS engine accepts (Android limit ~4000
/// chars), preferring paragraph and sentence boundaries.
List<String> chunkForSpeech(String text, {int max = 1500}) {
  final out = <String>[];
  for (final para in text.split('\n')) {
    var p = para.trim();
    while (p.length > max) {
      var cut = p.lastIndexOf(RegExp(r'[.!?。]\s'), max);
      if (cut < max ~/ 3) cut = p.lastIndexOf(' ', max);
      if (cut <= 0) cut = max;
      out.add(p.substring(0, cut + 1).trim());
      p = p.substring(cut + 1).trim();
    }
    if (p.isNotEmpty) out.add(p);
  }
  return out;
}

enum ReadAloudStatus { idle, loading, playing, paused }

@immutable
class ReadAloudState {
  final ReadAloudStatus status;
  final String title;
  final int index;
  final int total;
  final double rate;
  const ReadAloudState({this.status = ReadAloudStatus.idle, this.title = '', this.index = 0, this.total = 0, this.rate = 1.0});

  bool get active => status != ReadAloudStatus.idle;
  double get progress => total == 0 ? 0 : index / total;

  ReadAloudState copyWith({ReadAloudStatus? status, String? title, int? index, int? total, double? rate}) => ReadAloudState(
        status: status ?? this.status,
        title: title ?? this.title,
        index: index ?? this.index,
        total: total ?? this.total,
        rate: rate ?? this.rate,
      );
}

/// Reads the current article aloud with the phone's own text-to-speech.
class ReadAloudNotifier extends Notifier<ReadAloudState> {
  FlutterTts? _tts;
  List<String> _chunks = const [];

  @override
  ReadAloudState build() {
    ref.onDispose(() => _tts?.stop());
    return const ReadAloudState();
  }

  Future<FlutterTts> _engine() async {
    if (_tts != null) return _tts!;
    final tts = FlutterTts();
    await tts.awaitSpeakCompletion(false);
    tts.setCompletionHandler(_next);
    tts.setErrorHandler((_) => stop());
    _tts = tts;
    return tts;
  }

  /// Extracts the article from the active page and starts reading.
  Future<String?> start() async {
    state = state.copyWith(status: ReadAloudStatus.loading);
    try {
      final raw = await ref
          .read(tabsProvider.notifier)
          .activeController
          .runJavaScriptReturningResult('window.__dbg && window.__dbg.readerText ? window.__dbg.readerText() : ""');
      var s = raw is String ? raw : '$raw';
      // Android returns the JS string JSON-encoded.
      if (s.startsWith('"')) s = jsonDecode(s) as String;
      final j = s.isEmpty ? const {} : jsonDecode(s) as Map;
      final title = '${j['title'] ?? ''}';
      _chunks = [if (title.isNotEmpty) title, ...chunkForSpeech('${j['text'] ?? ''}')];
      if (_chunks.length <= (title.isNotEmpty ? 1 : 0)) {
        state = const ReadAloudState();
        return 'No article text found on this page.';
      }
      final tts = await _engine();
      await tts.setSpeechRate(_androidRate(state.rate));
      state = state.copyWith(status: ReadAloudStatus.playing, title: title, index: 0, total: _chunks.length);
      await tts.speak(_chunks.first);
      return null;
    } catch (e) {
      state = const ReadAloudState();
      return 'Read aloud is not available: $e';
    }
  }

  void _next() {
    if (state.status != ReadAloudStatus.playing) return;
    final i = state.index + 1;
    if (i >= _chunks.length) {
      state = const ReadAloudState().copyWith(rate: state.rate);
      return;
    }
    state = state.copyWith(index: i);
    _tts?.speak(_chunks[i]);
  }

  Future<void> pause() async {
    await _tts?.stop(); // resume restarts the current chunk (works on all Android versions)
    state = state.copyWith(status: ReadAloudStatus.paused);
  }

  Future<void> resume() async {
    if (_chunks.isEmpty) return;
    state = state.copyWith(status: ReadAloudStatus.playing);
    await _tts?.speak(_chunks[state.index]);
  }

  Future<void> skip(int delta) async {
    if (_chunks.isEmpty) return;
    final i = (state.index + delta).clamp(0, _chunks.length - 1);
    await _tts?.stop();
    state = state.copyWith(index: i, status: ReadAloudStatus.playing);
    await _tts?.speak(_chunks[i]);
  }

  Future<void> setRate(double rate) async {
    state = state.copyWith(rate: rate);
    await _tts?.setSpeechRate(_androidRate(rate));
    if (state.status == ReadAloudStatus.playing) await skip(0);
  }

  Future<void> stop() async {
    await _tts?.stop();
    _chunks = const [];
    state = const ReadAloudState().copyWith(rate: state.rate);
  }

  /// flutter_tts on Android: 0.5 is normal speed.
  static double _androidRate(double r) => (r * 0.5).clamp(0.1, 1.0);
}

final readAloudProvider = NotifierProvider<ReadAloudNotifier, ReadAloudState>(ReadAloudNotifier.new);
