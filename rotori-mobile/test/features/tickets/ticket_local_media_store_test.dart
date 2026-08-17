import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/features/tickets/data/ticket_local_media_store.dart';

void main() {
  test('staged media is unreadable by final ref until commit', () async {
    final store = MemoryTicketLocalMediaStore();
    final staged = await store.stage(
      planId: 'p1',
      ticketId: 't1',
      bytes: Uint8List.fromList([1, 2, 3]),
      extension: 'png',
    );

    final ref = await store.commit(staged);
    expect(ref, startsWith('memory:p1/t1/'));
    expect(ref, endsWith('.png'));
    expect(await store.read(ref), Uint8List.fromList([1, 2, 3]));
  });

  test('discard removes staged bytes and delete removes committed bytes',
      () async {
    final store = MemoryTicketLocalMediaStore();
    final staged = await store.stage(
      planId: 'p1',
      ticketId: 't1',
      bytes: Uint8List(1),
      extension: 'jpg',
    );
    await store.discard(staged);
    expect(store.stagedCount, 0);

    final next = await store.stage(
      planId: 'p1',
      ticketId: 't1',
      bytes: Uint8List(1),
      extension: 'jpg',
    );
    final ref = await store.commit(next);
    await store.delete(ref);
    expect(await store.read(ref), isNull);
  });

  test('normalizes the supported ticket-media extensions', () {
    expect(normalizeTicketMediaExtension(' .JPEG '), 'jpg');
    expect(normalizeTicketMediaExtension('PNG'), 'png');
    expect(normalizeTicketMediaExtension('webp'), 'webp');
    expect(() => normalizeTicketMediaExtension('gif'), throwsArgumentError);
  });

  test('rejects traversal in ticket-media path segments', () {
    expect(
      () => validateTicketMediaPathSegment('../p1', name: 'planId'),
      throwsArgumentError,
    );
    expect(
      () => validateTicketMediaPathSegment('p1/t1', name: 'planId'),
      throwsArgumentError,
    );
  });
}

class MemoryTicketLocalMediaStore implements TicketLocalMediaStore {
  final Map<String, _MemoryMedia> _staged = {};
  final Map<String, Uint8List> _committed = {};
  var _nextId = 0;

  int get stagedCount => _staged.length;

  @override
  Future<StagedTicketMedia> stage({
    required String planId,
    required String ticketId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final token = '$planId/$ticketId/${_nextId++}';
    _staged[token] = _MemoryMedia(bytes: Uint8List.fromList(bytes));
    return StagedTicketMedia(token: token, extension: extension);
  }

  @override
  Future<String> commit(StagedTicketMedia media) async {
    final bytes = _staged.remove(media.token)!;
    final ref = 'memory:${media.token}.${media.extension}';
    _committed[ref] = bytes.bytes;
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
    _committed.remove(localMediaRef);
  }

  @override
  Future<void> cleanupStale({required DateTime now}) async {}
}

class _MemoryMedia {
  const _MemoryMedia({required this.bytes});

  final Uint8List bytes;
}
