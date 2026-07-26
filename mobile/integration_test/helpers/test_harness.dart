import 'package:japan_trip/core/router.dart';

class FlowState {
  FlowState({required this.loggedIn, required this.location});

  final bool loggedIn;
  final String location;
}

String applyAuthGuard({required bool loggedIn, required String location}) {
  return resolveAuthRedirect(
        loggedIn: loggedIn,
        matchedLocation: location,
      ) ??
      location;
}

FlowState launchApp({required bool loggedIn}) {
  // Uygulama başlangıcı varsayılan olarak '/'.
  final resolved = applyAuthGuard(loggedIn: loggedIn, location: '/');
  return FlowState(loggedIn: loggedIn, location: resolved);
}

FlowState logoutFrom(FlowState state) {
  final resolved = applyAuthGuard(loggedIn: false, location: state.location);
  return FlowState(loggedIn: false, location: resolved);
}

class FakePlansDataSource {
  FakePlansDataSource({required this.localPlanIds, required this.remoteFails});

  final List<String> localPlanIds;
  final bool remoteFails;

  List<String> visiblePlans() {
    // Prod davranışının kritik beklentisi: uzak kaynak hata verse de local'den
    // ekran boş kalmamalı.
    if (remoteFails) return List<String>.from(localPlanIds);
    return List<String>.from(localPlanIds);
  }
}
