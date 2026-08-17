import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rotori/domain/types.dart';
import 'package:rotori/features/tickets/data/ticket_extractor.dart';
import 'package:rotori/features/tickets/data/ticket_local_media_store.dart';
import 'package:rotori/features/tickets/domain/ticket_import_models.dart';

class TicketImportCoordinator {
  TicketImportCoordinator({
    TicketLocalMediaStore? mediaStore,
    TicketExtractor? extractor,
  })  : _mediaStore = mediaStore ?? createTicketLocalMediaStore(),
        _extractor = extractor ?? createTicketExtractor();

  final TicketLocalMediaStore _mediaStore;
  final TicketExtractor _extractor;

  Future<TicketImportSession?> begin({
    required String planId,
    required String ticketId,
    required XFile? picked,
  }) async {
    if (picked == null) {
      return null;
    }

    final bytes = await picked.readAsBytes();
    final extension = _extensionFor(picked);
    final stagedMedia = await _mediaStore.stage(
      planId: planId,
      ticketId: ticketId,
      bytes: bytes,
      extension: extension,
    );

    try {
      final extraction = _supportsNativeExtraction
          ? await _extractor.extract(picked.path)
          : const TicketExtractionResult();
      return TicketImportSession(
        stagedMedia: stagedMedia,
        extraction: extraction,
        mediaStore: _mediaStore,
      );
    } on Object {
      await _mediaStore.discard(stagedMedia);
      rethrow;
    }
  }

  bool get _supportsNativeExtraction =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

class TicketImportSession {
  TicketImportSession({
    required this.stagedMedia,
    required this.extraction,
    required this.mediaStore,
  });

  final StagedTicketMedia stagedMedia;
  final TicketExtractionResult extraction;
  final TicketLocalMediaStore mediaStore;

  var _isTerminal = false;
  Future<bool>? _saveOperation;

  Future<bool> save({
    required Ticket ticket,
    required Future<bool> Function(Ticket ticket) persist,
    String? replacedMediaRef,
  }) {
    if (_saveOperation != null) {
      return _saveOperation!;
    }
    if (_isTerminal) {
      return Future<bool>.value(false);
    }
    _isTerminal = true;
    return _saveOperation = _save(
      ticket: ticket,
      persist: persist,
      replacedMediaRef: replacedMediaRef,
    );
  }

  Future<bool> _save({
    required Ticket ticket,
    required Future<bool> Function(Ticket ticket) persist,
    required String? replacedMediaRef,
  }) async {
    final String newRef;
    try {
      newRef = await mediaStore.commit(stagedMedia);
    } on Object {
      await mediaStore.discard(stagedMedia);
      return false;
    }

    final json = ticket.toJson()
      ..['localMediaRef'] = newRef
      ..remove('imageDataUrl')
      ..remove('scannedText');
    final updated = Ticket.fromJson(json);

    try {
      final persisted = await persist(updated);
      if (!persisted) {
        await mediaStore.delete(newRef);
        return false;
      }
    } on Object {
      await mediaStore.delete(newRef);
      return false;
    }

    if (replacedMediaRef != null && replacedMediaRef != newRef) {
      await mediaStore.delete(replacedMediaRef);
    }
    return true;
  }

  Future<void> cancel() async {
    if (_isTerminal) {
      return;
    }
    _isTerminal = true;
    await mediaStore.discard(stagedMedia);
  }
}

String _extensionFor(XFile picked) {
  final name = picked.name;
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex > 0 && dotIndex < name.length - 1) {
    return normalizeTicketMediaExtension(name.substring(dotIndex + 1));
  }

  switch (picked.mimeType?.split(';').first.trim().toLowerCase()) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
  }
  throw ArgumentError.value(
    picked.name,
    'picked.name',
    'Bilet medyası için desteklenen bir uzantı bulunamadı.',
  );
}
