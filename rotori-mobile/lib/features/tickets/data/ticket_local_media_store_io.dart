import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'ticket_local_media_store.dart';

TicketLocalMediaStore createTicketLocalMediaStore() =>
    _IoTicketLocalMediaStore();

class _IoTicketLocalMediaStore implements TicketLocalMediaStore {
  static const _prefix = 'native:';

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
    final token = '$safePlanId/$safeTicketId/$mediaId';
    final stagedFile = File(p.join(
      (await _root()).path,
      'tmp',
      '$token.$normalizedExtension',
    ));
    await stagedFile.parent.create(recursive: true);
    await stagedFile.writeAsBytes(bytes, flush: true);
    return StagedTicketMedia(token: token, extension: normalizedExtension);
  }

  @override
  Future<String> commit(StagedTicketMedia media) async {
    final extension = normalizeTicketMediaExtension(media.extension);
    final segments = _tokenSegments(media.token);
    final root = await _root();
    final stagedFile = File(p.join(
      root.path,
      'tmp',
      '${segments.join('/')}.$extension',
    ));
    final finalFile = File(p.join(
      root.path,
      'tickets',
      segments[0],
      segments[1],
      '${segments[2]}.$extension',
    ));
    await finalFile.parent.create(recursive: true);
    if (await finalFile.exists()) {
      throw StateError('Bilet medyası kimliği zaten kullanılıyor.');
    }
    await stagedFile.rename(finalFile.path);
    return '$_prefix${_relativePath(segments, extension)}';
  }

  @override
  Future<Uint8List?> read(String localMediaRef) async {
    final file = await _fileForRef(localMediaRef);
    if (file == null || !await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> discard(StagedTicketMedia media) async {
    final extension = normalizeTicketMediaExtension(media.extension);
    final segments = _tokenSegments(media.token);
    final file = File(p.join(
      (await _root()).path,
      'tmp',
      '${segments.join('/')}.$extension',
    ));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> delete(String localMediaRef) async {
    final file = await _fileForRef(localMediaRef);
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> cleanupStale({required DateTime now}) async {
    final tmp = Directory(p.join((await _root()).path, 'tmp'));
    if (!await tmp.exists()) {
      return;
    }
    final cutoff = now.subtract(const Duration(hours: 24));
    await for (final entity in tmp.list(recursive: true, followLinks: false)) {
      if (entity is File && (await entity.stat()).modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }

  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'ticket-media'));
  }

  List<String> _tokenSegments(String token) {
    final segments = token.split('/');
    if (segments.length != 3) {
      throw ArgumentError.value(
          token, 'token', 'Geçersiz staged medya belirteci.');
    }
    return [
      validateTicketMediaPathSegment(segments[0], name: 'planId'),
      validateTicketMediaPathSegment(segments[1], name: 'ticketId'),
      validateTicketMediaPathSegment(segments[2], name: 'mediaId'),
    ];
  }

  Future<File?> _fileForRef(String localMediaRef) async {
    if (!localMediaRef.startsWith(_prefix)) {
      return null;
    }
    final relative = localMediaRef.substring(_prefix.length);
    final segments = relative.split('/');
    if (segments.length != 4 || segments.first != 'tickets') {
      throw ArgumentError.value(
          localMediaRef, 'localMediaRef', 'Geçersiz medya referansı.');
    }
    validateTicketMediaPathSegment(segments[1], name: 'planId');
    validateTicketMediaPathSegment(segments[2], name: 'ticketId');
    final dot = segments[3].lastIndexOf('.');
    if (dot <= 0) {
      throw ArgumentError.value(
          localMediaRef, 'localMediaRef', 'Geçersiz medya referansı.');
    }
    validateTicketMediaPathSegment(segments[3].substring(0, dot),
        name: 'mediaId');
    final extension =
        normalizeTicketMediaExtension(segments[3].substring(dot + 1));
    return File(p.join(
      (await _root()).path,
      'tickets',
      segments[1],
      segments[2],
      '${segments[3].substring(0, dot)}.$extension',
    ));
  }

  String _relativePath(List<String> segments, String extension) =>
      'tickets/${segments[0]}/${segments[1]}/${segments[2]}.$extension';
}
