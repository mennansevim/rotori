// Japonca fraz sesi — OpenAI TTS ile önceden üretilmiş mp3 asset'lerini çalar.
//
// Neden asset: (1) offline çalışır, (2) OpenAI ses kalitesi native TTS'ten
// çok daha doğal ("nova" voice, tts-1-hd), (3) tek seferlik üretim maliyet
// çok düşük (~75 fraz × ~$0.001/1k char), (4) App Store binary'sinde
// paketlenir → runtime API key yok.
//
// Manifest (assets/tts/ja/manifest.json) `jp → id` eşlemesi tutar.
// `speakJa(jp)` çağrısı → id'yi bul → `assets/tts/ja/<id>.mp3` çal.
//
// Asset yoksa (henüz üretilmediyse) sessiz düş — debug'da log at.

import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final _player = AudioPlayer();
  Map<String, String>? _manifest; // jp text → asset id (uzantı hariç)
  String _format = 'mp3';

  Future<Map<String, String>> _loadManifest() async {
    if (_manifest != null) return _manifest!;
    try {
      final raw =
          await rootBundle.loadString('assets/tts/ja/manifest.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _format = (json['format'] as String?) ?? 'mp3';
      final items = (json['items'] as List).cast<Map<String, dynamic>>();
      _manifest = {
        for (final it in items) it['jp'] as String: it['id'] as String,
      };
    } catch (e) {
      debugPrint('TTS manifest load failed: $e');
      _manifest = const {};
    }
    return _manifest!;
  }

  Future<void> speakJa(String text) async {
    if (text.trim().isEmpty) return;
    final map = await _loadManifest();
    final id = map[text];
    if (id == null) {
      debugPrint('TTS: no asset for "$text" — regenerate manifest?');
      return;
    }
    try {
      await _player.stop();
      // AssetSource — pubspec'te tanımlı `assets/tts/ja/...` dosyasını çalar.
      await _player.play(AssetSource('tts/ja/$id.$_format'));
    } catch (e) {
      debugPrint('TTS play failed for "$text" ($id.$_format): $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}

final ttsServiceProvider = Provider<TtsService>((_) => TtsService.instance);
