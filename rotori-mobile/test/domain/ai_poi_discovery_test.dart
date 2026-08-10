import 'package:flutter_test/flutter_test.dart';
import 'package:rotori/domain/ai_poi_discovery.dart';

void main() {
  const policy = CostOptimizedPoiDiscoveryPolicy();

  test('yeterli güncel katalogda AI çağrısı yapmaz', () {
    const context = AiPoiDiscoveryContext(
      userApprovedAiDiscovery: true,
      catalogCandidateCount: 20,
      minimumCandidateCount: 8,
      callsForTrip: 0,
    );
    expect(policy.shouldDiscover(context), isFalse);
  });

  test('katalog yetersizse kullanıcı onayıyla tek keşif çağrısına izin verir',
      () {
    const context = AiPoiDiscoveryContext(
      userApprovedAiDiscovery: true,
      catalogCandidateCount: 3,
      minimumCandidateCount: 8,
      callsForTrip: 0,
    );
    expect(policy.shouldDiscover(context), isTrue);
  });

  test('onay yoksa veya cache varsa AI çağrısı yapmaz', () {
    const withoutApproval = AiPoiDiscoveryContext(
      userApprovedAiDiscovery: false,
      catalogCandidateCount: 0,
      minimumCandidateCount: 8,
      callsForTrip: 0,
      userRequestedFreshSuggestions: true,
    );
    const cached = AiPoiDiscoveryContext(
      userApprovedAiDiscovery: true,
      catalogCandidateCount: 0,
      minimumCandidateCount: 8,
      callsForTrip: 0,
      cacheHit: true,
    );
    expect(policy.shouldDiscover(withoutApproval), isFalse);
    expect(policy.shouldDiscover(cached), isFalse);
  });

  test('gezi başına bir çağrı bütçesini aşmaz', () {
    const context = AiPoiDiscoveryContext(
      userApprovedAiDiscovery: true,
      catalogCandidateCount: 0,
      minimumCandidateCount: 8,
      callsForTrip: 1,
    );
    expect(policy.shouldDiscover(context), isFalse);
  });
}
