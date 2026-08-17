// Bilet yardımcıları — hangi yerlerin bilet gerektirdiğini belirler ve
// OCR ile çıkarılan ham metinden tarih/saat/onay kodu ayrıştırır.
//
// requiresTicket → place_detail_sheet + wiring tarafından "🎫 Bilet ekle"
// butonunun gösterilip gösterilmeyeceğine karar vermek için kullanılır.
// parseTicketInfo → apps/planner/src/utils/ocr.ts parseTicketFromText portu.

import '../../domain/types.dart';
import '../tickets/domain/ticket_import_models.dart';

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

/// OCR ve QR çıktısından, kullanıcı onayı gerektiren bilet alanları üretir.
List<TicketImportCandidate> buildTicketImportCandidates(
  String text, {
  required List<String> qrPayloads,
}) {
  final candidates = <TicketImportCandidate>[];
  final seen = <String>{};

  void addCandidate(TicketCandidateType type, String rawValue) {
    final value = rawValue.trim();
    final identity = '${type.name}:${value.toLowerCase()}';
    if (value.isEmpty || !seen.add(identity)) return;
    candidates.add(TicketImportCandidate(
      id: identity,
      type: type,
      value: value,
      needsReview: true,
    ));
  }

  final datePattern = RegExp(r'\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b');
  for (final match in datePattern.allMatches(text)) {
    final year = match.group(1)!;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    addCandidate(TicketCandidateType.date, '$year-$month-$day');
  }

  for (final match
      in RegExp(r'\b(?:[01]\d|2[0-3]):[0-5]\d\b').allMatches(text)) {
    addCandidate(TicketCandidateType.time, match.group(0)!);
  }

  for (final line in text.split(RegExp(r'\r?\n'))) {
    final value = line.trim();
    if (value.length >= 3 &&
        value.length <= 80 &&
        !datePattern.hasMatch(value)) {
      addCandidate(TicketCandidateType.label, value);
      break;
    }
  }

  for (final match in RegExp(r'\b[A-Za-z0-9]{6,}\b').allMatches(text)) {
    final value = match.group(0)!;
    if (value.contains(RegExp(r'[A-Za-z]')) && value.contains(RegExp(r'\d'))) {
      addCandidate(TicketCandidateType.confirmationCode, value);
    }
  }

  _addPatternValues(
    text,
    RegExp(r'\b(?:seat|koltuk)\s*[:#-]?\s*([A-Za-z0-9-]+)',
        caseSensitive: false),
    TicketCandidateType.seat,
    addCandidate,
  );
  _addPatternValues(
    text,
    RegExp(r'\b(?:gate|kapı)\s*[:#-]?\s*([A-Za-z0-9-]+)', caseSensitive: false),
    TicketCandidateType.gate,
    addCandidate,
  );
  _addPatternValues(
    text,
    RegExp(r'\b(\d+)\s*(?:persons?|adults?|kişi(?:ler)?)\b',
        caseSensitive: false),
    TicketCandidateType.partySize,
    addCandidate,
  );
  _addPatternValues(
    text,
    RegExp(r'\b(?:person|adult|kişi)\s*[:#-]?\s*(\d+)\b', caseSensitive: false),
    TicketCandidateType.partySize,
    addCandidate,
  );

  final urlPattern = RegExp(r'https?://[^\s<>()]+', caseSensitive: false);
  for (final match in urlPattern.allMatches(text)) {
    addCandidate(TicketCandidateType.url, _trimUrlPunctuation(match.group(0)!));
  }
  for (final payload in qrPayloads) {
    final value = payload.trim();
    addCandidate(TicketCandidateType.qr, value);
    if (urlPattern.hasMatch(value)) {
      addCandidate(TicketCandidateType.url, _trimUrlPunctuation(value));
    }
  }

  return List.unmodifiable(candidates);
}

void _addPatternValues(
  String text,
  RegExp pattern,
  TicketCandidateType type,
  void Function(TicketCandidateType type, String rawValue) addCandidate,
) {
  for (final match in pattern.allMatches(text)) {
    addCandidate(type, match.group(1)!);
  }
}

String _trimUrlPunctuation(String value) => value.replaceFirst(
      RegExp(r'[.,;:!?]+$'),
      '',
    );
