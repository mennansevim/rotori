// Bilet yardımcıları — hangi yerlerin bilet gerektirdiğini belirler ve
// OCR ile çıkarılan ham metinden tarih/saat/onay kodu ayrıştırır.
//
// requiresTicket → place_detail_sheet + wiring tarafından "🎫 Bilet ekle"
// butonunun gösterilip gösterilmeyeceğine karar vermek için kullanılır.
// parseTicketInfo → apps/planner/src/utils/ocr.ts parseTicketFromText portu.

import '../../domain/types.dart';

/// Başlıktan emoji/işaret temizleyip karşılaştırma için normalize eder.
/// place_detail_sheet.dart'taki eski `_normalize` ile aynı yaklaşım —
/// tek bir kaynaktan paylaşılır.
String normalizeTitle(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final isDigit = r >= 48 && r <= 57;
    final isUpper = r >= 65 && r <= 90;
    final isLower = r >= 97 && r <= 122;
    final isLatinExt = r >= 0x00C0 && r <= 0x024F; // ç ş ğ ü ö ı İ vb.
    if (isDigit || isUpper || isLower || isLatinExt || r == 32) {
      b.writeCharCode(r);
    }
  }
  return b.toString().trim().toLowerCase();
}

/// Bilet gerektiren yer başlıklarında geçen anahtar kelimeler (normalize edilmiş).
const List<String> _ticketKeywords = [
  'disney',
  'disneyland',
  'disneysea',
  'universal',
  'usj',
  'teamlab',
  'team lab',
  'ghibli',
  'legoland',
  'aquarium',
  'sea life',
  'akvaryum',
  'museum',
  'müze',
  'skytree',
  'sky tree',
  'tokyo tower',
  'observation',
  'gözlem',
  'planetarium',
  'sumo',
  'kabuki',
  'robot restaurant',
];

/// Bu öğe bilet gerektiriyor mu?
/// category=='museum' ise veya normalize edilmiş başlık bilet anahtar
/// kelimelerinden birini içeriyorsa true.
bool requiresTicket(TimelineItem item, {String? category}) {
  if (category == 'museum') return true;
  final t = normalizeTitle(item.title);
  if (t.isEmpty) return false;
  for (final kw in _ticketKeywords) {
    if (t.contains(kw)) return true;
  }
  return false;
}

/// OCR ham metninden bilet bilgisi ayrıştırır.
/// Dönen anahtarlar (yalnızca bulunanlar): 'date' (YYYY-MM-DD), 'time' (HH:MM),
/// 'code' (onay/rezervasyon kodu).
Map<String, String> parseTicketInfo(String text) {
  final out = <String, String>{};
  if (text.isEmpty) return out;

  final dateMatch =
      RegExp(r'(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
  if (dateMatch != null) {
    final y = dateMatch.group(1)!;
    final m = dateMatch.group(2)!.padLeft(2, '0');
    final d = dateMatch.group(3)!.padLeft(2, '0');
    out['date'] = '$y-$m-$d';
  }

  final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
  if (timeMatch != null) {
    final h = timeMatch.group(1)!.padLeft(2, '0');
    final mm = timeMatch.group(2)!;
    out['time'] = '$h:$mm';
  }

  // Onay/rezervasyon kodu: 6+ karakterlik token'lardan HEM harf HEM rakam
  // içeren ilkini seç — böylece "DISNEYLAND" gibi salt-harf kelimeler ya da
  // salt-rakam diziler yanlışlıkla kod sayılmaz.
  for (final m in RegExp(r'\b[A-Z0-9]{6,}\b').allMatches(text)) {
    final tok = m.group(0)!;
    final hasDigit = tok.contains(RegExp(r'\d'));
    final hasAlpha = tok.contains(RegExp(r'[A-Z]'));
    if (hasDigit && hasAlpha) {
      out['code'] = tok;
      break;
    }
  }

  return out;
}
