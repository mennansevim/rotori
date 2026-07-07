// Yer detay popup — hem planner (Plan adımı) hem viewer (gün planları)
// tarafından kullanılır. Temaya uyumlu (açık/koyu) Material bileşenleri.
//
// İçerik: kısa tanıtım, tahmini yürüme adımı, öneriler (yakındaki yerler /
// yemekler), "haritada aç" butonu ve opsiyonel "düzenle".
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PlaceDetailSheet(
      item: item,
      city: city,
      countryCode: countryCode,
      profile: profile,
      onEdit: onEdit,
      existingTicket: existingTicket,
      onAddTicket: onAddTicket,
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
  });

  final TimelineItem item;
  final String city;
  final String? countryCode;
  final DestinationProfile? profile;
  final VoidCallback? onEdit;
  final Ticket? existingTicket;
  final void Function(Ticket)? onAddTicket;

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

  List<(String, String)> _recommendations(PlaceSuggestion? match) {
    final out = <(String, String)>[];
    if (item.tips != null && item.tips!.trim().isNotEmpty) {
      out.add(('💡', item.tips!.trim()));
    }
    final cc = countryCode;
    if (item.kind == TimelineItemKind.meal && cc != null) {
      for (final f in recommendedFoods(cc).take(3)) {
        out.add((f.emoji ?? '🍽️', f.label));
      }
    } else if (profile != null) {
      final near = profile!.popularPlaces.where((p) => p.id != match?.id).take(3);
      for (final p in near) {
        out.add((p.emoji, '${p.name} · ${ratingStars(placeRating(p))}'));
      }
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

    final recs = _recommendations(match);
    final rating = guide?.averageRating ??
        (match != null ? placeRating(match) : null);

    final ticket = _ticket;
    final needsTicket = requiresTicket(item, category: match?.category);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: tertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Fotoğraf karuseli (rehber varsa)
            if (guide != null && guide.imageUrls.isNotEmpty) ...[
              _PlaceCarousel(imageUrls: guide.imageUrls, subtleBg: subtleBg),
              const SizedBox(height: 16),
            ],

            // Başlık
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: subtleBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_kindIcon(item.kind), size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: onSurface)),
                      if (time.isNotEmpty || rating != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if (time.isNotEmpty) '🕒 $time',
                              if (rating != null)
                                '${ratingStars(rating)} ${rating.toStringAsFixed(1).replaceAll('.', ',')}',
                            ].join('   '),
                            style: TextStyle(fontSize: 13, color: secondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tanıtım
            Text(intro,
                style: TextStyle(fontSize: 14, color: secondary, height: 1.5)),
            const SizedBox(height: 16),

            // Meta chip'leri (süre / en iyi zaman / ön rezervasyon)
            if (guide != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: 'Süre',
                    value: _formatDuration(guide.visitDurationMin),
                    subtleBg: subtleBg,
                    onSurface: onSurface,
                    secondary: secondary,
                  ),
                  _MetaChip(
                    icon: Icons.wb_twilight_outlined,
                    label: 'En iyi zaman',
                    value: guide.bestTimeOfDay,
                    subtleBg: subtleBg,
                    onSurface: onSurface,
                    secondary: secondary,
                  ),
                  if (guide.advanceBookingDays != null)
                    _MetaChip(
                      icon: Icons.event_available_outlined,
                      label: 'Ön rezervasyon',
                      value: '${guide.advanceBookingDays} gün önceden',
                      subtleBg: subtleBg,
                      onSurface: onSurface,
                      secondary: secondary,
                    ),
                  if (guide.reviewCount != null)
                    _MetaChip(
                      icon: Icons.reviews_outlined,
                      label: 'Yorum',
                      value: '~${_formatReviewCount(guide.reviewCount!)}',
                      subtleBg: subtleBg,
                      onSurface: onSurface,
                      secondary: secondary,
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Tahmini yürüme adımı
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: subtleBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Text('👣', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Text('Tahmini yürüme',
                      style: TextStyle(fontSize: 13, color: secondary)),
                  const Spacer(),
                  Text(_formatSteps(steps),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: onSurface)),
                ],
              ),
            ),

            // Ziyaretçi ipuçları
            if (guide != null && guide.tips.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Ziyaretçi ipuçları',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: onSurface)),
              const SizedBox(height: 8),
              ...guide.tips.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 15, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: onSurface,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  )),
            ],

            // Rezervasyon ipucu
            if (guide?.bookingHint != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.confirmation_num_outlined,
                        size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Bileti nereden: ${guide!.bookingHint}',
                          style: TextStyle(
                              fontSize: 12, color: onSurface, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],

            // Yakınındaki öneriler / restoran önerileri
            if (recs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                item.kind == TimelineItemKind.meal
                    ? 'Ne yenir'
                    : 'Yakınlarda',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: onSurface),
              ),
              const SizedBox(height: 8),
              ...recs.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.$1, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(r.$2,
                              style: TextStyle(fontSize: 14, color: onSurface)),
                        ),
                      ],
                    ),
                  )),
            ],

            // Bilet — mevcut bilet kartı veya "Bilet ekle" butonu.
            if (ticket != null) ...[
              const SizedBox(height: 16),
              _ticketCard(ticket,
                  onSurface: onSurface,
                  secondary: secondary,
                  subtleBg: subtleBg),
            ] else if (needsTicket && widget.onAddTicket != null) ...[
              const SizedBox(height: 16),
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

            const SizedBox(height: 20),

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
        ),
      ),
    );
  }
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtleBg,
    required this.onSurface,
    required this.secondary,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color subtleBg;
  final Color onSurface;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: subtleBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 10, color: secondary)),
                  Text(value,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onSurface)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          height: 180,
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
