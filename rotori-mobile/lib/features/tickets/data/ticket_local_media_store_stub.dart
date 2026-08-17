import 'dart:typed_data';

import 'ticket_local_media_store.dart';

TicketLocalMediaStore createTicketLocalMediaStore() =>
    _UnsupportedTicketLocalMediaStore();

class _UnsupportedTicketLocalMediaStore implements TicketLocalMediaStore {
  Never _unsupported() => throw UnsupportedError(
      'Yerel bilet medyası bu platformda desteklenmiyor.');

  @override
  Future<StagedTicketMedia> stage({
    required String planId,
    required String ticketId,
    required Uint8List bytes,
    required String extension,
  }) async =>
      _unsupported();

  @override
  Future<String> commit(StagedTicketMedia media) async => _unsupported();

  @override
  Future<Uint8List?> read(String localMediaRef) async => _unsupported();

  @override
  Future<void> discard(StagedTicketMedia media) async => _unsupported();

  @override
  Future<void> delete(String localMediaRef) async => _unsupported();

  @override
  Future<void> cleanupStale({required DateTime now}) async => _unsupported();
}
