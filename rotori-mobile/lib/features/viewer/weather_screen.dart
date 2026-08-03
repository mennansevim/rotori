// Hava Durumu ekranı — hedef şehir için günlük tahmin (Open-Meteo, anahtar YOK).
//
// React viewer'daki WeatherStrip.tsx'in Flutter portu: 5+ günlük şerit,
// emoji + etiket + ↑max ↓min + 💧yağış. Veri gerçek (Open-Meteo). Viewer
// paletine uyumlu (Theme + ViewerPaletteScope), Türkçe UI, web + mobil.
//
// Ağ çağrısı [weatherFetcherProvider] üzerinden yapılır; testlerde bu provider
// sahte bir fonksiyonla override edilerek yüklenmiş durum ağsız render edilir.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/weather_service.dart';
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

  /// İlk lat/lng'si olan destinasyon; yoksa Tokyo. (city, lat, lng) döner.
  ({String city, double lat, double lng}) _destination() {
    final dests = [...trip.preferences.destinations]
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final d in dests) {
      if (d.lat != null && d.lng != null) {
        return (
          city: d.city.isNotEmpty ? d.city : 'Tokyo',
          lat: d.lat!,
          lng: d.lng!,
        );
      }
    }
    return (city: 'Tokyo', lat: 35.68, lng: 139.65);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ViewerPalette.of(context);
    final s = LanguageScope.of(context);
    final dest = _destination();
    final coords = (lat: dest.lat, lng: dest.lng);
    final async = ref.watch(forecastProvider(coords));

    return Scaffold(
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
      body: async.when(
        loading: () => _Loading(palette: palette),
        error: (_, __) => _ErrorView(
          palette: palette,
          onRetry: () => ref.invalidate(forecastProvider(coords)),
        ),
        data: (forecast) => _ForecastList(
          trip: trip,
          city: dest.city,
          forecast: forecast,
          palette: palette,
        ),
      ),
    );
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

class _ForecastList extends StatelessWidget {
  const _ForecastList({
    required this.trip,
    required this.city,
    required this.forecast,
    required this.palette,
  });

  final Trip trip;
  final String city;
  final List<DayForecast> forecast;
  final ViewerPalette palette;

  @override
  Widget build(BuildContext context) {
    final start = trip.tripStart;
    final end = trip.tripEnd;

    // Seyahat tarih aralığıyla kesişen günler; kesişen yoksa ilk 7 gün.
    final overlapping = (start.isNotEmpty && end.isNotEmpty)
        ? forecast
            .where((f) => f.date.compareTo(start) >= 0 && f.date.compareTo(end) <= 0)
            .toList()
        : const <DayForecast>[];
    final shown =
        overlapping.isNotEmpty ? overlapping : forecast.take(7).toList();
    final rangeMatched = overlapping.isNotEmpty;
    final today = _todayIso();
    final s = LanguageScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Row(
          children: [
            const Text('📍', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                city,
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
          rangeMatched
              ? s.s('weather.forecastTravel')
              : s.s('weather.forecastUpcoming'),
          style: TextStyle(color: palette.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          _EmptyCard(palette: palette)
        else
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DayRow(
                forecast: f,
                palette: palette,
                isActive: f.date == today,
              ),
            ),
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

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.forecast,
    required this.palette,
    required this.isActive,
  });

  final DayForecast forecast;
  final ViewerPalette palette;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    final lang = s.lang;
    final (emoji, labelKey) = weatherInfo(forecast.code);
    final (dayLabel, weekday) = _formatDay(forecast.date, lang);
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
            width: 96,
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
                if (forecast.precipProb != null)
                  Text(
                    '💧${forecast.precipProb}%',
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
          // Sıcaklıklar.
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
