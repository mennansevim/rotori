import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ticket_local_media_store_stub.dart'
    if (dart.library.io) 'ticket_local_media_store_io.dart'
    if (dart.library.html) 'ticket_local_media_store_web.dart' as platform;

class StagedTicketMedia {
  const StagedTicketMedia({required this.token, required this.extension});

  final String token;
  final String extension;
}

abstract interface class TicketLocalMediaStore {
  Future<StagedTicketMedia> stage({
    required String planId,
    required String ticketId,
    required Uint8List bytes,
    required String extension,
  });

  Future<String> commit(StagedTicketMedia media);
  Future<Uint8List?> read(String localMediaRef);
  Future<void> discard(StagedTicketMedia media);
  Future<void> delete(String localMediaRef);
  Future<void> cleanupStale({required DateTime now});
}

TicketLocalMediaStore createTicketLocalMediaStore() =>
    platform.createTicketLocalMediaStore();

final ticketLocalMediaStoreProvider = Provider<TicketLocalMediaStore>(
  (ref) => createTicketLocalMediaStore(),
);

String normalizeTicketMediaExtension(String extension) {
  var normalized = extension.trim().toLowerCase();
  if (normalized.startsWith('.')) {
    normalized = normalized.substring(1);
  }
  if (normalized == 'jpeg') {
    normalized = 'jpg';
  }
  if (normalized == 'jpg' || normalized == 'png' || normalized == 'webp') {
    return normalized;
  }
  throw ArgumentError.value(
    extension,
    'extension',
    'Bilet medyası yalnızca jpg, png veya webp olabilir.',
  );
}

String validateTicketMediaPathSegment(String value, {required String name}) {
  if (value.isEmpty ||
      value.contains('..') ||
      value.contains('/') ||
      value.contains('\\')) {
    throw ArgumentError.value(value, name, 'Geçersiz medya yolu bölümü.');
  }
  return value;
}
