// Rotori Eats — restoran detay sheet'i.
//
// Free/premium sınırı burada bilinçli olarak ETİK bir yerden geçirildi:
//   - Güvenlik/diyet bilgisi (helal seviyesi ve açıklaması, alerjen sorma
//     frazları, nakit uyarısı) HER ZAMAN ücretsizdir. Birinin yiyemeyeceği bir
//     şeyi yemesini engelleyen bilgi paywall'ın arkasına konmaz.
//   - Ücretli olan kısım KARAR HIZLANDIRAN zekadır: Rotori uyum skoru, mesafe
//     ve "ne zaman git / ne söyle" içgörüsü.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n.dart';
import '../../../data/google_maps_launcher.dart';
import '../../../domain/eats.dart';
import '../../../domain/eats_query.dart';
import '../../../domain/japanese_phrases_data.dart' show JpPhrase;
import '../../../domain/localized_text.dart';
import '../viewer_theme.dart';

Future<void> showEatsDetailSheet({
  required BuildContext context,
  required ViewerPalette palette,
  required AppLang lang,
  required EatsResult result,
  required EatsContext eatsContext,
  required bool premium,
  required Future<void> Function() onUpsell,
  Future<void> Function()? onEditPreferences,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewerPaletteScope(
      palette: palette,
      child: _EatsDetailSheet(
        palette: palette,
        lang: lang,
        result: result,
        eatsContext: eatsContext,
        premium: premium,
        onUpsell: onUpsell,
        onEditPreferences: onEditPreferences,
      ),
    ),
  );
}

class _EatsDetailSheet extends StatelessWidget {
  const _EatsDetailSheet({
    required this.palette,
    required this.lang,
    required this.result,
    required this.eatsContext,
    required this.premium,
    required this.onUpsell,
    this.onEditPreferences,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final EatsResult result;
  final EatsContext eatsContext;
  final bool premium;
  final Future<void> Function() onUpsell;

  /// Eksik skor girdilerini doldurma sheet'ini açar. Null ise "eksik" listesi
  /// yine gösterilir ama doldurma butonu çıkmaz.
  final Future<void> Function()? onEditPreferences;

  ViewerPalette get p => palette;
  EatsPlace get place => result.place;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: p.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  _header(),
                  const SizedBox(height: 14),
                  _trustCard(context),
                  const SizedBox(height: 12),
                  _factsRow(),
                  const SizedBox(height: 14),
                  _signature(),
                  const SizedBox(height: 12),
                  Text(
                    place.description.of(lang),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _amenities(),
                  const SizedBox(height: 16),
                  _scoreBlock(context),
                  const SizedBox(height: 16),
                  _tipBlock(context),
                  const SizedBox(height: 16),
                  _phraseCard(context),
                  const SizedBox(height: 14),
                  _verifiedNote(),
                ],
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(place.categoryEmoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.name,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${place.nameJa} · ${place.city} · ${place.area}',
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, size: 17, color: p.gold),
                const SizedBox(width: 2),
                Text(
                  place.rating.toStringAsFixed(1),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Text(
              const LText('Google ölçeği', 'Google scale').of(lang),
              style: TextStyle(color: p.textMuted, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  /// Helal/vejetaryen seviyesi + NE DEMEK olduğu. Rakiplerde tek bir "helal"
  /// rozeti var; belirsizlik tam olarak burada saklanıyor.
  Widget _trustCard(BuildContext context) {
    final rows = <Widget>[];
    if (place.halal != HalalTrust.none) {
      rows.add(_trustRow(
        emoji: place.halal.emoji,
        title: place.halal.label.of(lang),
        body: place.halal.explainer.of(lang),
      ));
    }
    if (place.veggie != VeggieLevel.none) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(_trustRow(
        emoji: place.veggie.emoji,
        title: place.veggie.label.of(lang),
        body: place.veggie == VeggieLevel.veganMenu
            ? const LText(
                'Mutfakta hayvansal ürün yok — dashi riski taşımaz.',
                'No animal products in the kitchen — no dashi risk.',
              ).of(lang)
            : const LText(
                'Vejetaryen seçenek var; çorbada balık suyu (dashi) olabilir, sor.',
                'Vegetarian options exist; broth may contain fish stock (dashi) — ask.',
              ).of(lang),
      ));
    }
    if (rows.isEmpty) {
      rows.add(_trustRow(
        emoji: 'ℹ️',
        title: const LText('Diyet bilgisi yok', 'No dietary info').of(lang),
        body: const LText(
          'Bu mekan için helal/vejetaryen uyumu belirtilmemiş.',
          'No halal or vegetarian compliance is stated for this place.',
        ).of(lang),
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _trustRow({
    required String emoji,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _factsRow() {
    final budget = eatsContext.mealBudgetJpy;
    final fitsBudget = budget != null && budget > 0
        ? place.priceMaxJpy <= budget
        : null;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _fact(
          icon: Icons.payments_outlined,
          text: '${place.priceBand} · ${place.priceTier.symbol}',
          tone: fitsBudget == null
              ? null
              : (fitsBudget ? p.matcha : p.sunset),
        ),
        if (result.distanceKm != null && premium)
          _fact(
            icon: Icons.directions_walk_rounded,
            text: '${result.distanceKm!.toStringAsFixed(1)} km · '
                '${result.walkMinutes} ${lang == AppLang.tr ? "dk" : "min"}',
          ),
        _fact(
          icon: Icons.schedule_rounded,
          text: place.slots.map((s) => s.emoji).join(' '),
        ),
        if (fitsBudget == false)
          _fact(
            icon: Icons.trending_up_rounded,
            text: const LText('Bütçe üstü', 'Above budget').of(lang),
            tone: p.sunset,
          ),
      ],
    );
  }

  Widget _fact({required IconData icon, required String text, Color? tone}) {
    final c = tone ?? p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.elevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _signature() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.matcha.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👉', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: const LText('Bunu söyle: ', 'Order this: ').of(lang),
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: place.signature.of(lang),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amenities() {
    final sorted = place.amenities.toList()
      ..sort((a, b) => (a.isCaution ? 1 : 0).compareTo(b.isCaution ? 1 : 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          const LText('Pratik bilgiler', 'Practical info').of(lang),
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final a in sorted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: a.isCaution
                      ? p.sunset.withValues(alpha: 0.14)
                      : p.elevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: a.isCaution
                        ? p.sunset.withValues(alpha: 0.45)
                        : p.border,
                  ),
                ),
                child: Text(
                  '${a.emoji} ${a.label.of(lang)}',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Rotori uyum skoru kırılımı — premium.
  Widget _scoreBlock(BuildContext context) {
    final s = scoreEatsPlace(
      place,
      context: eatsContext,
      distanceKm: result.distanceKm,
    );
    return _premiumBlock(
      context: context,
      title: const LText('Rotori uyum skoru', 'Rotori match score'),
      lockedPitch: const LText(
        'Diyetin, bütçen ve konumun bu mekana ne kadar uyuyor — tek sayıda.',
        'How well your diet, budget and location fit this place — in one number.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Diyet ve bütçenin ikisi de bilinmiyorsa ortada kişiselleştirilmiş
          // bir şey yok — büyük bir sayı basmak yanıltıcı olur.
          if (s.isPersonalized)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s.score}',
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                Text(
                  ' / 100',
                  style: TextStyle(color: p.textMuted, fontSize: 13),
                ),
                const SizedBox(width: 8),
                if (s.knownCount < s.totalCount)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      lang == AppLang.tr
                          ? '${s.knownCount}/${s.totalCount} sinyal'
                          : '${s.knownCount}/${s.totalCount} signals',
                      style: TextStyle(color: p.textMuted, fontSize: 11),
                    ),
                  ),
              ],
            )
          else
            Text(
              const LText(
                'Henüz kişiselleştirilemiyor',
                'Not personalised yet',
              ).of(lang),
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 10),
          for (final part in s.parts) _scoreBar(part),
          if (s.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in s.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '· ${r.of(lang)}',
                  style: TextStyle(color: p.textSecondary, fontSize: 12),
                ),
              ),
          ],
          if (s.missingSignals.isNotEmpty) ...[
            const SizedBox(height: 12),
            _missingBlock(context, s),
          ],
        ],
      ),
    );
  }

  /// Eksik sinyalleri ve nasıl doldurulacağını gösterir. Skorun neden
  /// zayıf olduğunu saklamak yerine kullanıcıya kontrolü verir.
  Widget _missingBlock(BuildContext context, EatsScore s) {
    final fillable = s.missingSignals
        .where((sig) => sig == EatsSignal.diet || sig == EatsSignal.budget)
        .toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            const LText(
              'Skoru keskinleştirmek için eksik olanlar',
              'Missing inputs that would sharpen this score',
            ).of(lang),
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final sig in s.missingSignals)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '· ${sig.label.of(lang)} — ${sig.missingHint.of(lang)}',
                style: TextStyle(color: p.textSecondary, fontSize: 11.5),
              ),
            ),
          if (fillable.isNotEmpty && onEditPreferences != null) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onEditPreferences!();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: Text(
                  const LText('Tercihlerimi gir', 'Set my preferences').of(lang),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scoreBar(EatsScorePart part) {
    final known = part.known;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              part.signal.label.of(lang),
              style: TextStyle(
                color: known ? p.textSecondary : p.textMuted,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: known ? (part.value / part.max).clamp(0.0, 1.0) : 0,
                minHeight: 6,
                backgroundColor: p.border,
                valueColor: AlwaysStoppedAnimation(p.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(
              known
                  ? '${part.value}'
                  : const LText('eksik', 'missing').of(lang),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: known ? p.textPrimary : p.textMuted,
                fontSize: 11.5,
                fontWeight: known ? FontWeight.w700 : FontWeight.w500,
                fontStyle: known ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipBlock(BuildContext context) {
    final tip = place.insiderTip;
    if (tip == null) return const SizedBox.shrink();
    return _premiumBlock(
      context: context,
      title: const LText('Bilenin ipucu', 'Insider tip'),
      lockedPitch: const LText(
        'Ne zaman gitmeli, kuyruğu nasıl atlarsın, ne söylemelisin.',
        'When to go, how to skip the queue, what to say.',
      ),
      child: Text(
        tip.of(lang),
        style: TextStyle(color: p.textPrimary, fontSize: 13, height: 1.4),
      ),
    );
  }

  /// Premium blok sarmalayıcı — kilitliyken değeri anlatır, açıkken içeriği verir.
  Widget _premiumBlock({
    required BuildContext context,
    required LText title,
    required LText lockedPitch,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: premium ? p.border : p.accent.withValues(alpha: 0.45),
        ),
        color: premium ? p.elevated : p.accent.withValues(alpha: 0.07),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.of(lang),
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!premium)
                Icon(Icons.lock_rounded, size: 14, color: p.accent),
            ],
          ),
          const SizedBox(height: 9),
          if (premium)
            child
          else ...[
            Text(
              lockedPitch.of(lang),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onUpsell();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.accent,
                  side: BorderSide(color: p.accent.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  const LText('Eats Pass ile aç', 'Unlock with Eats Pass').of(lang),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sipariş frazları — DAİMA ücretsiz. Birinin yiyemeyeceği bir şeyi
  /// yemesini engelleyen bilgi paywall'ın arkasına konmaz.
  Widget _phraseCard(BuildContext context) {
    final phrases = _phrasesFor(place);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                const LText('Kapıda göster / sor', 'Show or ask at the door')
                    .of(lang),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.matcha.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                const LText('Ücretsiz', 'Free').of(lang),
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _copyRow(
          context,
          jp: place.nameJa,
          romaji: place.name,
          meaning: const LText('Mekanın Japonca adı', 'The place in Japanese'),
        ),
        for (final ph in phrases)
          _copyRow(
            context,
            jp: ph.jp,
            romaji: ph.romaji,
            meaning: ph.meaning,
          ),
      ],
    );
  }

  Widget _copyRow(
    BuildContext context, {
    required String jp,
    String? romaji,
    required LText meaning,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.elevated,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () {
            Clipboard.setData(ClipboardData(text: jp));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  const LText('Kopyalandı', 'Copied').of(lang),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jp,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (romaji != null)
                        Text(
                          romaji,
                          style: TextStyle(color: p.textMuted, fontSize: 11),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        meaning.of(lang),
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.copy_rounded, size: 15, color: p.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _verifiedNote() {
    return Text(
      lang == AppLang.tr
          ? 'Bu bilgi küratörlü ve kamuya açık kaynaklardan derlenmiştir '
              '(derleme: ${place.verifiedOn}); mekandan doğrudan teyit '
              'ALINMAMIŞTIR. Helal sertifikası, menü ve çalışma saatleri '
              'değişebilir — sipariş öncesi mekanda sor.'
          : 'This entry is curated from public sources '
              '(compiled ${place.verifiedOn}); it has NOT been confirmed with '
              'the venue directly. Halal certification, menu and hours can '
              'change — ask before you order.',
      style: TextStyle(color: p.textMuted, fontSize: 11, height: 1.35),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.textSecondary,
                side: BorderSide(color: p.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              label: Text(
                const LText('Kapat', 'Close').of(lang),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => openGoogleMapsPoint(
                lat: place.lat,
                lng: place.lng,
                label: place.name,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: const Icon(Icons.navigation_rounded, size: 16),
              label: Text(
                const LText('Yol tarifi', 'Directions').of(lang),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mekanın diyet profiline göre en işe yarar frazları seçer.
List<JpPhrase> _phrasesFor(EatsPlace place) {
  final out = <JpPhrase>[];
  if (place.halal != HalalTrust.none) {
    out.add(const JpPhrase(
      jp: 'これに豚肉は入っていますか？',
      romaji: 'Kore ni butaniku wa haitte imasu ka?',
      meaning: LText('Bunun içinde domuz eti var mı?', 'Does this contain pork?'),
    ));
    out.add(const JpPhrase(
      jp: 'お酒やみりんは使っていますか？',
      romaji: 'Osake ya mirin wa tsukatte imasu ka?',
      meaning: LText(
        'Alkol veya mirin kullanıyor musunuz?',
        'Do you use alcohol or mirin?',
      ),
    ));
  }
  if (place.veggie != VeggieLevel.none) {
    out.add(const JpPhrase(
      jp: 'だしは使っていますか？',
      romaji: 'Dashi wa tsukatte imasu ka?',
      meaning: LText(
        'Balık suyu (dashi) kullanıyor musunuz?',
        'Do you use fish stock (dashi)?',
      ),
    ));
  }
  if (place.amenities.contains(EatsAmenity.cashOnly)) {
    out.add(const JpPhrase(
      jp: 'カードで払えますか？',
      romaji: 'Kaado de haraemasu ka?',
      meaning: LText('Kartla ödeyebilir miyim?', 'Can I pay by card?'),
    ));
  }
  if (out.isEmpty) {
    out.add(const JpPhrase(
      jp: 'おすすめは何ですか？',
      romaji: 'Osusume wa nan desu ka?',
      meaning: LText('Ne tavsiye edersiniz?', 'What do you recommend?'),
    ));
  }
  return out;
}
