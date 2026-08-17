import 'dart:typed_data';

import 'package:idb_shim/idb_shim.dart';
import 'package:uuid/uuid.dart';

import 'ticket_local_media_store.dart';

const _dbName = 'rotori-ticket-media';
const _storeName = 'media';
const _stagedPrefix = 'webtmp:';
const _committedPrefix = 'web:';

TicketLocalMediaStore createTicketLocalMediaStore() =>
    _WebTicketLocalMediaStore();

class _WebTicketLocalMediaStore implements TicketLocalMediaStore {
  @override
  Future<StagedTicketMedia> stage({
    required String planId,
    required String ticketId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final safePlanId = validateTicketMediaPathSegment(planId, name: 'planId');
    final safeTicketId =
        validateTicketMediaPathSegment(ticketId, name: 'ticketId');
    final normalizedExtension = normalizeTicketMediaExtension(extension);
    final mediaId = const Uuid().v4();
    final ref =
        '$_stagedPrefix${_relativePath(safePlanId, safeTicketId, mediaId, normalizedExtension)}';
    await _put(_record(
      ref: ref,
      bytes: bytes,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      staged: true,
    ));
    return StagedTicketMedia(token: ref, extension: normalizedExtension);
  }

  @override
  Future<String> commit(StagedTicketMedia media) async {
    final extension = normalizeTicketMediaExtension(media.extension);
    final stagedRef = _validatedStagedRef(media.token, extension);
    final committedRef =
        '$_committedPrefix${stagedRef.substring(_stagedPrefix.length)}';
    final db = await _open();
    try {
      final tx = db.transaction(_storeName, idbModeReadWrite);
      final store = tx.objectStore(_storeName);
      final record = await store.getObject(stagedRef);
      if (record == null) {
        throw StateError('Staged bilet medyası bulunamadı.');
      }
      final existing = await store.getObject(committedRef);
      if (existing != null) {
        throw StateError('Bilet medyası kimliği zaten kullanılıyor.');
      }
      final stagedRecord = _recordFromObject(record, stagedRef);
      await store.put({
        ...stagedRecord,
        'ref': committedRef,
        'staged': false,
      });
      await store.delete(stagedRef);
      await tx.completed;
      return committedRef;
    } finally {
      db.close();
    }
  }

  @override
  Future<Uint8List?> read(String localMediaRef) async {
    final ref = _validatedCommittedRef(localMediaRef);
    if (ref == null) {
      return null;
    }
    final record = await _get(ref);
    if (record == null || record['staged'] == true) {
      return null;
    }
    return _bytesFromRecord(record);
  }

  @override
  Future<void> discard(StagedTicketMedia media) async {
    final extension = normalizeTicketMediaExtension(media.extension);
    await _delete(_validatedStagedRef(media.token, extension));
  }

  @override
  Future<void> delete(String localMediaRef) async {
    final ref = _validatedCommittedRef(localMediaRef);
    if (ref != null) {
      await _delete(ref);
    }
  }

  @override
  Future<void> cleanupStale({required DateTime now}) async {
    final db = await _open();
    try {
      final tx = db.transaction(_storeName, idbModeReadWrite);
      final store = tx.objectStore(_storeName);
      final cutoff =
          now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
      final records = await store.getAll();
      for (final value in records) {
        final record = _recordFromObject(value, 'cleanup');
        final createdAt = record['createdAt'];
        if (record['staged'] == true &&
            record['ref'] is String &&
            (record['ref'] as String).startsWith(_stagedPrefix) &&
            createdAt is num &&
            createdAt < cutoff) {
          await store.delete(record['ref'] as String);
        }
      }
      await tx.completed;
    } finally {
      db.close();
    }
  }
}

Future<Database> _open() => idbFactoryWeb.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final db = event.database;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName, keyPath: 'ref');
        }
      },
    );

Future<void> _put(Map<String, Object?> record) async {
  final db = await _open();
  try {
    final tx = db.transaction(_storeName, idbModeReadWrite);
    await tx.objectStore(_storeName).put(record);
    await tx.completed;
  } finally {
    db.close();
  }
}

Future<Map<String, Object?>?> _get(String ref) async {
  final db = await _open();
  try {
    final tx = db.transaction(_storeName, idbModeReadOnly);
    final value = await tx.objectStore(_storeName).getObject(ref);
    await tx.completed;
    return value == null ? null : _recordFromObject(value, ref);
  } finally {
    db.close();
  }
}

Future<void> _delete(String ref) async {
  final db = await _open();
  try {
    final tx = db.transaction(_storeName, idbModeReadWrite);
    await tx.objectStore(_storeName).delete(ref);
    await tx.completed;
  } finally {
    db.close();
  }
}

Map<String, Object?> _record({
  required String ref,
  required Uint8List bytes,
  required int createdAt,
  required bool staged,
}) =>
    {
      'ref': ref,
      'bytes': Uint8List.fromList(bytes),
      'createdAt': createdAt,
      'staged': staged,
    };

Map<String, Object?> _recordFromObject(Object value, String ref) {
  if (value is! Map) {
    throw StateError('Geçersiz bilet medya kaydı: $ref');
  }
  return Map<String, Object?>.from(value);
}

Uint8List _bytesFromRecord(Map<String, Object?> record) {
  final bytes = record['bytes'];
  if (bytes is Uint8List) {
    return Uint8List.fromList(bytes);
  }
  if (bytes is List<int>) {
    return Uint8List.fromList(bytes);
  }
  throw StateError('Geçersiz bilet medya baytları.');
}

String _validatedStagedRef(String ref, String extension) {
  if (!ref.startsWith(_stagedPrefix)) {
    throw ArgumentError.value(ref, 'token', 'Geçersiz staged medya belirteci.');
  }
  _validatedRelativePath(ref.substring(_stagedPrefix.length), extension);
  return ref;
}

String? _validatedCommittedRef(String ref) {
  if (!ref.startsWith(_committedPrefix)) {
    return null;
  }
  _validatedRelativePath(ref.substring(_committedPrefix.length), null);
  return ref;
}

void _validatedRelativePath(String relative, String? expectedExtension) {
  final segments = relative.split('/');
  if (segments.length != 4 || segments.first != 'tickets') {
    throw ArgumentError.value(
        relative, 'localMediaRef', 'Geçersiz medya referansı.');
  }
  validateTicketMediaPathSegment(segments[1], name: 'planId');
  validateTicketMediaPathSegment(segments[2], name: 'ticketId');
  final dot = segments[3].lastIndexOf('.');
  if (dot <= 0) {
    throw ArgumentError.value(
        relative, 'localMediaRef', 'Geçersiz medya referansı.');
  }
  validateTicketMediaPathSegment(segments[3].substring(0, dot),
      name: 'mediaId');
  final extension =
      normalizeTicketMediaExtension(segments[3].substring(dot + 1));
  if (expectedExtension != null && extension != expectedExtension) {
    throw ArgumentError.value(
        relative, 'token', 'Staged medya uzantısı uyuşmuyor.');
  }
}

String _relativePath(
  String planId,
  String ticketId,
  String mediaId,
  String extension,
) =>
    'tickets/$planId/$ticketId/$mediaId.$extension';
