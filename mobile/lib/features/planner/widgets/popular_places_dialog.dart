import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../domain/explore.dart';
import '../../../domain/japan_suggestions.dart';
import '../../../domain/place_guide.dart';
import '../../../domain/types.dart';
import '../planner_theme.dart';

/// "Gezi planı oluştur"a basıldığında açılan popüler yerler popup'ının sonucu.
/// [mustSeeNames] seçilen yerlerin adları (mustSee'ye eklenir),
/// [citiesToAdd] rota dışı olup kullanıcının onayladığı şehirler (rotaya eklenir).
class PopularPlacesResult {
  PopularPlacesResult(this.mustSeeNames, this.citiesToAdd);
  final List<String> mustSeeNames;
  final List<String> citiesToAdd;
}

/// Popüler gezilecek yerler popup'ı — kullanıcı plan üretmeden önce eklemek
/// istediği yerleri seçer. Seçtiği yer rota şehirlerinde değilse önce şehir
/// eklenmesi için onay ister. Eskiden ExploreStep içinde inline gösterilirdi.
class PopularPlacesDialog extends StatefulWidget {
  const PopularPlacesDialog({super.key, required this.trip});
  final Trip trip;

  @override
  State<PopularPlacesDialog> createState() => _PopularPlacesDialogState();
}

class _PopularPlacesDialogState extends State<PopularPlacesDialog> {
  /// Seçili yerlerin id'leri.
  final Set<String> _selected = {};

  /// Rota dışı olup kullanıcının bu oturumda eklenmeye onayladığı şehirler
  /// (orijinal ad — normalize karşılaştırma _cityKnown içinde yapılır).
  final Set<String> _citiesToAdd = {};

  /// "Osaka (Kansai)" → "osaka" — parantez içeriğini at, küçük harfe indir.
  String _normCity(String c) =>
      c.replaceAll(RegExp(r'\(.*?\)'), '').toLowerCase().trim();

  /// Rota şehirleri (normalize).
  late final Set<String> _routeCities = {
    for (final d in widget.trip.preferences.destinations)
      if (d.city.trim().isNotEmpty) _normCity(d.city),
  };

  /// Bir şehir rota şehirlerinde mi ya da bu oturumda onaylandı mı?
  bool _cityKnown(String city) {
    final n = _normCity(city);
    if (n.isEmpty) return true;
    if (_routeCities.contains(n)) return true;
    return _citiesToAdd.any((c) => _normCity(c) == n);
  }

  /// Rota şehrindeki yerler önce gelecek şekilde sıralı liste.
  List<PlaceSuggestion> get _orderedPlaces {
    final inRoute = <PlaceSuggestion>[];
    final rest = <PlaceSuggestion>[];
    for (final p in kJapanPopular) {
      if (_routeCities.contains(_normCity(p.city))) {
        inRoute.add(p);
      } else {
        rest.add(p);
      }
    }
    return [...inRoute, ...rest];
  }

  Future<void> _onTapPlace(PlaceSuggestion p) async {
    // Zaten seçiliyse çıkar.
    if (_selected.contains(p.id)) {
      setState(() => _selected.remove(p.id));
      return;
    }
    // Şehri bilinen (rota veya onaylı) ise doğrudan seç.
    if (_cityKnown(p.city)) {
      setState(() => _selected.add(p.id));
      return;
    }
    // Rota dışı şehir → önce onay iste.
    final s = LanguageScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.s('popular.cityWarn.title')),
        content: Text(
            s.p('popular.cityWarn.body', {'city': p.city, 'place': p.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.s('popular.cityWarn.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.s('popular.cityWarn.confirm'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _citiesToAdd.add(p.city);
      _selected.add(p.id);
    });
  }

  void _skip() => Navigator.pop(context, null);

  void _confirm() {
    final ordered = _orderedPlaces;
    final names = [
      for (final p in ordered)
        if (_selected.contains(p.id)) p.name,
    ];
    Navigator.pop(
        context, PopularPlacesResult(names, _citiesToAdd.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final places = _orderedPlaces;

    return Dialog(
      backgroundColor: PT.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PT.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.s('popular.title'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PT.text)),
              const SizedBox(height: 4),
              Text(s.s('popular.sub'),
                  style: const TextStyle(
                      fontSize: 13, color: PT.textSecondary, height: 1.4)),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                  children: [
                    for (final p in places)
                      _PopularPlaceCard(
                        emoji: p.emoji,
                        name: p.name,
                        city: p.city,
                        rating: placeRating(p),
                        kidFriendly: isKidFriendly(p),
                        // Görsel place_guide'ın küratörlü (Wikimedia) fotoğrafından
                        // gelir — mekana birebir uyumlu. Rehber yoksa emoji fallback.
                        imageUrl: _placeCardImage(p.name),
                        selected: _selected.contains(p.id),
                        onTap: () => _onTapPlace(p),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _skip,
                    child: Text(s.s('popular.skip'),
                        style: const TextStyle(color: PT.textSecondary)),
                  ),
                  const Spacer(),
                  PButton(label: s.s('popular.confirm'), onPressed: _confirm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "⭐ Popüler gezilecek yerler" bölümüne özel kompakt kart — 2-sütun grid için.
/// Emoji + ad (bold 14, 2 satır ellipsis) + puan (12 gold) + şehir (12 muted).
/// Popüler yer kartının görseli: place_guide'daki gerçek (Wikimedia) fotoğraf.
/// Eşleşen rehber yoksa null → kart emoji gradient fallback gösterir.
String? _placeCardImage(String name) {
  final g = matchPlaceGuide(name);
  return (g != null && g.imageUrls.isNotEmpty) ? g.imageUrls.first : null;
}

class _PopularPlaceCard extends StatelessWidget {
  const _PopularPlaceCard({
    required this.emoji,
    required this.name,
    required this.city,
    required this.rating,
    required this.kidFriendly,
    required this.selected,
    required this.onTap,
    this.imageUrl,
  });

  final String emoji;
  final String name;
  final String city;
  final double? rating;
  final bool kidFriendly;
  final bool selected;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PT.accentSoft : PT.bgSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PT.radius),
        side: BorderSide(color: selected ? PT.accent : PT.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(PT.radius),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Görsel bandı (5:3) — emoji fallback / kid + selected overlay.
            AspectRatio(
              aspectRatio: 5 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Görsel varsa Image; her durumda (loading/error/yok) emoji
                  // gradient fallback görünür — böylece boş kart olmaz.
                  if (imageUrl != null)
                    Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      frameBuilder: (_, child, frame, wasSync) {
                        if (wasSync || frame != null) return child;
                        return _EmojiFallback(emoji: emoji);
                      },
                      errorBuilder: (_, __, ___) => _EmojiFallback(emoji: emoji),
                    )
                  else
                    _EmojiFallback(emoji: emoji),
                  // Sağ üstte kid + selected rozetleri.
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (kidFriendly)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('🧸',
                                style: TextStyle(fontSize: 11)),
                          ),
                        if (kidFriendly && selected) const SizedBox(width: 4),
                        if (selected)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: PT.accent,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.check,
                                size: 14, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: PT.text,
                    ),
                  ),
                  if (rating != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('${ratingStars(rating!)} $rating',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB8860B))),
                    ),
                  if (city.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: PT.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Görsel yükleme başarısızsa/URL yoksa emoji'yi büyük gösteren fallback.
class _EmojiFallback extends StatelessWidget {
  const _EmojiFallback({required this.emoji});
  final String emoji;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCE4EC), Color(0xFFE1BEE7)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 38)),
    );
  }
}
