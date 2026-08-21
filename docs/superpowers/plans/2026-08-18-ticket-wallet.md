# Rotori Wallet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current ticket row/dialog experience with an Apple-style Rotori Wallet, device-local screenshot/camera import, dynamic user-confirmed extraction, and safe local media lifecycle.

**Architecture:** Ticket scheduling fields remain in the existing `Ticket` domain model, while arbitrary user-confirmed fields become ordered `TicketDetail` records. A platform-neutral local media store owns images, a device-only extraction layer produces candidates, and a coordinator commits or rolls back media around `PlanEditSession` persistence. Focused ticket presentation files replace the ticket widgets currently embedded in `plan_viewer_screen.dart`.

**Tech Stack:** Flutter 3.24+, Dart 3.5+, Riverpod, `image_picker`, `google_mlkit_text_recognition`, `google_mlkit_barcode_scanning`, `path_provider`, `idb_shim`, Flutter widget/unit tests.

## Global Constraints

- Preserve `environment.sdk: '>=3.5.0 <4.0.0'` and `flutter: ">=3.24.0"`.
- Keep all user-facing strings in `lib/core/l10n.dart`; no new hard-coded Turkish or English UI text.
- Never upload ticket images, raw OCR text, QR payloads, or unconfirmed candidates.
- Store native images in app-private storage and web preview images in browser-local IndexedDB.
- Do not write absolute paths or base64 images into synced `Trip` JSON.
- Do not infer `purchased`; the user must select it.
- Keep the viewer bottom navigation mounted while ticket sheets open.
- Preserve old `imageDataUrl` records until migration succeeds.
- Use at least 44×44 logical-pixel targets, semantic labels, Dynamic Type-safe layouts, and reduced-motion behavior.
- Add dependencies compatible with Dart 3.5: `path: ^1.9.1`, `path_provider: ^2.1.6`, `idb_shim: 2.6.1+7`, and `google_mlkit_barcode_scanning: 0.14.1`.
- Follow strict red-green-refactor: every production behavior starts with a failing test.

---

## File Structure

### Create

- `rotori-mobile/lib/features/tickets/domain/ticket_import_models.dart` — extraction candidates, confirmed details mapping, and import result types.
- `rotori-mobile/lib/features/tickets/data/ticket_local_media_store.dart` — public media store contract and conditional factory.
- `rotori-mobile/lib/features/tickets/data/ticket_local_media_store_io.dart` — app-private native file implementation.
- `rotori-mobile/lib/features/tickets/data/ticket_local_media_store_web.dart` — IndexedDB implementation.
- `rotori-mobile/lib/features/tickets/data/ticket_local_media_store_stub.dart` — unsupported/test-safe fallback.
- `rotori-mobile/lib/features/tickets/data/ticket_extractor.dart` — conditional OCR/QR extraction facade.
- `rotori-mobile/lib/features/tickets/data/ticket_extractor_io.dart` — ML Kit text and barcode extraction.
- `rotori-mobile/lib/features/tickets/data/ticket_extractor_stub.dart` — web/manual fallback.
- `rotori-mobile/lib/features/tickets/application/ticket_import_coordinator.dart` — staged import, commit, rollback, and replacement lifecycle.
- `rotori-mobile/lib/features/tickets/presentation/ticket_wallet_view.dart` — large title, empty state, ready/pending grouping.
- `rotori-mobile/lib/features/tickets/presentation/ticket_wallet_cards.dart` — featured, compact, and pending ticket rows.
- `rotori-mobile/lib/features/tickets/presentation/ticket_add_sheet.dart` — source picker and manual/plan entry routing.
- `rotori-mobile/lib/features/tickets/presentation/ticket_import_review_sheet.dart` — dynamic candidate review.
- `rotori-mobile/lib/features/tickets/presentation/ticket_detail_sheet.dart` — view/edit/image replacement/delete.
- `rotori-mobile/test/domain/ticket_model_test.dart`
- `rotori-mobile/test/features/tickets/ticket_local_media_store_test.dart`
- `rotori-mobile/test/features/tickets/ticket_extractor_test.dart`
- `rotori-mobile/test/features/tickets/ticket_import_coordinator_test.dart`
- `rotori-mobile/test/features/tickets/ticket_wallet_view_test.dart`
- `rotori-mobile/test/features/tickets/ticket_sheets_test.dart`

### Modify

- `rotori-mobile/pubspec.yaml` and `rotori-mobile/pubspec.lock` — direct local-storage and barcode dependencies.
- `rotori-mobile/lib/domain/types.dart` — `TicketDetail`, `localMediaRef`, `confirmedDetails`, backward-compatible JSON.
- `rotori-mobile/lib/domain/plan_schedule_engine.dart` — `DeleteTicket` and relationship cleanup.
- `rotori-mobile/lib/features/shared/ticket_support.dart` — deterministic candidate parsing helpers.
- `rotori-mobile/lib/features/shared/place_detail_sheet.dart` — remove direct base64/OCR persistence and delegate to the shared ticket flow.
- `rotori-mobile/lib/features/plans/plan_viewer_screen.dart` — wire the new wallet and sheets; remove old ticket dialog/list classes.
- `rotori-mobile/lib/core/l10n.dart` — wallet, import, review, errors, permissions, and accessibility copy.
- `rotori-mobile/lib/preview_main.dart` — deterministic local-media preview override.
- `rotori-mobile/test/domain/plan_schedule_engine_test.dart`
- `rotori-mobile/test/features/viewer/plan_viewer_test.dart`
- `rotori-mobile/test/features/ticket_support_test.dart`
- `rotori-mobile/test/qa_scenarios_test.dart`
- `docs/CURRENT_TASK.md` — completed implementation and verification evidence.

---

### Task 1: Extend the Ticket Domain and Add Safe Deletion

**Files:**
- Create: `rotori-mobile/test/domain/ticket_model_test.dart`
- Modify: `rotori-mobile/lib/domain/types.dart:242`
- Modify: `rotori-mobile/lib/domain/plan_schedule_engine.dart:272`
- Modify: `rotori-mobile/test/domain/plan_schedule_engine_test.dart`

**Interfaces:**
- Produces: `TicketDetail`, `Ticket.localMediaRef`, `Ticket.confirmedDetails`, `DeleteTicket(ticketId: String)`, and `CityTransitionPlan.copyWith(clearLinkedTicket: bool)`.
- Consumes: Existing `Ticket.fromJson/toJson`, `PlanScheduleEngine.apply`, and `ActivityLockType.ticketedEvent`.

- [ ] **Step 1: Write failing JSON compatibility tests**

Add to `test/domain/ticket_model_test.dart`:

```dart
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
}
```

- [ ] **Step 2: Run the model test and verify RED**

Run: `flutter test test/domain/ticket_model_test.dart`

Expected: compile failure because `TicketDetail`, `localMediaRef`, and `confirmedDetails` do not exist.

- [ ] **Step 3: Implement the backward-compatible model**

Add this public type before `Ticket` and extend its constructor/JSON methods:

```dart
class TicketDetail {
  const TicketDetail({
    required this.id,
    required this.label,
    required this.value,
    this.semanticKey,
  });

  final String id;
  final String? semanticKey;
  final String label;
  final String value;

  factory TicketDetail.fromJson(Map<String, dynamic> json) => TicketDetail(
        id: json['id'] as String,
        semanticKey: json['semanticKey'] as String?,
        label: (json['label'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (semanticKey != null) 'semanticKey': semanticKey,
        'label': label,
        'value': value,
      };
}
```

Add optional `String? localMediaRef` and `List<TicketDetail> confirmedDetails = const []`. Parse malformed detail lists defensively and emit only non-empty collections.

- [ ] **Step 4: Run the model test and verify GREEN**

Run: `flutter test test/domain/ticket_model_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing deletion tests**

Add two tests to `test/domain/plan_schedule_engine_test.dart`:

```dart
test('DeleteTicket removes ticket and clears city transition link', () {
  final trip = tripWith([day(1, [])]);
  trip.days.single.cityTransition = const CityTransitionPlan(
    fromCity: 'Tokyo',
    toCity: 'Kyoto',
    mode: 'shinkansen',
    linkedTicketId: 't1',
  );
  trip.tickets.add(Ticket(
    id: 't1', kind: 'train', label: 'Tokyo → Kyoto', purchased: true,
  ));

  final result = const PlanScheduleEngine().apply(
    trip,
    const DeleteTicket(ticketId: 't1'),
  );

  expect(result.isSuccess, isTrue);
  expect(result.trip!.tickets, isEmpty);
  expect(result.trip!.days.single.cityTransition!.linkedTicketId, isNull);
});

test('DeleteTicket unlocks only its linked ticketed activity', () {
  final locked = item('teamlab', '14:00')
    ..lockType = ActivityLockType.ticketedEvent
    ..fixedStartTime = '14:00'
    ..canChangeTime = false
    ..canReorder = false;
  final trip = tripWith([day(1, [locked])]);
  trip.tickets.add(Ticket(
    id: 't1',
    kind: 'attraction',
    label: 'teamLab',
    purchased: true,
    linkedActivityId: 'teamlab',
  ));

  final result = const PlanScheduleEngine().apply(
    trip,
    const DeleteTicket(ticketId: 't1'),
  );

  final activity = result.trip!.days.single.items.single;
  expect(activity.lockType, ActivityLockType.none);
  expect(activity.fixedStartTime, isNull);
  expect(activity.fixedEndTime, isNull);
  expect(activity.canChangeTime, isTrue);
  expect(activity.canChangeDay, isTrue);
  expect(activity.canReorder, isTrue);
  expect(activity.canDelete, isTrue);
  expect(activity.lockReason, isNull);
});
```

- [ ] **Step 6: Run deletion tests and verify RED**

Run: `flutter test test/domain/plan_schedule_engine_test.dart --plain-name DeleteTicket`

Expected: compile failure because `DeleteTicket` and `clearLinkedTicket` do not exist.

- [ ] **Step 7: Implement deletion at the domain boundary**

Add `DeleteTicket`, dispatch it from `PlanScheduleEngine.apply`, remove the matching ticket, clear any matching transition link, and unlock only an activity whose `lockType` is `ticketedEvent` and whose id equals `ticket.linkedActivityId`. Unlocking clears both fixed times and `lockReason`, restores `canChangeTime`, `canChangeDay`, `canReorder`, and `canDelete`, and sets `lockType` to `none`. Extend `CityTransitionPlan.copyWith` with `bool clearLinkedTicket = false` and set:

```dart
linkedTicketId:
    clearLinkedTicket ? null : (linkedTicketId ?? this.linkedTicketId),
```

- [ ] **Step 8: Run domain tests and commit**

Run:

```bash
flutter test test/domain/ticket_model_test.dart
flutter test test/domain/plan_schedule_engine_test.dart --plain-name DeleteTicket
```

Expected: PASS.

Commit:

```bash
git add rotori-mobile/lib/domain/types.dart rotori-mobile/lib/domain/plan_schedule_engine.dart rotori-mobile/test/domain/ticket_model_test.dart rotori-mobile/test/domain/plan_schedule_engine_test.dart
git commit -m "feat(mobile): extend ticket domain for local wallet"
```

---

### Task 2: Build the Device-Local Media Store

**Files:**
- Modify: `rotori-mobile/pubspec.yaml`
- Modify: `rotori-mobile/pubspec.lock`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_local_media_store.dart`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_local_media_store_io.dart`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_local_media_store_web.dart`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_local_media_store_stub.dart`
- Create: `rotori-mobile/test/features/tickets/ticket_local_media_store_test.dart`

**Interfaces:**
- Produces:

```dart
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
```

- Consumes: `path_provider` on IO and `idb_shim` on web.

- [ ] **Step 1: Add dependency constraints**

Add direct dependencies:

```yaml
  path: ^1.9.1
  path_provider: ^2.1.6
  idb_shim: 2.6.1+7
```

Run: `flutter pub get`

Expected: dependency resolution succeeds without raising the Dart 3.5 floor.

- [ ] **Step 2: Write failing contract tests with an in-memory test store**

Create `test/features/tickets/ticket_local_media_store_test.dart`. Define a private in-memory implementation in the test and assert:

```dart
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

test('discard removes staged bytes and delete removes committed bytes', () async {
  final store = MemoryTicketLocalMediaStore();
  final staged = await store.stage(
    planId: 'p1', ticketId: 't1', bytes: Uint8List(1), extension: 'jpg',
  );
  await store.discard(staged);
  expect(store.stagedCount, 0);

  final next = await store.stage(
    planId: 'p1', ticketId: 't1', bytes: Uint8List(1), extension: 'jpg',
  );
  final ref = await store.commit(next);
  await store.delete(ref);
  expect(await store.read(ref), isNull);
});
```

- [ ] **Step 3: Run the test and verify RED**

Run: `flutter test test/features/tickets/ticket_local_media_store_test.dart`

Expected: compile failure because the contract types do not exist.

- [ ] **Step 4: Implement the contract and conditional factory**

`ticket_local_media_store.dart` exports the stub, IO, or web implementation with conditional exports and exposes a Riverpod provider:

```dart
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
```

Normalize extensions to `jpg`, `png`, or `webp`; reject other values with `ArgumentError`.

- [ ] **Step 5: Implement native app-private storage**

Use `getApplicationSupportDirectory()`. Stage under `ticket-media/tmp/<token>.<ext>`, then commit atomically by rename to a unique `ticket-media/tickets/<planId>/<ticketId>/<mediaId>.<ext>` path. Return `native:tickets/<planId>/<ticketId>/<mediaId>.<ext>`. The unique media id is required so replacement never overwrites the old image before plan persistence succeeds. Resolve only refs beginning with `native:` and reject traversal segments containing `..`.

The critical native path logic is:

```dart
final support = await getApplicationSupportDirectory();
final root = Directory(p.join(support.path, 'ticket-media'));
final mediaId = const Uuid().v4();
final token = '${_safe(planId)}/${_safe(ticketId)}/$mediaId';
final stagedFile = File(p.join(root.path, 'tmp', '$token.$extension'));
await stagedFile.parent.create(recursive: true);
await stagedFile.writeAsBytes(bytes, flush: true);

final finalFile = File(p.join(
  root.path,
  'tickets',
  _safe(planId),
  _safe(ticketId),
  '$mediaId.$extension',
));
await finalFile.parent.create(recursive: true);
await stagedFile.rename(finalFile.path);
return 'native:tickets/${_safe(planId)}/${_safe(ticketId)}/$mediaId.$extension';
```

Import `package:path/path.dart` as `p` and `package:uuid/uuid.dart`; both are direct dependencies.

- [ ] **Step 6: Implement web IndexedDB storage**

Open database `rotori-ticket-media`, version `1`, object store `media`, key path `ref`. Store byte lists and timestamps. Use `web:` refs for committed records and `webtmp:` refs for staged records. `cleanupStale` deletes only staged records older than 24 hours.

Use this record shape and transaction pattern:

```dart
const _dbName = 'rotori-ticket-media';
const _storeName = 'media';

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
  final tx = db.transaction(_storeName, idbModeReadWrite);
  await tx.objectStore(_storeName).put(record);
  await tx.completed;
}
```

Each record is `{'ref': ref, 'bytes': bytes, 'createdAt': milliseconds, 'staged': bool}`. Commit writes the final record and deletes the staged record in one read-write transaction.

- [ ] **Step 7: Run tests and web analysis**

Run:

```bash
flutter test test/features/tickets/ticket_local_media_store_test.dart
flutter analyze lib/features/tickets/data test/features/tickets/ticket_local_media_store_test.dart
flutter build web --release -t lib/preview_main.dart
```

Expected: all pass; web build contains no `dart:io` import leak.

- [ ] **Step 8: Commit**

```bash
git add rotori-mobile/pubspec.yaml rotori-mobile/pubspec.lock rotori-mobile/lib/features/tickets/data rotori-mobile/test/features/tickets/ticket_local_media_store_test.dart
git commit -m "feat(mobile): add device-local ticket media store"
```

---

### Task 3: Produce Dynamic On-Device Extraction Candidates

**Files:**
- Modify: `rotori-mobile/pubspec.yaml`
- Modify: `rotori-mobile/pubspec.lock`
- Create: `rotori-mobile/lib/features/tickets/domain/ticket_import_models.dart`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_extractor.dart`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_extractor_io.dart`
- Create: `rotori-mobile/lib/features/tickets/data/ticket_extractor_stub.dart`
- Modify: `rotori-mobile/lib/features/shared/ticket_support.dart`
- Modify: `rotori-mobile/test/features/ticket_support_test.dart`
- Create: `rotori-mobile/test/features/tickets/ticket_extractor_test.dart`

**Interfaces:**
- Produces:

```dart
enum TicketCandidateType {
  label, date, time, venue, confirmationCode, seat, gate, partySize, url, qr,
}

class TicketImportCandidate {
  const TicketImportCandidate({
    required this.id,
    required this.type,
    required this.value,
    required this.needsReview,
  });
  final String id;
  final TicketCandidateType type;
  final String value;
  final bool needsReview;
}

class TicketExtractionResult {
  const TicketExtractionResult({
    this.candidates = const [],
    this.rawText = '',
    this.qrPayloads = const [],
  });
  final List<TicketImportCandidate> candidates;
  final String rawText;
  final List<String> qrPayloads;
}

abstract interface class TicketExtractor {
  Future<TicketExtractionResult> extract(String imagePath);
}
```

- Consumes: Existing `extractTicketText` behavior, ML Kit text recognition, and ML Kit barcode scanning.

- [ ] **Step 1: Add mobile barcode dependency**

Add:

```yaml
  google_mlkit_barcode_scanning: 0.14.1
```

Run: `flutter pub get`

Expected: package resolves alongside existing ML Kit dependencies and Dart 3.5 constraints.

- [ ] **Step 2: Write failing deterministic parser tests**

Extend `test/features/ticket_support_test.dart`:

```dart
test('candidate parser returns every distinct date and time for review', () {
  final candidates = buildTicketImportCandidates(
    'Purchase 2026-07-01\nVisit 2026-08-17\nDoors 08:30\nEntry 09:00',
    qrPayloads: const [],
  );
  expect(candidates.where((c) => c.type == TicketCandidateType.date),
      hasLength(2));
  expect(candidates.where((c) => c.type == TicketCandidateType.time),
      hasLength(2));
  expect(candidates.every((c) => c.needsReview), isTrue);
});

test('candidate parser keeps QR payload without marking purchase status', () {
  final candidates = buildTicketImportCandidates(
    'Tokyo Disneyland',
    qrPayloads: const ['https://ticket.example/ABC123'],
  );
  expect(candidates.any((c) => c.type == TicketCandidateType.qr), isTrue);
  expect(candidates.any((c) => c.type.name == 'purchased'), isFalse);
});
```

- [ ] **Step 3: Run parser tests and verify RED**

Run: `flutter test test/features/ticket_support_test.dart --plain-name candidate`

Expected: compile failure because candidate types and parser do not exist.

- [ ] **Step 4: Implement candidate types and parser**

Keep `parseTicketInfo` for legacy callers. Add `buildTicketImportCandidates(String text, {required List<String> qrPayloads})` that:

- emits every distinct ISO/slash/dot date and `HH:mm` time;
- emits mixed alphanumeric codes of at least six characters as confirmation-code candidates;
- proposes the first non-empty, non-date line between 3 and 80 characters as a label candidate;
- recognizes localized `seat`/`koltuk`, `gate`/`kapı`, and `person`/`adult`/`kişi` patterns as seat, gate, and party-size candidates;
- emits URL and QR candidates;
- deduplicates by `(type, normalized value)`;
- marks all machine-produced candidates `needsReview: true`;
- never creates a purchased candidate.

The parser returns candidates through one deduplicating helper:

```dart
void addCandidate(
  TicketCandidateType type,
  String rawValue,
) {
  final value = rawValue.trim();
  final identity = '${type.name}:${value.toLowerCase()}';
  if (value.isEmpty || !seen.add(identity)) return;
  candidates.add(TicketImportCandidate(
    id: identity,
    type: type,
    value: value,
    needsReview: true,
  ));
}
```

- [ ] **Step 5: Write failing extractor adapter test**

Create `test/features/tickets/ticket_extractor_test.dart` with a fake raw recognizer and assert `TicketExtractor` combines text and QR into one result while retaining raw text only in memory.

- [ ] **Step 6: Implement conditional extraction**

On IO, run `TextRecognizer` and `BarcodeScanner(formats: [BarcodeFormat.qrCode])` against the same `InputImage`. Close both recognizers in `finally`. On web/stub, return `const TicketExtractionResult()` so manual entry remains available.

```dart
Future<TicketExtractionResult> extractTicketImage(String imagePath) async {
  final input = InputImage.fromFilePath(imagePath);
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  try {
    final results = await Future.wait<Object>([
      textRecognizer.processImage(input),
      barcodeScanner.processImage(input),
    ]);
    final text = (results[0] as RecognizedText).text;
    final qrPayloads = (results[1] as List<Barcode>)
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return TicketExtractionResult(
      rawText: text,
      qrPayloads: qrPayloads,
      candidates: buildTicketImportCandidates(
        text,
        qrPayloads: qrPayloads,
      ),
    );
  } finally {
    await textRecognizer.close();
    await barcodeScanner.close();
  }
}
```

- [ ] **Step 7: Run tests, analyze, and commit**

Run:

```bash
flutter test test/features/ticket_support_test.dart
flutter test test/features/tickets/ticket_extractor_test.dart
flutter analyze lib/features/tickets/data lib/features/tickets/domain
```

Expected: PASS.

Commit:

```bash
git add rotori-mobile/pubspec.yaml rotori-mobile/pubspec.lock rotori-mobile/lib/features/tickets/domain rotori-mobile/lib/features/tickets/data/ticket_extractor* rotori-mobile/lib/features/shared/ticket_support.dart rotori-mobile/test/features/ticket_support_test.dart rotori-mobile/test/features/tickets/ticket_extractor_test.dart
git commit -m "feat(mobile): extract dynamic ticket candidates on device"
```

---

### Task 4: Make Import Commit and Rollback Atomic

**Files:**
- Create: `rotori-mobile/lib/features/tickets/application/ticket_import_coordinator.dart`
- Create: `rotori-mobile/test/features/tickets/ticket_import_coordinator_test.dart`

**Interfaces:**
- Produces:

```dart
class TicketImportSession {
  TicketImportSession({
    required this.stagedMedia,
    required this.extraction,
    required this.mediaStore,
  });
  final StagedTicketMedia stagedMedia;
  final TicketExtractionResult extraction;
  final TicketLocalMediaStore mediaStore;

  Future<bool> save({
    required Ticket ticket,
    required Future<bool> Function(Ticket ticket) persist,
    String? replacedMediaRef,
  });
  Future<void> cancel();
}

class TicketImportCoordinator {
  Future<TicketImportSession?> begin({
    required String planId,
    required String ticketId,
    required XFile? picked,
  });
}
```

- Consumes: `TicketLocalMediaStore`, `TicketExtractor`, `Ticket.localMediaRef`, and a UI-supplied persistence callback.

- [ ] **Step 1: Write failing lifecycle tests**

Cover three cases in `ticket_import_coordinator_test.dart`:

```dart
test('cancel discards staged media', () async {
  final session = await coordinator.begin(
    planId: 'p1', ticketId: 't1', picked: fakeImage,
  );
  await session!.cancel();
  expect(mediaStore.stagedCount, 0);
});

test('save rollback deletes new media when plan persistence fails', () async {
  final session = await coordinator.begin(
    planId: 'p1', ticketId: 't1', picked: fakeImage,
  );
  final saved = await session!.save(
    ticket: ticket,
    persist: (_) async => false,
  );
  expect(saved, isFalse);
  expect(mediaStore.committedCount, 0);
});

test('replacement deletes old media only after successful persistence', () async {
  final session = await coordinator.begin(
    planId: 'p1', ticketId: 't1', picked: fakeImage,
  );
  final saved = await session!.save(
    ticket: ticket,
    replacedMediaRef: 'memory:old',
    persist: (updated) async => updated.localMediaRef != null,
  );
  expect(saved, isTrue);
  expect(mediaStore.deletedRefs, contains('memory:old'));
});
```

- [ ] **Step 2: Run tests and verify RED**

Run: `flutter test test/features/tickets/ticket_import_coordinator_test.dart`

Expected: compile failure because coordinator/session do not exist.

- [ ] **Step 3: Implement the coordinator**

In `begin`, return `null` when the picker was cancelled. Otherwise, read the selected file exactly once with `await picked.readAsBytes()`, derive and normalize the extension from `picked.name`/MIME metadata, stage those bytes, and run extraction against `picked.path` only on supported native platforms. If extraction throws, discard the staged media before returning an error to the UI. Web uses the stub extractor and still stages the picked bytes in IndexedDB for manual review.

Rules in `save`:

1. Commit staged media and create a new `Ticket` through JSON cloning with `localMediaRef` set and `imageDataUrl/scannedText` omitted for new imports.
2. Call `persist(updatedTicket)`.
3. If persistence returns false or throws, delete the new ref and return false.
4. If persistence succeeds, delete `replacedMediaRef` when different from the new ref.
5. Make `save` and `cancel` idempotent with a private terminal-state flag.

Use explicit JSON removal so legacy payloads cannot leak into new saves:

```dart
final newRef = await mediaStore.commit(stagedMedia);
final json = ticket.toJson()
  ..['localMediaRef'] = newRef
  ..remove('imageDataUrl')
  ..remove('scannedText');
final updated = Ticket.fromJson(json);
try {
  final ok = await persist(updated);
  if (!ok) {
    await mediaStore.delete(newRef);
    return false;
  }
  if (replacedMediaRef != null && replacedMediaRef != newRef) {
    await mediaStore.delete(replacedMediaRef);
  }
  return true;
} on Object {
  await mediaStore.delete(newRef);
  return false;
}
```

- [ ] **Step 4: Run lifecycle tests and commit**

Run:

```bash
flutter test test/features/tickets/ticket_import_coordinator_test.dart
flutter analyze lib/features/tickets/application
```

Expected: PASS.

Commit:

```bash
git add rotori-mobile/lib/features/tickets/application rotori-mobile/test/features/tickets/ticket_import_coordinator_test.dart
git commit -m "feat(mobile): make ticket media imports atomic"
```

---

### Task 5: Build the Rotori Wallet List

**Files:**
- Create: `rotori-mobile/lib/features/tickets/presentation/ticket_wallet_view.dart`
- Create: `rotori-mobile/lib/features/tickets/presentation/ticket_wallet_cards.dart`
- Create: `rotori-mobile/test/features/tickets/ticket_wallet_view_test.dart`
- Modify: `rotori-mobile/lib/core/l10n.dart`

**Interfaces:**
- Produces:

```dart
class TicketWalletView extends StatelessWidget {
  const TicketWalletView({
    super.key,
    required this.tickets,
    required this.palette,
    required this.now,
    required this.onAdd,
    required this.onOpen,
    required this.onOpenMedia,
  });
  final List<Ticket> tickets;
  final ViewerPalette palette;
  final DateTime now;
  final VoidCallback onAdd;
  final ValueChanged<Ticket> onOpen;
  final ValueChanged<Ticket> onOpenMedia;
}
```

- Consumes: `Ticket`, `ViewerPalette`, and `LanguageScope`.

- [ ] **Step 1: Write failing hierarchy tests**

Create widget tests asserting these keys:

```dart
expect(find.byKey(const ValueKey('ticket-wallet-title')), findsOneWidget);
expect(find.byKey(const ValueKey('ticket-wallet-featured')), findsOneWidget);
expect(find.byKey(const ValueKey('ticket-wallet-compact-list')), findsOneWidget);
expect(find.byKey(const ValueKey('ticket-wallet-pending-group')), findsOneWidget);
expect(find.byKey(const ValueKey('ticket-wallet-add')), findsOneWidget);
```

Use fixtures with two purchased dated tickets and one unpurchased ticket. Assert the earliest future purchased ticket is featured. Add a separate empty-state test for `ticket-wallet-empty` and `add-first-ticket`.

- [ ] **Step 2: Run wallet tests and verify RED**

Run: `flutter test test/features/tickets/ticket_wallet_view_test.dart`

Expected: compile failure because wallet widgets do not exist.

- [ ] **Step 3: Implement deterministic grouping**

In `ticket_wallet_view.dart`, sort a copied list; never mutate `Trip.tickets`. Ready tickets are `purchased == true`; pending tickets are all others. Feature the earliest ready `visitDate` on or after `now`, falling back to the first ready ticket. Render only the featured ticket large.

```dart
final ready = tickets.where((ticket) => ticket.purchased).toList()
  ..sort((a, b) => _ticketDate(a)?.compareTo(_ticketDate(b) ?? _maxDate) ?? 1);
final pending = tickets.where((ticket) => !ticket.purchased).toList();
final upcoming = ready.where((ticket) {
  final date = _ticketDate(ticket);
  return date != null && !date.isBefore(DateUtils.dateOnly(now));
}).toList();
final featured = upcoming.isNotEmpty
    ? upcoming.first
    : (ready.isEmpty ? null : ready.first);
```

- [ ] **Step 4: Implement Apple-style cards and accessibility**

Use a large content title, a circular 44×44 add target, a featured gradient card, compact ready cards, and an inset pending group. Each card gets a single summary semantic label containing name, date/time if present, and status. QR/media remains a separately labeled 44×44 action. Do not use color as the only status cue.

The top-level build shape is:

```dart
return CustomScrollView(
  key: const ValueKey('ticket-wallet-scroll'),
  slivers: [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      sliver: SliverToBoxAdapter(child: _WalletHeader(onAdd: onAdd)),
    ),
    if (featured != null)
      SliverToBoxAdapter(
        child: TicketWalletCard(
          key: const ValueKey('ticket-wallet-featured'),
          ticket: featured,
          palette: palette,
          onOpen: () => onOpen(featured),
          onOpenMedia: () => onOpenMedia(featured),
        ),
      ),
    if (ready.where((ticket) => ticket.id != featured?.id).isNotEmpty)
      SliverToBoxAdapter(child: TicketCompactList(/* explicit ready items */)),
    if (pending.isNotEmpty)
      SliverToBoxAdapter(child: TicketPendingGroup(tickets: pending)),
  ],
);
```

- [ ] **Step 5: Add localized copy**

Add Turkish/English keys for wallet title, summary fragments, ready, pending, sale countdown, missing information, open ticket image, and empty-state copy. Tests resolve strings through `L10n` rather than hard-coded UI literals.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
flutter test test/features/tickets/ticket_wallet_view_test.dart
flutter analyze lib/features/tickets/presentation/ticket_wallet_view.dart lib/features/tickets/presentation/ticket_wallet_cards.dart
```

Expected: PASS with no overflow at 390px width and text scale 2.0.

Commit:

```bash
git add rotori-mobile/lib/features/tickets/presentation/ticket_wallet_view.dart rotori-mobile/lib/features/tickets/presentation/ticket_wallet_cards.dart rotori-mobile/lib/core/l10n.dart rotori-mobile/test/features/tickets/ticket_wallet_view_test.dart
git commit -m "feat(mobile): add Rotori Wallet ticket list"
```

---

### Task 6: Build Add, Review, and Detail Sheets

**Files:**
- Create: `rotori-mobile/lib/features/tickets/presentation/ticket_add_sheet.dart`
- Create: `rotori-mobile/lib/features/tickets/presentation/ticket_import_review_sheet.dart`
- Create: `rotori-mobile/lib/features/tickets/presentation/ticket_detail_sheet.dart`
- Create: `rotori-mobile/test/features/tickets/ticket_sheets_test.dart`
- Modify: `rotori-mobile/lib/core/l10n.dart`

**Interfaces:**
- Produces:

```dart
enum TicketAddSource { gallery, camera, plan, manual }

class TicketReviewResult {
  const TicketReviewResult(this.ticket);
  final Ticket ticket;
}

enum TicketDetailAction { save, replaceMedia, delete }

class TicketDetailResult {
  const TicketDetailResult({required this.action, this.ticket});
  final TicketDetailAction action;
  final Ticket? ticket;
}

Future<TicketAddSource?> showTicketAddSheet({
  required BuildContext context,
  required ViewerPalette palette,
});

Future<TicketReviewResult?> showTicketImportReviewSheet({
  required BuildContext context,
  required TicketExtractionResult extraction,
  required Ticket initialTicket,
  required ViewerPalette palette,
});

Future<TicketDetailResult?> showTicketDetailSheet({
  required BuildContext context,
  required Ticket ticket,
  required Uint8List? mediaBytes,
  required ViewerPalette palette,
});
```

- Consumes: import candidate types, local media bytes, and localized copy.

- [ ] **Step 1: Write failing source-sheet tests**

Assert the source sheet shows gallery, camera, plan, and manual actions; tapping each returns the matching enum. Assert the sheet uses a drag handle and remains dismissible.

- [ ] **Step 2: Write failing dynamic-review tests**

Use an extraction result containing two dates, one time, and one confirmation code. Assert:

- only those candidate groups appear;
- save is disabled until one date is selected;
- `purchased` starts false;
- removing the confirmation code removes it from `confirmedDetails`;
- an empty extraction still permits manual label entry.

- [ ] **Step 3: Write failing detail-sheet tests**

Assert the detail sheet displays local media when bytes exist, shows `Görseli yeniden ekle` when the ref exists but bytes are null, and returns explicit edit/replace/delete actions.

- [ ] **Step 4: Run sheet tests and verify RED**

Run: `flutter test test/features/tickets/ticket_sheets_test.dart`

Expected: compile failure because sheet APIs do not exist.

- [ ] **Step 5: Implement source and review sheets**

Use `showModalBottomSheet(isScrollControlled: true, showDragHandle: true, useSafeArea: true)`. Keep fields in a scrollable body with a keyboard-safe bottom inset. Read `MediaQuery.disableAnimations` and `accessibleNavigation`; use zero-duration/cross-fade behavior when either is true.

Map selected canonical candidates to `Ticket` fields. Map remaining accepted candidates to `TicketDetail` with stable ids derived from type and normalized value. Never persist `rawText` or unselected QR payloads.

```dart
return showModalBottomSheet<TicketAddSource>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => TicketAddSheetBody(
    palette: palette,
    onSelect: (source) => Navigator.pop(sheetContext, source),
  ),
);
```

When `MediaQuery.disableAnimations` or `accessibleNavigation` is true, pass an `AnimationStyle` with `Duration.zero` forward and reverse durations where supported by the project Flutter version; otherwise rely on the platform sheet transition.

- [ ] **Step 6: Implement detail sheet and destructive confirmation**

Provide edit, image replacement, and delete actions. Delete uses a confirmation only because it removes locally stored media; the confirmation names the ticket. Return an action to the caller rather than mutating the plan inside the widget.

```dart
Navigator.pop(
  context,
  const TicketDetailResult(action: TicketDetailAction.replaceMedia),
);

Navigator.pop(
  context,
  const TicketDetailResult(action: TicketDetailAction.delete),
);
```

- [ ] **Step 7: Add localized copy and run tests**

Run:

```bash
flutter test test/features/tickets/ticket_sheets_test.dart
flutter analyze lib/features/tickets/presentation
```

Expected: PASS at text scale 1.0 and 2.0, with no hidden primary action behind the keyboard.

- [ ] **Step 8: Commit**

```bash
git add rotori-mobile/lib/features/tickets/presentation/ticket_add_sheet.dart rotori-mobile/lib/features/tickets/presentation/ticket_import_review_sheet.dart rotori-mobile/lib/features/tickets/presentation/ticket_detail_sheet.dart rotori-mobile/lib/core/l10n.dart rotori-mobile/test/features/tickets/ticket_sheets_test.dart
git commit -m "feat(mobile): add ticket import and detail sheets"
```

---

### Task 7: Integrate Wallet, Import, and Place Detail

**Files:**
- Modify: `rotori-mobile/lib/features/plans/plan_viewer_screen.dart:914-940,997-1055,3022-3240`
- Modify: `rotori-mobile/lib/features/shared/place_detail_sheet.dart:304-470`
- Modify: `rotori-mobile/lib/preview_main.dart`
- Modify: `rotori-mobile/test/features/viewer/plan_viewer_test.dart`
- Modify: `rotori-mobile/test/qa_scenarios_test.dart`

**Interfaces:**
- Consumes: `TicketWalletView`, sheet functions, `TicketImportCoordinator`, `TicketLocalMediaStore`, `UpsertTicket`, `DeleteTicket`.
- Produces: one shared ticket import flow callable from the Biletler tab and place detail.

- [ ] **Step 1: Write failing viewer integration tests**

Replace the old empty-ticket assertions with wallet keys. Add tests that:

- tap `viewer.quick.tickets` and see the large title plus persistent `viewer-quick-nav`;
- tap `ticket-wallet-add`, select manual, save a label, and see the new ticket;
- open the add sheet and verify `viewer-quick-nav` remains mounted behind it;
- open an existing ticket, delete it, and verify it disappears;
- simulate persistence failure and verify imported media is rolled back.

- [ ] **Step 2: Run viewer tests and verify RED**

Run:

```bash
flutter test test/features/viewer/plan_viewer_test.dart --plain-name Bilet
flutter test test/features/viewer/plan_viewer_test.dart --plain-name ticket
```

Expected: failures on missing wallet/sheet keys.

- [ ] **Step 3: Replace embedded ticket widgets**

Import the new ticket modules. Replace `_TabTicketsView` with `TicketWalletView`; remove `_TicketEditorDraft`, `_TicketEditorDialog`, and `_TabTicketsView`. Keep the `IndexedStack` and bottom navigation unchanged so sheets overlay rather than replace the viewer shell.

```dart
TicketWalletView(
  tickets: trip.tickets,
  palette: palette,
  now: ref.watch(nowProvider),
  onAdd: _openTicketAddFlow,
  onOpen: _openTicketDetails,
  onOpenMedia: _openTicketMedia,
),
```

- [ ] **Step 4: Wire gallery and camera import**

Use `ImagePicker.pickImage` without lossy compression of the original QR-bearing image. Pass bytes and detected extension to `TicketImportCoordinator.begin`. Open `TicketImportReviewSheet`; on confirmation call session `save` with a callback that executes `UpsertTicket` through `_editSession` and returns `result.isSuccess`.

```dart
final picked = await ImagePicker().pickImage(source: source);
final session = await ref.read(ticketImportCoordinatorProvider).begin(
  planId: _trip.id,
  ticketId: newTicketId(),
  picked: picked,
);
if (session == null || !mounted) return;
final review = await showTicketImportReviewSheet(
  context: context,
  extraction: session.extraction,
  initialTicket: seedTicket,
  palette: ViewerPalette.of(context),
);
if (review == null) {
  await session.cancel();
  return;
}
await session.save(
  ticket: review.ticket,
  persist: (ticket) async =>
      (await _editSession.execute(UpsertTicket(ticket: ticket))).isSuccess,
);
```

- [ ] **Step 5: Wire manual and plan selection**

Manual entry opens the same review sheet with an empty extraction and no staged media. Plan selection shows eligible timeline items/city transitions, seeds label/date/time/link fields, and still requires review.

- [ ] **Step 6: Wire detail, replacement, and deletion**

Read image bytes through `TicketLocalMediaStore`. Replacement uses a new import session and passes the existing ref as `replacedMediaRef`. Deletion executes `DeleteTicket`; only after success delete the local ref. On failed delete, keep both ticket and media.

- [ ] **Step 7: Remove duplicate place-detail persistence**

Delete direct base64 encoding, automatic `purchased: true`, and direct raw OCR storage from `place_detail_sheet.dart`. Change its callback contract so it requests the shared import flow with the linked activity as seed context. Preserve the existing `requiresTicket` visibility rule.

Replace the old callback with:

```dart
final Future<bool> Function(TimelineItem item, ImageSource source)?
    onImportTicket;
```

The sheet chooses gallery/camera but delegates staging, extraction, review, and persistence to the viewer callback.

- [ ] **Step 8: Add deterministic preview media overrides**

In `preview_main.dart`, override `ticketLocalMediaStoreProvider` with an in-memory implementation containing a small seeded ticket image. Do not access device permissions in preview.

- [ ] **Step 9: Run integration tests and commit**

Run:

```bash
flutter test test/features/viewer/plan_viewer_test.dart
flutter test test/qa_scenarios_test.dart --plain-name ticket
flutter analyze lib/features/plans/plan_viewer_screen.dart lib/features/shared/place_detail_sheet.dart lib/preview_main.dart
```

Expected: ticket flows pass; the existing quick nav remains present.

Commit:

```bash
git add rotori-mobile/lib/features/plans/plan_viewer_screen.dart rotori-mobile/lib/features/shared/place_detail_sheet.dart rotori-mobile/lib/preview_main.dart rotori-mobile/test/features/viewer/plan_viewer_test.dart rotori-mobile/test/qa_scenarios_test.dart
git commit -m "feat(mobile): integrate Rotori Wallet ticket flow"
```

---

### Task 8: Migrate Legacy Images and Verify the Full Feature

**Files:**
- Modify: `rotori-mobile/lib/features/tickets/application/ticket_import_coordinator.dart`
- Modify: `rotori-mobile/lib/features/tickets/data/ticket_local_media_store.dart`
- Modify: `rotori-mobile/test/features/tickets/ticket_import_coordinator_test.dart`
- Modify: `rotori-mobile/test/features/tickets/ticket_wallet_view_test.dart`
- Modify: `docs/CURRENT_TASK.md`

**Interfaces:**
- Produces: `Future<bool> migrateLegacyTicketMedia({required String planId, required Ticket ticket, required Future<bool> Function(Ticket ticket) persist})` and startup stale-temp cleanup.
- Consumes: legacy `imageDataUrl`, local media store, and plan persistence.

- [ ] **Step 1: Write failing migration tests**

Add tests proving:

```dart
test('legacy data URL is removed only after migrated ticket persists', () async {
  late Ticket persisted;
  final migrated = await coordinator.migrateLegacyTicketMedia(
    planId: 'p1',
    ticket: legacyTicket,
    persist: (ticket) async {
      persisted = ticket;
      return true;
    },
  );
  expect(migrated, isTrue);
  expect(persisted.localMediaRef, isNotNull);
  expect(persisted.imageDataUrl, isNull);
});

test('failed legacy persistence deletes new media and keeps old payload', () async {
  final migrated = await coordinator.migrateLegacyTicketMedia(
    planId: 'p1',
    ticket: legacyTicket,
    persist: (_) async => false,
  );
  expect(migrated, isFalse);
  expect(mediaStore.committedCount, 0);
  expect(legacyTicket.imageDataUrl, isNotNull);
});
```

- [ ] **Step 2: Run migration tests and verify RED**

Run: `flutter test test/features/tickets/ticket_import_coordinator_test.dart --plain-name legacy`

Expected: compile failure because migration API does not exist.

- [ ] **Step 3: Implement migration and stale cleanup**

Decode only valid `data:image/...;base64,` payloads, stage/commit them locally, and build a cloned ticket with `localMediaRef` set and `imageDataUrl` removed. Persist that clone before reporting success. If decoding, staging, committing, or persistence fails, delete any newly committed media and leave the original plan record untouched so the old data URL remains available. Trigger `cleanupStale(now: ref.read(nowProvider))` once during app bootstrap without blocking first paint.

```dart
Future<bool> migrateLegacyTicketMedia({
  required String planId,
  required Ticket ticket,
  required Future<bool> Function(Ticket ticket) persist,
}) async {
  final dataUrl = ticket.imageDataUrl;
  if (ticket.localMediaRef != null || dataUrl == null) return false;
  final match = RegExp(r'^data:image/(png|jpeg|webp);base64,(.+)$')
      .firstMatch(dataUrl);
  if (match == null) return false;
  String? newRef;
  StagedTicketMedia? staged;
  try {
    staged = await mediaStore.stage(
      planId: planId,
      ticketId: ticket.id,
      bytes: base64Decode(match.group(2)!),
      extension: match.group(1) == 'jpeg' ? 'jpg' : match.group(1)!,
    );
    newRef = await mediaStore.commit(staged);
    staged = null;
    final json = ticket.toJson()
      ..['localMediaRef'] = newRef
      ..remove('imageDataUrl');
    final saved = await persist(Ticket.fromJson(json));
    if (!saved) await mediaStore.delete(newRef!);
    return saved;
  } on Object {
    if (staged != null) await mediaStore.discard(staged!);
    if (newRef != null) await mediaStore.delete(newRef!);
    return false;
  }
}
```

- [ ] **Step 4: Add final accessibility and missing-file tests**

Verify:

- wallet cards have semantic status/name labels;
- media action has a separate semantic button label;
- text scale 2.0 produces no overflow;
- reduced motion uses no long-running transition;
- missing local media shows reattach state while preserving ticket metadata.

- [ ] **Step 5: Run the complete ticket-focused suite**

Run:

```bash
flutter test test/domain/ticket_model_test.dart
flutter test test/domain/plan_schedule_engine_test.dart
flutter test test/features/ticket_support_test.dart
flutter test test/features/tickets
flutter test test/features/viewer/plan_viewer_test.dart
flutter test test/qa_scenarios_test.dart --plain-name ticket
flutter analyze
flutter build web --release -t lib/preview_main.dart
```

Expected: all ticket tests pass, analyzer reports no issues, and preview web build succeeds.

- [ ] **Step 6: Perform mobile smoke checks**

On an iOS simulator or device:

1. Add a screenshot from Photos.
2. Add a newly captured camera image.
3. Deny photo permission and continue through manual entry.
4. Cancel review and confirm no ticket appears.
5. Replace an existing image.
6. Delete a ticket and confirm its image is unavailable afterward.
7. Enable Larger Text and Reduce Motion and repeat add/open sheet flows.

Expected: no image leaves the device, navigation remains visible, and every failure path offers a next action.

- [ ] **Step 7: Update project status and commit**

Add a dated entry to `docs/CURRENT_TASK.md` listing implementation, tests, analyzer, web build, and mobile smoke evidence.

Commit:

```bash
git add rotori-mobile/lib/features/tickets rotori-mobile/test/features/tickets docs/CURRENT_TASK.md
git commit -m "test(mobile): verify Rotori Wallet ticket lifecycle"
```

---

## Final Review Gate

Before integration, compare the implementation against every acceptance criterion in `docs/superpowers/specs/2026-08-18-ticket-wallet-design.md`. Confirm that the final diff does not stage unrelated existing workspace changes, especially current edits in auth, drawer, viewer theme, scanner, map, and preview files.
