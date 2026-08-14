// Geliştirici araçlarının görünürlüğü.
//
// **Neden bayrak:** Drawer'daki "Premium (debug)" anahtarı `kDebugMode` ile
// korunuyordu. Önizleme hedefi (`flutter run --release -t
// lib/preview_main.dart`) release derlendiği için anahtar orada HİÇ
// görünmüyordu — yani premium'un arkasındaki ekranlar önizlemede denenemiyordu.
// `kDebugMode` kaldırılırsa anahtar mağazadaki üretim yapısına da giderdi ve
// premium'u herkes açabilirdi.
//
// Bayrak yalnız `preview_main.dart` içinde açılır; üretim girişi
// (`lib/main.dart`) hiç dokunmaz, dolayısıyla release üretim yapısında
// varsayılan `false` kalır.
library;

import 'package:flutter/foundation.dart';

bool _previewTools = false;

/// Önizleme (veya debug) yapısında mıyız — geliştirici anahtarları görünür mü?
bool get showDebugTools => kDebugMode || _previewTools;

/// Önizleme girişinden çağrılır. Üretim girişi çağırmaz.
void enablePreviewDebugTools() => _previewTools = true;
