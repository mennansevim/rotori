import 'dart:async';

import '../../domain/plan_schedule_engine.dart';
import '../../domain/types.dart';

typedef PlanPersist = Future<void> Function(Trip trip);
typedef PlanEditListener = void Function(PlanEditState state);

class PlanEditState {
  const PlanEditState({
    required this.trip,
    this.isSaving = false,
    this.canUndo = false,
    this.lastFailure,
    this.lastChanges = const [],
    this.saveFailed = false,
  });

  final Trip trip;
  final bool isSaving;
  final bool canUndo;
  final PlanEditFailure? lastFailure;
  final List<PlanChange> lastChanges;
  final bool saveFailed;
}

/// Bir planın düzenleme oturumunu seri hale getirir.
///
/// Domain doğrulaması başarılıysa UI hemen güncellenir. Yerel persistence
/// yazımı hata verirse snapshot geri yüklenir. Uzak ağ hatası repository
/// tarafından dirty kayıt olarak tutulduğundan offline düzenleme korunur.
class PlanEditSession {
  PlanEditSession({
    required Trip initialTrip,
    required PlanPersist persist,
    required PlanEditListener onChanged,
    this.engine = const PlanScheduleEngine(),
    this.maxUndo = 20,
  })  : _trip = _clone(initialTrip),
        _persist = persist,
        _onChanged = onChanged;

  final PlanScheduleEngine engine;
  final int maxUndo;
  final PlanPersist _persist;
  final PlanEditListener _onChanged;
  final List<Trip> _undo = [];
  Trip _trip;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Trip get current => _trip;
  bool get canUndo => _undo.isNotEmpty;

  Future<PlanEditResult> execute(PlanEditCommand command) {
    final completer = Completer<PlanEditResult>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        completer.complete(PlanEditResult.failure(const PlanEditFailure(
          PlanEditFailureCode.activityNotFound,
          message: 'Düzenleme oturumu kapandı.',
        )));
        return;
      }
      final before = _clone(_trip);
      final result = engine.apply(_trip, command);
      if (!result.isSuccess) {
        _emit(lastFailure: result.failure);
        completer.complete(result);
        return;
      }
      _pushUndo(before);
      _trip = result.trip!;
      _emit(isSaving: true, changes: result.changes);
      try {
        await _persist(_clone(_trip));
        _emit(changes: result.changes);
        completer.complete(result);
      } on Object {
        _trip = before;
        if (_undo.isNotEmpty) _undo.removeLast();
        _emit(
          saveFailed: true,
          lastFailure: const PlanEditFailure(
            PlanEditFailureCode.activityNotFound,
            message: 'Değişiklik kaydedilemedi; plan eski haline getirildi.',
          ),
        );
        completer.complete(PlanEditResult.failure(const PlanEditFailure(
          PlanEditFailureCode.activityNotFound,
          message: 'Değişiklik kaydedilemedi; plan eski haline getirildi.',
        )));
      }
    });
    return completer.future;
  }

  Future<bool> undo() {
    final completer = Completer<bool>();
    _tail = _tail.then((_) async {
      if (_disposed || _undo.isEmpty) {
        completer.complete(false);
        return;
      }
      final beforeUndo = _clone(_trip);
      final restored = _undo.removeLast();
      _trip = _clone(restored);
      _emit(isSaving: true);
      try {
        await _persist(_clone(_trip));
        _emit();
        completer.complete(true);
      } on Object {
        _trip = beforeUndo;
        _undo.add(restored);
        _emit(
          saveFailed: true,
          lastFailure: const PlanEditFailure(
            PlanEditFailureCode.activityNotFound,
            message: 'Geri alma kaydedilemedi.',
          ),
        );
        completer.complete(false);
      }
    });
    return completer.future;
  }

  /// Realtime'dan daha yeni plan geldiğinde, bekleyen yazım yoksa oturumu
  /// güvenle yeniler. Aktif local komut kuyruğunu uzaktan gelen veri ezmez.
  void replaceFromRemote(Trip trip) {
    _tail = _tail.then((_) {
      if (_disposed) return;
      _trip = _clone(trip);
      _undo.clear();
      _emit();
    });
  }

  void dispose() {
    _disposed = true;
  }

  void _pushUndo(Trip trip) {
    _undo.add(_clone(trip));
    if (_undo.length > maxUndo) _undo.removeAt(0);
  }

  void _emit({
    bool isSaving = false,
    bool saveFailed = false,
    PlanEditFailure? lastFailure,
    List<PlanChange> changes = const [],
  }) {
    if (_disposed) return;
    _onChanged(PlanEditState(
      trip: _trip,
      isSaving: isSaving,
      canUndo: canUndo,
      lastFailure: lastFailure,
      lastChanges: changes,
      saveFailed: saveFailed,
    ));
  }

  static Trip _clone(Trip trip) => Trip.fromJson(trip.toJson());
}
