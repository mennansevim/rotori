import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/tickets/application/ticket_import_coordinator.dart';
import 'package:rotori/features/tickets/data/ticket_local_media_store.dart';
import 'package:rotori/features/tickets/domain/ticket_import_models.dart';

void main() {
  late _MemoryTicketLocalMediaStore mediaStore;
  late TicketImportCoordinator coordinator;
  late XFile fakeImage;
  late Ticket ticket;

  setUp(() {
    mediaStore = _MemoryTicketLocalMediaStore();
    coordinator = TicketImportCoordinator(
      mediaStore: mediaStore,
      extractor: const _EmptyTicketExtractor(),
    );
    fakeImage = XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      path: '/picked/ticket.JPEG',
      mimeType: 'image/jpeg',
    );
    ticket = Ticket(
      id: 't1',
      kind: 'attraction',
      label: 'teamLab Planets',
      purchased: true,
      imageDataUrl: 'data:image/jpeg;base64,AQID',
      scannedText: 'legacy OCR text',
    );
  });

  test('cancel discards staged media', () async {
    final session = await coordinator.begin(
      planId: 'p1',
      ticketId: 't1',
      picked: fakeImage,
    );

    await session!.cancel();

    expect(mediaStore.stagedCount, 0);
  });

  test('save rollback deletes new media when plan persistence fails', () async {
    final session = await coordinator.begin(
      planId: 'p1',
      ticketId: 't1',
      picked: fakeImage,
    );
    Ticket? persisted;

    final saved = await session!.save(
      ticket: ticket,
      persist: (updated) async {
        persisted = updated;
        return false;
      },
    );

    expect(saved, isFalse);
    expect(mediaStore.committedCount, 0);
    expect(persisted!.localMediaRef, 'memory:p1/t1/0.jpg');
    expect(persisted!.imageDataUrl, isNull);
    expect(persisted!.scannedText, isNull);
  });

  test('replacement deletes old media only after successful persistence',
      () async {
    final session = await coordinator.begin(
      planId: 'p1',
      ticketId: 't1',
      picked: fakeImage,
    );

    final saved = await session!.save(
      ticket: ticket,
      replacedMediaRef: 'memory:old',
      persist: (updated) async {
        expect(mediaStore.deletedRefs, isNot(contains('memory:old')));
        return updated.localMediaRef != null;
      },
    );

    expect(saved, isTrue);
    expect(mediaStore.deletedRefs, contains('memory:old'));
  });

  test('repeated save returns its successful result without persisting twice',
      () async {
    final session = await coordinator.begin(
      planId: 'p1',
      ticketId: 't1',
      picked: fakeImage,
    );
    var persistCalls = 0;

    Future<bool> persist(Ticket updated) async {
      persistCalls++;
      return true;
    }

    final first = await session!.save(ticket: ticket, persist: persist);
    final second = await session.save(ticket: ticket, persist: persist);

    expect(first, isTrue);
    expect(second, isTrue);
    expect(persistCalls, 1);
    expect(mediaStore.committedCount, 1);
  });
}

class _EmptyTicketExtractor implements TicketExtractor {
  const _EmptyTicketExtractor();

  @override
  Future<TicketExtractionResult> extract(String imagePath) async =>
      const TicketExtractionResult();
}

class _MemoryTicketLocalMediaStore implements TicketLocalMediaStore {
  final Map<String, Uint8List> _staged = {};
  final Map<String, Uint8List> _committed = {};
  final List<String> deletedRefs = [];
  var _nextId = 0;

  int get stagedCount => _staged.length;
  int get committedCount => _committed.length;

  @override
  Future<StagedTicketMedia> stage({
    required String planId,
    required String ticketId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final token = '$planId/$ticketId/${_nextId++}';
    _staged[token] = Uint8List.fromList(bytes);
    return StagedTicketMedia(token: token, extension: extension);
  }

  @override
  Future<String> commit(StagedTicketMedia media) async {
    final bytes = _staged.remove(media.token)!;
    final ref = 'memory:${media.token}.${media.extension}';
    _committed[ref] = bytes;
    return ref;
  }

  @override
  Future<Uint8List?> read(String localMediaRef) async =>
      _committed[localMediaRef];

  @override
  Future<void> discard(StagedTicketMedia media) async {
    _staged.remove(media.token);
  }

  @override
  Future<void> delete(String localMediaRef) async {
    deletedRefs.add(localMediaRef);
    _committed.remove(localMediaRef);
  }

  @override
  Future<void> cleanupStale({required DateTime now}) async {}
}
