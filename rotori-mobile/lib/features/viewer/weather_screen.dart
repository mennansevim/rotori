// Hava Durumu ekranı — **rota boyunca** gün gün hava (Open-Meteo, anahtar YOK).
//
// Eskiden burada tek bir şehrin (ilk lat/lng'li destinasyon, yoksa Tokyo) ham
// günlük tahmini listeleniyordu. Çok şehirli bir gezide bu yanlıştı: 5. gün
// Kyoto'dayken Tokyo'nun havası gösteriliyordu.
//
// Artık liste planın kendi günlerinden türer ve her satır o gün **bulunulan
// şehrin** tahminini taşır. Eşleştirme `domain/trip_forecast.dart` içindeki
// saf `buildRouteForecast` ile yapılır — gün kartlarındaki hava rozeti de
// aynı fonksiyonu kullanır, böylece iki yüzey sapamaz.
//
// Ağ çağrısı [weatherFetcherProvider] üzerinden yapılır; testlerde bu provider
// sahte bir fonksiyonla override edilerek yüklenmiş durum ağsız render edilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/weather_service.dart';
import '../../domain/trip_forecast.dart';
import '../../domain/types.dart';
import 'viewer_theme.dart';

// ---------------------------------------------------------------------------
// Tarih yardımcıları — dile göre ay/gün dizisi (intl'e bağlı DEĞİL).
// ---------------------------------------------------------------------------

/// "2026-07-13" → ("13 Temmuz"/"13 July", "Pazartesi"/"Monday"). Parse
/// edilemezse (isoDate, '').
(String dayLabel, String weekday) _formatDay(String isoDate, AppLang lang) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return (isoDate, '');
  final months = L10n.monthsFor(lang);
  final weekdays = L10n.weekdaysFor(lang);
  final day = lang == AppLang.en
      ? '${months[d.month]} ${d.day}'
      : '${d.day} ${months[d.month]}';
  return (day, weekdays[d.weekday]);
}

/// Bugünün yerel tarihi YYYY-MM-DD (aktif günü vurgulamak için).
String _todayIso() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

// ---------------------------------------------------------------------------
// Servis enjeksiyonu — test override noktası.
// ---------------------------------------------------------------------------

typedef ForecastFetcher = Future<List<DayForecast>> Function(
  double lat,
  double lng,
);

/// Varsayılan: gerçek Open-Meteo çağrısı. Testlerde override edilir.
final weatherFetcherProvider = Provider<ForecastFetcher>((ref) => fetchForecast);

/// Konuma göre tahmini çözer. Family anahtarı named record (eşitlik/cache için).
final forecastProvider =
    FutureProvider.family<List<DayForecast>, ({double lat, double lng})>(
  (ref, coords) => ref.watch(weatherFetcherProvider)(coords.lat, coords.lng),
);

// ---------------------------------------------------------------------------
// Ekran kökü — tema + palet scope sarmalayıcı.
// ---------------------------------------------------------------------------

class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(viewerPaletteProvider);
    return Theme(
      data: palette.toThemeData(),
      child: ViewerPaletteScope(
        palette: palette,
        child: _WeatherView(trip: trip),
      ),
    );
  }
}

class _WeatherView extends ConsumerWidget {
  const _WeatherView({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ViewerPalette.of(context);
    final s = LanguageScope.of(context);

    // Rotadaki her ayrı şehir için tek çağrı. `forecastProvider` koordinat
    // bazında önbelleklidir; aynı şehri iki kez çekmeyiz.
    final destinations = trip.preferences.destinations;
    final targets = distinctForecastDestinations(destinations);

    Widget scaffold(Widget body) => Scaffold(
          backgroundColor: palette.bg,
          appBar: AppBar(
            leading: const BackButton(),
            title: Text(
              s.s('weather.title'),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            backgroundColor: palette.card,
            foregroundColor: palette.textPrimary,
            elevation: 0,
          ),
          body: body,
        );

    // Koordinatı olan hiçbir destinasyon yok — çekilecek bir şey de yok.
    if (targets.isEmpty) {
      return scaffold(
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [_EmptyCard(palette: palette)],
        ),
      );
    }

    final requests = targets
        .map((d) => (lat: d.lat!, lng: d.lng!))
        .toList(growable: false);
    final asyncs = requests.map((c) => ref.watch(forecastProvider(c))).toList();

    if (asyncs.any((a) => a.isLoading)) {
      return scaffold(_Loading(palette: palette));
    }

    // Kısmi hata toleransı: bir şehrin çağrısı düşerse ekranı boşaltmayız,
    // yalnız o şehrin günleri veri-yok olarak görünür. Hepsi düştüyse hata.
    if (asyncs.every((a) => a.hasError)) {
      return scaffold(_ErrorView(
        palette: palette,
        onRetry: () {
          for (final c in requests) {
            ref.invalidate(forecastProvider(c));
          }
        },
      ));
    }

    final byDestination = <String, List<DayForecast>>{};
    for (var i = 0; i < targets.length; i++) {
      final value = asyncs[i].valueOrNull;
      if (value != null) byDestination[targets[i].id] = value;
    }

    // Günler üretilmemişse (taslak plan) gezi tarih aralığından türet —
    // ekran yine rota-farkındalıklı kalır, boşalmaz.
    final rows = trip.days.isNotEmpty
        ? buildRouteForecast(
            days: trip.days,
            destinations: destinations,
            forecastsByDestinationId: byDestination,
          )
        : buildRouteForecastFromDateRange(
            startIso: trip.tripStart,
            endIso: trip.tripEnd,
            destinations: destinations,
            forecastsByDestinationId: byDestination,
          );

    return scaffold(_RouteForecastList(rows: rows, palette: palette));
  }
}

// ---------------------------------------------------------------------------
// Durumlar: yükleniyor / hata.
// ---------------------------------------------------------------------------

class _Loading extends StatelessWidget {
  const _Loading({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: palette.accent),
          const SizedBox(height: 16),
          Text(
            LanguageScope.of(context).s('weather.loading'),
            style: TextStyle(color: palette.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.palette, required this.onRetry});
  final ViewerPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌧️', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              s.s('weather.error'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(s.s('weather.retry')),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Veri: şehir başlığı + kart listesi + kaynak notu.
// ---------------------------------------------------------------------------

/// Rota boyunca gün gün hava — şehir başlıkları altında gruplanmış.
class _RouteForecastList extends StatelessWidget {
  const _RouteForecastList({required this.rows, required this.palette});

  final List<RouteDayForecast> rows;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final today = _todayIso();

    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [_EmptyCard(palette: palette)],
      );
    }

    final segments = groupRouteForecastByCity(rows);
    final cities = segments
        .map((seg) => seg.city)
        .where((c) => c.isNotEmpty)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Row(
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                cities.isEmpty ? s.s('weather.title') : cities.join('  →  '),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          s.s('weather.routeSubtitle'),
          style: TextStyle(color: palette.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 18),
        // Tek şehirli gezide blok başlığı üstteki büyük başlıkla aynı şeyi
        // yazardı; gruplanacak bir şey de yok. O yüzden yalnız çok bloklu
        // rotalarda başlık çizilir.
        for (var i = 0; i < segments.length; i++) ...[
          if (segments.length > 1) ...[
            if (i > 0) const SizedBox(height: 22),
            _CitySectionHeader(segment: segments[i], palette: palette),
            const SizedBox(height: 10),
          ],
          for (final row in segments[i].days)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DayRow(
                row: row,
                palette: palette,
                isActive: row.date == today,
              ),
            ),
        ],
        const SizedBox(height: 8),
        Center(
          child: Text(
            s.s('weather.source'),
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Şehir bloğunun başlığı: ad + tarih aralığı + gün sayısı.
class _CitySectionHeader extends StatelessWidget {
  const _CitySectionHeader({required this.segment, required this.palette});

  final RouteCitySegment segment;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final p = palette;
    final hasCity = segment.city.isNotEmpty;
    final title = hasCity ? segment.city : s.s('weather.unknownCity');
    final range = _formatDateRange(segment.startDate, segment.endDate, s.lang);

    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: hasCity ? p.accent : p.textMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$range · ${s.p('weather.dayCount', {'n': '${segment.dayCount}'})}',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// "15–17 Eki" / "Oct 15–17". Tek günlük blokta yalnız o gün yazılır.
String _formatDateRange(String startIso, String endIso, AppLang lang) {
  final a = DateTime.tryParse(startIso);
  final b = DateTime.tryParse(endIso);
  if (a == null || b == null) return '';
  final months = L10n.monthsShortFor(lang);
  final sameMonth = a.month == b.month && a.year == b.year;

  if (a == b) {
    return lang == AppLang.en
        ? '${months[a.month]} ${a.day}'
        : '${a.day} ${months[a.month]}';
  }
  if (sameMonth) {
    return lang == AppLang.en
        ? '${months[a.month]} ${a.day}–${b.day}'
        : '${a.day}–${b.day} ${months[a.month]}';
  }
  return lang == AppLang.en
      ? '${months[a.month]} ${a.day} – ${months[b.month]} ${b.day}'
      : '${a.day} ${months[a.month]} – ${b.day} ${months[b.month]}';
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.row,
    required this.palette,
    required this.isActive,
  });

  final RouteDayForecast row;
  final ViewerPalette palette;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final lang = s.lang;
    final forecast = row.forecast;
    // Veri yoksa uydurmuyoruz: nötr ikon + "veri yok" etiketi.
    final (emoji, labelKey) = forecast == null
        ? ('—', 'weather.noData')
        : weatherInfo(forecast.code);
    final (dayLabel, weekday) = _formatDay(row.date, lang);
    final tempStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? palette.cardHover : palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? palette.accent.withValues(alpha: 0.55) : palette.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Tarih.
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        dayLabel,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          s.s('weather.today'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (weekday.isNotEmpty)
                  Text(
                    weekday,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                // Şehir artık blok başlığında; satırda tekrar edilmez.
                Text(
                  s.p('weather.dayNumber', {'n': '${row.dayNumber}'}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Emoji.
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          // Etiket + yağış.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.s(labelKey),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (forecast?.precipProb != null)
                  Text(
                    '💧${forecast!.precipProb}%',
                    style: TextStyle(
                      color: palette.sky,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          // Sıcaklıklar — veri yoksa hiç gösterilmez.
          if (forecast != null)
            Row(
              children: [
                Text('↑${forecast.tempMax.round()}°', style: tempStyle),
                const SizedBox(width: 8),
                Text(
                  '↓${forecast.tempMin.round()}°',
                  style: tempStyle.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.palette});
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        LanguageScope.of(context).s('weather.empty'),
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.textSecondary),
      ),
    );
  }
}
