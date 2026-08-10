// ticket_support.dart davranış testleri:
// requiresTicket (bilet gerektiren yerler) + parseTicketInfo (OCR ayrıştırma).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/shared/ticket_support.dart';

TimelineItem _item(String title) => TimelineItem(id: 'i1', title: title);

void main() {
  group('requiresTicket', () {
    test('Disney → true', () {
      expect(requiresTicket(_item('🏰 Tokyo Disneyland')), isTrue);
    });

    test('USJ / Universal → true', () {
      expect(requiresTicket(_item('Universal Studios Japan (USJ)')), isTrue);
    });

    test('teamLab → true', () {
      expect(requiresTicket(_item('teamLab Planets')), isTrue);
    });

    test('category museum → true (başlıkta anahtar kelime olmasa da)', () {
      expect(
        requiresTicket(_item('Edo-Tokyo'), category: 'museum'),
        isTrue,
      );
    });

    test('başlıkta müze geçen yer → true', () {
      expect(requiresTicket(_item('Ghibli Müzesi')), isTrue);
    });

    test('sıradan ramen yemeği → false', () {
      expect(requiresTicket(_item('🍜 Ichiran Ramen')), isFalse);
    });

    test('boş başlık → false', () {
      expect(requiresTicket(_item('')), isFalse);
    });
  });

  group('parseTicketInfo', () {
    test('tarih + saat içeren metinden ikisini de çıkarır', () {
      const text = 'DISNEYLAND\nVisit Date: 2026-07-21\nEntry 09:30\nCONF ABC12345';
      final info = parseTicketInfo(text);
      expect(info['date'], '2026-07-21');
      expect(info['time'], '09:30');
      expect(info['code'], 'ABC12345');
    });

    test('slash formatlı tarih (0-pad) → YYYY-MM-DD', () {
      final info = parseTicketInfo('Date 2026/7/5 time 8:05');
      expect(info['date'], '2026-07-05');
      expect(info['time'], '08:05');
    });

    test('boş metin → boş harita', () {
      expect(parseTicketInfo(''), isEmpty);
    });

    test('tarih yoksa date anahtarı dönmez', () {
      final info = parseTicketInfo('teamLab entry 10:00');
      expect(info.containsKey('date'), isFalse);
      expect(info['time'], '10:00');
    });
  });
}
