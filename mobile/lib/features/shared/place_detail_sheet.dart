// Yer detay popup — hem planner (Plan adımı) hem viewer (gün planları)
// tarafından kullanılır. Temaya uyumlu (açık/koyu) Material bileşenleri.
//
// İçerik: kısa tanıtım, tahmini yürüme adımı, gerçek mesafeye dayalı
// "yakınlarda" önerileri (koordinatlardan hesaplanır), yemek önerileri,
// "haritada aç" butonu ve opsiyonel "düzenle".
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/city_places.dart';
import '../../domain/destination_profiles.dart';
import '../../domain/explore.dart';
import '../../domain/japan_suggestions.dart';
import '../../domain/place_guide.dart';
import '../../domain/trip_factory.dart';
import '../../domain/types.dart';
import 'ticket_ocr.dart';
import 'ticket_support.dart';

/// Bir zaman çizelgesi öğesi için detay popup'ını açar.
/// [onEdit] verilirse "Düzenle" butonu gösterilir (planner); viewer'da null.
/// [existingTicket] varsa bilet kartı gösterilir; yoksa ve [onAddTicket]
/// verilmişse bilet gerektiren yerler için "🎫 Bilet ekle" butonu çıkar.
Future<void> showPlaceDetailSheet({
  required BuildContext context,
  required TimelineItem item,
  required String city,
  String? countryCode,
  VoidCallback? onEdit,
  Ticket? existingTicket,
  void Function(Ticket)? onAddTicket,
}) {
  final profile =
      countryCode != null ? getDestinationProfile(countryCode) : null;
  final hasGuide = matchPlaceGuide(item.title) != null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      // Rehberli yerlerde biraz daha yüksek başlar; asla tam ekran kaplamaz.
      initialChildSize: hasGuide ? 0.68 : 0.5,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: _PlaceDetailSheet(
          item: item,
          city: city,
          countryCode: countryCode,
          profile: profile,
          onEdit: onEdit,
          existingTicket: existingTicket,
          onAddTicket: onAddTicket,
          scrollController: scrollController,
        ),
      ),
    ),
  );
}

// Türkçe uzun tarih (viewer'daki formatla tutarlı) — bilet ziyaret tarihi için.
const List<String> _kTrMonths = [
  '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık', //
];

String _formatVisitDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day} ${_kTrMonths[d.month]} ${d.year}';
}

const Map<String, String> _kCategoryLabels = {
  'temple': 'Tapınak',
  'shrine': 'Tapınak',
  'view': 'Manzara',
  'city': 'Şehir',
  'museum': 'Müze',
  'park': 'Park',
  'shopping': 'Alışveriş',
  'fun': 'Eğlence',
  'nature': 'Doğa',
  'food': 'Yemek',
  'culture': 'Kültür',
  'landmark': 'Simge yapı',
};

/// Başlıktan emoji/işaret temizleyip karşılaştırma için normalize eder.
/// ticket_support.dart'taki paylaşılan normalizeTitle'a delege eder.
String _normalize(String s) => normalizeTitle(s);

/// Başlığı profildeki popüler yerle eşleştir (adım/kategori/puan için).
PlaceSuggestion? _matchPlace(String title, DestinationProfile? profile) {
  if (profile == null) return null;
  final t = _normalize(title);
  if (t.isEmpty) return null;
  for (final p in profile.popularPlaces) {
    final n = _normalize(p.name);
    if (n.isEmpty) continue;
    if (t == n || t.contains(n) || n.contains(t)) return p;
  }
  return null;
}

/// Öğe için tahmini yürüme adımı: eşleşen yerin typicalSteps'i,
/// yoksa tür + süreden kaba tahmin.
int _estimateItemSteps(TimelineItem item, PlaceSuggestion? match) {
  if (match?.typicalSteps != null) return match!.typicalSteps!;
  switch (item.kind) {
    case TimelineItemKind.meal:
      return 500;
    case TimelineItemKind.transport:
      return 400;
    case TimelineItemKind.hotel:
      return 200;
    default:
      final d = item.durationMin ?? 90;
      return 1500 + (d ~/ 30) * 500; // 90 dk ≈ 2.500 adım
  }
}

String _formatSteps(int steps) {
  if (steps < 1000) return '~$steps adım';
  final k = steps / 1000;
  final s = k == k.roundToDouble()
      ? k.toStringAsFixed(0)
      : k.toStringAsFixed(1).replaceAll('.', ',');
  return '~$s bin adım';
}

IconData _kindIcon(TimelineItemKind? k) => switch (k) {
      TimelineItemKind.meal => Icons.restaurant,
      TimelineItemKind.transport => Icons.directions_transit,
      TimelineItemKind.hotel => Icons.hotel,
      _ => Icons.place,
    };

class _PlaceDetailSheet extends StatefulWidget {
  const _PlaceDetailSheet({
    required this.item,
    required this.city,
    required this.countryCode,
    required this.profile,
    required this.onEdit,
    required this.existingTicket,
    required this.onAddTicket,
    required this.scrollController,
  });

  final TimelineItem item;
  final String city;
  final String? countryCode;
  final DestinationProfile? profile;
  final VoidCallback? onEdit;
  final Ticket? existingTicket;
  final void Function(Ticket)? onAddTicket;
  final ScrollController scrollController;

  @override
  State<_PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<_PlaceDetailSheet> {
  // Bu oturumda eklenen bilet (varsa widget.existingTicket'i geçersiz kılar).
  Ticket? _added;
  bool _pickingTicket = false;

  TimelineItem get item => widget.item;
  String get city => widget.city;
  String? get countryCode => widget.countryCode;
  DestinationProfile? get profile => widget.profile;
  VoidCallback? get onEdit => widget.onEdit;

  Ticket? get _ticket => _added ?? widget.existingTicket;

  Future<void> _openMap(BuildContext context) async {
    String url;
    if (item.mapUrl != null && item.mapUrl!.trim().isNotEmpty) {
      url = item.mapUrl!.trim();
    } else if (item.lat != null && item.lng != null) {
      url =
          'https://www.google.com/maps/search/?api=1&query=${item.lat},${item.lng}';
    } else {
      final q = '${_normalize(item.title)} $city'.trim();
      url = googleReviewsUrl(q.isEmpty ? item.title : q);
    }
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(url);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(const SnackBar(
        content: Text('Harita açılamadı — bağlantı panoya kopyalandı'),
      ));
    }
  }

  /// Yemek öğesinde yerel yemek önerileri; diğerlerinde koordinatlardan
  /// hesaplanan GERÇEK yakın yerler (isim · kategori · mesafe). Konum
  /// çözülemezse boş döner — uydurma öneri göstermeyiz.
  List<(String, String)> _recommendations() {
    final out = <(String, String)>[];
    final cc = countryCode;
    if (item.kind == TimelineItemKind.meal && cc != null) {
      for (final f in recommendedFoods(cc).take(3)) {
        out.add((f.emoji ?? '🍽️', f.label));
      }
      return out;
    }
    final near = nearbyCityPlaces(
      title: _normalize(item.title),
      lat: item.lat,
      lng: item.lng,
    );
    for (final n in near) {
      out.add((
        n.place.emoji,
        '${n.place.name} · ${n.place.category} · ${_formatDistance(n.distanceM)}',
      ));
    }
    return out;
  }

  // --- Bilet ekleme akışı ---------------------------------------------------

  /// "Bilet ekle" → Kamera / Galeri / Vazgeç seçenekli küçük bir sheet açar.
  Future<void> _startAddTicket() async {
    if (_pickingTicket) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Text('📷', style: TextStyle(fontSize: 22)),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Text('🖼️', style: TextStyle(fontSize: 22)),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Vazgeç'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickAndAddTicket(source);
  }

  Future<void> _pickAndAddTicket(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pickingTicket = true);
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (picked == null) {
        if (mounted) setState(() => _pickingTicket = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final b64 = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$b64';

      String text = '';
      if (!kIsWeb) {
        text = await extractTicketText(picked.path);
      }
      final info = parseTicketInfo(text);

      final normalized = _normalize(item.title);
      final ticket = Ticket(
        id: newTicketId(),
        kind: 'attraction',
        label: normalized.isEmpty ? item.title : item.title,
        purchased: true,
        visitDate: info['date'],
        imageDataUrl: dataUrl,
        scannedText: text.isEmpty ? null : text,
        emoji: '🎫',
      );
      widget.onAddTicket!(ticket);
      if (!mounted) return;
      setState(() {
        _added = ticket;
        _pickingTicket = false;
      });
      messenger.showSnackBar(const SnackBar(
        content: Text(kIsWeb
            ? '🎫 Bilet eklendi · Otomatik metin çıkarımı cihazda (iOS) çalışır'
            : '🎫 Bilet eklendi'),
      ));
    } catch (e) {
      if (mounted) setState(() => _pickingTicket = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Bilet eklenemedi — tekrar deneyin')),
      );
    }
  }

  /// Eklenmiş bilet kartı — foto + çıkarılan bilgiler.
  Widget _ticketCard(
    Ticket ticket, {
    required Color onSurface,
    required Color secondary,
    required Color subtleBg,
  }) {
    Widget? image;
    final dataUrl = ticket.imageDataUrl;
    if (dataUrl != null && dataUrl.contains(',')) {
      try {
        final b = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
        image = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            b,
            height: 180,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _ticketImagePlaceholder(subtleBg),
          ),
        );
      } catch (_) {
        image = _ticketImagePlaceholder(subtleBg);
      }
    }

    final scanned = ticket.scannedText?.trim();
    final preview = scanned == null || scanned.isEmpty
        ? null
        : (scanned.length > 140 ? '${scanned.substring(0, 140)}…' : scanned);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: subtleBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎫 Bilet',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: onSurface)),
          const SizedBox(height: 10),
          if (image != null) ...[
            image,
            const SizedBox(height: 10),
          ],
          const Row(
            children: [
              Text('✓ ', style: TextStyle(color: Color(0xFF16A34A))),
              Text('Bilet eklendi',
                  style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
          if (ticket.visitDate != null) ...[
            const SizedBox(height: 4),
            Text('Ziyaret: ${_formatVisitDate(ticket.visitDate!)}',
                style: TextStyle(fontSize: 13, color: secondary)),
          ],
          if (preview != null) ...[
            const SizedBox(height: 8),
            Text('📄 Okunan metin',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 2),
            Text(preview,
                style: TextStyle(
                    fontSize: 12, color: secondary, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _ticketImagePlaceholder(Color bg) => Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('🎫', style: TextStyle(fontSize: 40)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final secondary = onSurface.withValues(alpha: 0.65);
    final tertiary = onSurface.withValues(alpha: 0.45);
    final subtleBg = onSurface.withValues(alpha: 0.06);

    final match = _matchPlace(item.title, profile);
    final steps = _estimateItemSteps(item, match);
    final time = item.time ?? item.scheduledTime ?? '';
    final categoryKey = match?.category;
    final categoryLabel = categoryKey != null
        ? (_kCategoryLabels[categoryKey] ?? categoryKey)
        : null;
    final guide = matchPlaceGuide(item.title);

    final String intro;
    if (item.description != null && item.description!.trim().isNotEmpty) {
      intro = item.description!.trim();
    } else if (guide != null) {
      intro = guide.brief;
    } else {
      final parts = [
        if (categoryLabel != null) categoryLabel,
        if (city.isNotEmpty) city,
      ];
      intro = parts.isNotEmpty ? parts.join(' · ') : 'Planınızdaki bir durak.';
    }

    final recs = _recommendations();
    final userTip = item.tips?.trim();
    final rating = guide?.averageRating ??
        (match != null ? placeRating(match) : null);

    final ticket = _ticket;
    final needsTicket = requiresTicket(item, category: match?.category);

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: tertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Başlık
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: subtleBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_kindIcon(item.kind), size: 18, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: onSurface)),
                  if (time.isNotEmpty || rating != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        [
                          if (time.isNotEmpty) time,
                          if (rating != null)
                            '★ ${rating.toStringAsFixed(1).replaceAll('.', ',')}'
                                '${guide?.reviewCount != null ? ' (${_formatReviewCount(guide!.reviewCount!)} yorum)' : ''}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: secondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Fotoğraflar (rehber varsa) — kompakt, kaydırmalı
        if (guide != null && guide.imageUrls.isNotEmpty) ...[
          _PlaceCarousel(imageUrls: guide.imageUrls, subtleBg: subtleBg),
          const SizedBox(height: 12),
        ],

        // Tanıtım
        Text(intro,
            style: TextStyle(fontSize: 13.5, color: secondary, height: 1.45)),

        // Kullanıcının kendi notu (plandaki tips alanı)
        if (userTip != null && userTip.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(userTip,
                    style: TextStyle(
                        fontSize: 12.5, color: onSurface, height: 1.35)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),

        // Kompakt istatistik barı: Süre | Yürüme | Rezervasyon
        _StatBar(
          cells: [
            if (guide != null)
              ('⏱', 'Süre', _formatDuration(guide.visitDurationMin)),
            ('👣', 'Yürüme', _formatSteps(steps)),
            if (guide?.advanceBookingDays != null)
              ('🎟', 'Bilet', '${guide!.advanceBookingDays} gün önce'),
          ],
          subtleBg: subtleBg,
          onSurface: onSurface,
          secondary: secondary,
        ),

        // En iyi zaman — tek satır
        if (guide != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🌅', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(guide.bestTimeOfDay,
                    style: TextStyle(fontSize: 12.5, color: secondary)),
              ),
            ],
          ),
        ],

        // Ziyaretçi ipuçları
        if (guide != null && guide.tips.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('İpuçları',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: onSurface)),
          const SizedBox(height: 6),
          ...guide.tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('·',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: cs.primary)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(t,
                          style: TextStyle(
                              fontSize: 12.5, color: onSurface, height: 1.35)),
                    ),
                  ],
                ),
              )),
          if (guide.bookingHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('🎟 ${guide.bookingHint}',
                  style: TextStyle(fontSize: 12, color: secondary)),
            ),
        ],

        // Yakınındaki öneriler / restoran önerileri
        if (recs.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            item.kind == TimelineItemKind.meal ? 'Ne yenir' : 'Yakınlarda',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: onSurface),
          ),
          const SizedBox(height: 6),
          ...recs.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(r.$2,
                          style:
                              TextStyle(fontSize: 13, color: onSurface)),
                    ),
                  ],
                ),
              )),
        ],

        // Bilet — mevcut bilet kartı veya "Bilet ekle" butonu.
        if (ticket != null) ...[
          const SizedBox(height: 14),
          _ticketCard(ticket,
              onSurface: onSurface, secondary: secondary, subtleBg: subtleBg),
        ] else if (needsTicket && widget.onAddTicket != null) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _pickingTicket
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('🎫'),
              label: Text(_pickingTicket ? 'Ekleniyor…' : 'Bilet ekle'),
              onPressed: _pickingTicket ? null : _startAddTicket,
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Aksiyonlar
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Text('🗺️'),
                label: const Text('Haritada aç'),
                onPressed: () => _openMap(context),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Text('✏️'),
                  label: const Text('Düzenle'),
                  onPressed: onEdit,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Tek satırlık kompakt istatistik barı — hücreler dikey çizgiyle ayrılır.
class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.cells,
    required this.subtleBg,
    required this.onSurface,
    required this.secondary,
  });

  /// (emoji, etiket, değer)
  final List<(String, String, String)> cells;
  final Color subtleBg;
  final Color onSurface;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: subtleBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                    width: 1, thickness: 1, color: onSurface.withValues(alpha: 0.08)),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${cells[i].$1} ${cells[i].$2}',
                        style: TextStyle(fontSize: 11, color: secondary)),
                    const SizedBox(height: 2),
                    Text(cells[i].$3,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: onSurface)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kuş uçuşu mesafeyi okunur yapar: 50 m'ye yuvarlanmış metre ya da km.
String _formatDistance(double m) {
  if (m < 950) {
    final r = (m / 50).round() * 50;
    return '${r < 50 ? 50 : r} m';
  }
  final km = m / 1000;
  final s = km < 10
      ? km.toStringAsFixed(1).replaceAll('.', ',')
      : km.toStringAsFixed(0);
  return '$s km';
}

String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes dk';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '$h saat';
  return '$h sa $m dk';
}

String _formatReviewCount(int n) {
  if (n >= 1000) {
    final k = n / 1000;
    if (k >= 10) return '${k.toStringAsFixed(0)}bin';
    return '${k.toStringAsFixed(1).replaceAll('.0', '')}bin';
  }
  return '$n';
}

/// Yerin görsellerini kaydırılabilir bir carousel'de gösterir.
/// Görsel yüklenemezse subtle placeholder gösterilir.
class _PlaceCarousel extends StatefulWidget {
  const _PlaceCarousel({required this.imageUrls, required this.subtleBg});
  final List<String> imageUrls;
  final Color subtleBg;

  @override
  State<_PlaceCarousel> createState() => _PlaceCarouselState();
}

class _PlaceCarouselState extends State<_PlaceCarousel> {
  final _ctrl = PageController(viewportFraction: 0.92);
  int _idx = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  widget.imageUrls[i],
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: widget.subtleBg,
                      alignment: Alignment.center,
                      child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    color: widget.subtleBg,
                    alignment: Alignment.center,
                    child: const Text('🗺️',
                        style: TextStyle(fontSize: 36)),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.imageUrls.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.imageUrls.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _idx ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _idx
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withValues(
                            alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
