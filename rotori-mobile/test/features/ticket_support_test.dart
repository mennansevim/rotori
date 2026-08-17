// ticket_support.dart davranış testleri:
// requiresTicket (bilet gerektiren yerler) + parseTicketInfo (OCR ayrıştırma).

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/shared/ticket_support.dart';
import 'package:rotori/features/tickets/domain/ticket_import_models.dart';

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
      const text =
          'DISNEYLAND\nVisit Date: 2026-07-21\nEntry 09:30\nCONF ABC12345';
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

  group('buildTicketImportCandidates', () {
    test('candidate parser returns every distinct date and time for review',
        () {
      final candidates = buildTicketImportCandidates(
        'Purchase 2026-07-01\nVisit 2026-08-17\nDoors 08:30\nEntry 09:00',
        qrPayloads: const [],
      );

      expect(
        candidates
            .where((candidate) => candidate.type == TicketCandidateType.date),
        hasLength(2),
      );
      expect(
        candidates
            .where((candidate) => candidate.type == TicketCandidateType.time),
        hasLength(2),
      );
      expect(candidates.every((candidate) => candidate.needsReview), isTrue);
    });

    test('candidate parser keeps QR payload without marking purchase status',
        () {
      final candidates = buildTicketImportCandidates(
        'Tokyo Disneyland',
        qrPayloads: const ['https://ticket.example/ABC123'],
      );

      expect(
        candidates.any((candidate) => candidate.type == TicketCandidateType.qr),
        isTrue,
      );
      expect(
        candidates.any((candidate) => candidate.type.name == 'purchased'),
        isFalse,
      );
    });

    test('candidate parser proposes label and localized ticket details', () {
      final candidates = buildTicketImportCandidates(
        'Tokyo Disneyland\nKoltuk: C-12\nKapı: A\n2 kişi',
        qrPayloads: const [],
      );

      expect(
        candidates.any(
          (candidate) =>
              candidate.type == TicketCandidateType.label &&
              candidate.value == 'Tokyo Disneyland',
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (candidate) =>
              candidate.type == TicketCandidateType.seat &&
              candidate.value == 'C-12',
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (candidate) =>
              candidate.type == TicketCandidateType.gate &&
              candidate.value == 'A',
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (candidate) =>
              candidate.type == TicketCandidateType.partySize &&
              candidate.value == '2',
        ),
        isTrue,
      );
    });

    test(
        'candidate parser deduplicates normalized values and keeps codes and URLs',
        () {
      final candidates = buildTicketImportCandidates(
        'Visit 2026/8/17\nAgain 2026/8/17\nCode AB12CD34\n'
        'https://ticket.example/AB12CD34',
        qrPayloads: const ['HTTPS://TICKET.EXAMPLE/AB12CD34'],
      );

      expect(
        candidates
            .where((candidate) => candidate.type == TicketCandidateType.date),
        hasLength(1),
      );
      expect(
        candidates.where(
          (candidate) => candidate.type == TicketCandidateType.confirmationCode,
        ),
        hasLength(1),
      );
      expect(
        candidates
            .where((candidate) => candidate.type == TicketCandidateType.url),
        hasLength(1),
      );
      expect(
        candidates
            .where((candidate) => candidate.type == TicketCandidateType.qr),
        hasLength(1),
      );
    });
  });
}
