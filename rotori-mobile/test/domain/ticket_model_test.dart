import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/types.dart';

void main() {
  test('ticket local media and confirmed details round-trip', () {
    final ticket = Ticket(
      id: 't1',
      kind: 'attraction',
      label: 'Tokyo Disneyland',
      purchased: true,
      localMediaRef: 'native:tickets/plan/t1/original.png',
      confirmedDetails: const [
        TicketDetail(
          id: 'd1',
          semanticKey: 'confirmationCode',
          label: 'Rezervasyon kodu',
          value: 'ABC12345',
        ),
      ],
    );

    final restored = Ticket.fromJson(ticket.toJson());
    expect(restored.localMediaRef, ticket.localMediaRef);
    expect(restored.confirmedDetails.single.value, 'ABC12345');
  });

  test('legacy ticket without local fields still loads', () {
    final restored = Ticket.fromJson({
      'id': 'legacy',
      'kind': 'other',
      'label': 'Legacy',
      'purchased': false,
      'imageDataUrl': 'data:image/png;base64,AA==',
    });
    expect(restored.localMediaRef, isNull);
    expect(restored.confirmedDetails, isEmpty);
    expect(restored.imageDataUrl, startsWith('data:image/png'));
  });

  test('malformed confirmed details are ignored', () {
    final restored = Ticket.fromJson({
      'id': 'legacy',
      'kind': 'other',
      'label': 'Legacy',
      'purchased': false,
      'confirmedDetails': 'not-a-list',
    });

    expect(restored.confirmedDetails, isEmpty);
  });
}
