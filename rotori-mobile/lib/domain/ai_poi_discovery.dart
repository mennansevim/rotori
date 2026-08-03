/// AI yalnız aday POI keşfi/kişiselleştirmesi için kullanılır; gün ataması,
/// ulaşım, saat kontrolü ve sıralama deterministik optimizer'ın işidir.
class AiPoiDiscoveryContext {
  const AiPoiDiscoveryContext({
    required this.userApprovedAiDiscovery,
    required this.catalogCandidateCount,
    required this.minimumCandidateCount,
    required this.callsForTrip,
    this.userRequestedFreshSuggestions = false,
    this.catalogIsStale = false,
    this.hasUnresolvedSpecialInterest = false,
    this.cacheHit = false,
  })  : assert(catalogCandidateCount >= 0),
        assert(minimumCandidateCount >= 0),
        assert(callsForTrip >= 0);

  final bool userApprovedAiDiscovery;
  final int catalogCandidateCount;
  final int minimumCandidateCount;
  final int callsForTrip;
  final bool userRequestedFreshSuggestions;
  final bool catalogIsStale;
  final bool hasUnresolvedSpecialInterest;
  final bool cacheHit;
}

class CostOptimizedPoiDiscoveryPolicy {
  const CostOptimizedPoiDiscoveryPolicy({
    this.maximumCallsPerTrip = 1,
    this.maximumInputTokens = 1200,
    this.maximumOutputTokens = 600,
  })  : assert(maximumCallsPerTrip >= 0),
        assert(maximumInputTokens >= 0),
        assert(maximumOutputTokens >= 0);

  final int maximumCallsPerTrip;
  final int maximumInputTokens;
  final int maximumOutputTokens;

  bool shouldDiscover(AiPoiDiscoveryContext context) {
    if (!context.userApprovedAiDiscovery || context.cacheHit) return false;
    if (context.callsForTrip >= maximumCallsPerTrip) return false;
    return context.userRequestedFreshSuggestions ||
        context.catalogIsStale ||
        context.hasUnresolvedSpecialInterest ||
        context.catalogCandidateCount < context.minimumCandidateCount;
  }
}

class PoiDiscoveryCacheKey {
  const PoiDiscoveryCacheKey({
    required this.cityIds,
    required this.preferenceHash,
    required this.catalogVersion,
    required this.locale,
  });

  final String cityIds;
  final String preferenceHash;
  final String catalogVersion;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is PoiDiscoveryCacheKey &&
      other.cityIds == cityIds &&
      other.preferenceHash == preferenceHash &&
      other.catalogVersion == catalogVersion &&
      other.locale == locale;

  @override
  int get hashCode =>
      Object.hash(cityIds, preferenceHash, catalogVersion, locale);
}
