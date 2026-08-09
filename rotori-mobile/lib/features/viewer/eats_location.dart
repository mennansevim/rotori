// Rotori Eats için "yakınımda" konum kaynağı.
//
// Geofence controller'dan AYRI tutuldu: o, gezi penceresi boyunca sürekli akış
// dinleyen bir motor; burada istenen tek seferlik, ucuz bir konum örneği.
// Eats ekranı "Yakınımda"yı açana kadar bu provider hiç okunmaz — izin
// diyaloğu kullanıcı istemeden çıkmaz.
//
// Test edilebilirlik: [eatsOriginProvider] override edilebilir; widget
// testleri gerçek Geolocator'a hiç dokunmaz.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/geofence.dart' show LatLng;

/// Konum çözümünün sonucu — UI hata durumunu ayırt edebilsin diye enum.
enum EatsLocationState { ok, denied, unavailable }

class EatsOrigin {
  const EatsOrigin(this.state, [this.point]);

  final EatsLocationState state;
  final LatLng? point;

  static const EatsOrigin denied = EatsOrigin(EatsLocationState.denied);
  static const EatsOrigin unavailable = EatsOrigin(EatsLocationState.unavailable);
}

/// Tek seferlik konum örneği. Önce son bilinen konumu dener (anında döner),
/// yoksa 8 saniyelik zaman aşımıyla taze konum ister.
final eatsOriginProvider = FutureProvider.autoDispose<EatsOrigin>((ref) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return EatsOrigin.unavailable;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return EatsOrigin.denied;
    }

    if (!kIsWeb) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return EatsOrigin(
          EatsLocationState.ok,
          LatLng(last.latitude, last.longitude),
        );
      }
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return EatsOrigin(EatsLocationState.ok, LatLng(pos.latitude, pos.longitude));
  } catch (_) {
    return EatsOrigin.unavailable;
  }
});
