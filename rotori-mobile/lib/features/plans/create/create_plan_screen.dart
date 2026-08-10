// Yeni plan oluşturma — 2 soru, sonra dolu plan.
//
// Eski 6 adımlı wizard'ın (Başla→Rota→Başlık→Konaklama→Plan→Yayın) yerine
// geçer. Kullanıcı yalnızca "nereye" ve "ne zaman" söyler; kalkış, uçuş, otel,
// başlık, tempo hepsi akıllı varsayılandır ve plan üzerinde düzenlenir.
//
// Trip yalnızca plan ÜRETİLDİKTEN sonra kaydedilir — kullanıcı yarıda çıkarsa
// listede boş "hayalet plan" kalmaz.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n.dart';
import '../../../data/language_store.dart';
import '../../../data/plans_repository.dart';
import '../../../domain/city_places.dart';
import '../../../domain/plan_generation.dart';
import '../../../domain/dietary.dart';
import '../../../domain/route_sanity.dart';
import '../../../domain/types.dart';
import '../../viewer/viewer_theme.dart';
import '../plan_providers.dart';
import 'city_select_page.dart';
import 'preferences_page.dart';
import 'create_plan_widgets.dart';
import 'date_select_page.dart';

class CreatePlanScreen extends ConsumerStatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  ConsumerState<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends ConsumerState<CreatePlanScreen> {
  static const _pageAnim = Duration(milliseconds: 280);

  final _pc = PageController();

  /// Seçim SIRASI = rota sırası. Set değil List olması bilinçli.
  final List<String> _selected = [];

  String _start = '';
  String _end = '';
  bool _datesEstimated = false;
  bool _generating = false;
  int _page = 0;

  /// şehirKey → gün. Kullanıcı stepper'la değiştirdiyse dolu; boşsa önerilen
  /// (içerik ağırlıklı) dağılım kullanılır. Toplamı DAİMA gün sayısına eşittir.
  Map<String, int> _dayOverrides = const {};

  /// 3. adım — beslenme tercihleri. İSTEĞE BAĞLI; boş kalırsa Rotori uyum
  /// skoru bu bileşeni "eksik" gösterir, nötr puanla doldurmaz.
  final List<String> _dietTags = [];

  /// 3. adım — kişi başı öğün bütçesi (JPY). null = belirtilmedi.
  int? _mealBudgetJpy;

  void _toggleDietTag(String id) {
    final update = toggleDietaryTag(_dietTags, id);
    setState(() {
      _dietTags
        ..clear()
        ..addAll(update.selected);
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  // --- adım geçişleri -------------------------------------------------------

  void _goToPage(int page) {
    setState(() => _page = page);
    _pc.animateToPage(page, duration: _pageAnim, curve: Curves.easeOutCubic);
  }

  void _back() {
    if (_page > 0) {
      _goToPage(_page - 1);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/plans');
    }
  }

  // --- 1. ekran -------------------------------------------------------------

  void _toggleCity(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
      // Şehir listesi değişti → elle ayarlanan dağılım geçersiz.
      _dayOverrides = const {};
    });
  }

  /// Bir şehrin gününü ±1 değiştirir. TOPLAM GÜN SABİTTİR: fark, günü 1'den
  /// fazla olan komşu bir şehirden alınır (artırma) ya da ona verilir
  /// (azaltma). Böylece tarih aralığı ile dağılım her zaman tutarlı kalır.
  void _adjustDays(String cityKey, int delta) {
    final current = Map<String, int>.from(_effectiveSplit());
    if (current.isEmpty || !current.containsKey(cityKey)) return;

    // Farkın alınacağı/verileceği şehir: cityKey dışındaki en çok günlü.
    String? donor;
    var best = -1;
    for (final e in current.entries) {
      if (e.key == cityKey) continue;
      final eligible = delta > 0 ? e.value > 1 : true;
      if (eligible && e.value > best) {
        best = e.value;
        donor = e.key;
      }
    }
    if (donor == null) return;
    if (delta > 0 && current[donor]! <= 1) return;
    if (delta < 0 && current[cityKey]! <= 1) return;

    current[cityKey] = current[cityKey]! + delta;
    current[donor] = current[donor]! - delta;
    setState(() => _dayOverrides = current);
  }

  /// Önerilen rota sırasını uygular. Gün dağılımı şehir sırasına bağlı
  /// olduğu için elle ayarlanan dağılım sıfırlanır — aksi halde "Tokyo 5 gün"
  /// yanlış şehre yapışırdı.
  void _applyRouteOrder(List<String> order) {
    final s = LanguageScope.of(context);
    setState(() {
      _selected
        ..clear()
        ..addAll(order);
      _dayOverrides = const {};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.s('create.route.fixed'))),
    );
  }

  /// Yürürlükteki dağılım: kullanıcı ayarladıysa o, yoksa önerilen.
  Map<String, int> _effectiveSplit() {
    if (_dayOverrides.isNotEmpty) return _dayOverrides;
    if (_start.isEmpty || _end.isEmpty) return const {};
    return suggestedDaySplit(_selected, _start, _end);
  }

  /// Hero alt satırı: "🗼 Tokyo → ⛩️ Kyoto"
  String _routeSummary() {
    final parts = <String>[];
    for (final key in _selected) {
      final match = kCityData.where((c) => c.key == key);
      if (match.isEmpty) continue;
      parts.add('${match.first.emoji} ${match.first.label}');
    }
    return parts.join('  →  ');
  }

  // --- 2. ekran -------------------------------------------------------------

  Future<void> _pickRange() async {
    final s = LanguageScope.of(context);
    final palette = ref.read(viewerPaletteProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existingStart = DateTime.tryParse(_start);
    final existingEnd = DateTime.tryParse(_end);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(now.year + 2, 12, 31),
      currentDate: today,
      initialDateRange: existingStart != null && existingEnd != null
          ? DateTimeRange(start: existingStart, end: existingEnd)
          : null,
      helpText: s.s('create.rangeHelp'),
      confirmText: s.s('create.rangeConfirm'),
      cancelText: s.s('create.rangeCancel'),
      saveText: s.s('create.rangeConfirm'),
      builder: (ctx, child) =>
          Theme(data: palette.toThemeData(), child: child ?? const SizedBox()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = _ymd(picked.start);
      _end = _ymd(picked.end);
      // Kullanıcı elle seçti — artık "tahmini" değil.
      _datesEstimated = false;
      // Toplam gün değişti → elle ayarlanan dağılım geçersiz.
      _dayOverrides = const {};
    });
  }

  /// "Tarih henüz belli değil" — sezona göre akıllı varsayılan.
  void _useSuggestedDates() {
    final r = suggestDateRange(cityCount: _selected.length);
    setState(() {
      _start = r.start;
      _end = r.end;
      _datesEstimated = true;
      _dayOverrides = const {};
    });
  }

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // --- üretim ---------------------------------------------------------------

  bool get _canGenerate =>
      !_generating &&
      _selected.isNotEmpty &&
      _start.isNotEmpty &&
      _end.isNotEmpty &&
      _selected.length <= inclusiveDays(_start, _end);

  Future<void> _generate() async {
    if (!_canGenerate) return;
    final repo = ref.read(plansRepositoryProvider);
    final lang = ref.read(appLangProvider);
    final s = LanguageScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _generating = true);

    // Üretim senkron ve hızlı (~10-50 ms) — YAPAY GECİKME YOK.
    final trip = buildTripFromCities(
      cityKeys: _selected,
      startYmd: _start,
      endYmd: _end,
      lang: lang,
      datesEstimated: _datesEstimated,
      dayOverrides: _dayOverrides.isEmpty ? null : _dayOverrides,
    );

    // 3. adımda toplanan tercihler. buildTripFromCities bunları parametre
    // olarak almıyor; üretimden sonra yazmak hem imzayı büyütmemeyi hem de
    // "boş bırakılırsa hiç yazma" davranışını korumayı sağlıyor.
    if (_dietTags.isNotEmpty) {
      trip.preferences.dietaryTags = List<String>.from(_dietTags);
    }
    if (_mealBudgetJpy != null) {
      trip.preferences.mealBudgetJpyPerPerson = _mealBudgetJpy;
    }
    trip.preferences.planAssumptions = PlanAssumptions(
      dateSource: _datesEstimated ? 'seasonalSuggestion' : 'userSelected',
      dateRationale: _datesEstimated ? 'seasonalWeatherAndCrowdBalance' : null,
      flightStatus: 'draft',
      hotelStatus: 'draft',
    );

    // Repo yokken (önizleme/oturumsuz) viewer planı buradan okur.
    ref.read(draftTripProvider.notifier).state = trip;

    if (repo == null) {
      if (!mounted) return;
      setState(() => _generating = false);
      context.pushReplacement('/plans/${trip.id}/view');
      return;
    }

    try {
      // Önce yerel cache: viewer anında açılabilsin. Sunucu push'u arkada.
      await repo.saveLocal(trip);
      unawaited(repo.save(trip).catchError((_) => null));
      ref.invalidate(plansPullProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _generating = false);
      messenger.showSnackBar(
        SnackBar(content: Text(s.s('create.saveFailed'))),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _generating = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.s('create.ready')),
        duration: const Duration(seconds: 2),
      ),
    );
    context.pushReplacement('/plans/${trip.id}/view');
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(viewerPaletteProvider);
    final s = LanguageScope.of(context);
    final onFirstPage = _page == 0;

    return PopScope(
      canPop: onFirstPage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToPage(0);
      },
      child: Theme(
        data: palette.toThemeData(),
        child: Scaffold(
          backgroundColor: palette.bg,
          body: Column(
            children: [
              BrandHero(
                palette: palette,
                step: _page,
                totalSteps: 3,
                onBack: _back,
                title: switch (_page) {
                  0 => s.s('create.cities.title'),
                  1 => s.s('create.dates.title'),
                  _ => s.s('create.prefs.title'),
                },
                subtitle: switch (_page) {
                  0 => s.s('create.cities.sub'),
                  1 => (_selected.isEmpty
                      ? s.s('create.dates.sub')
                      : _routeSummary()),
                  _ => s.s('create.prefs.sub'),
                },
              ),
              Expanded(
                child: PageView(
                  controller: _pc,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    CitySelectPage(
                      palette: palette,
                      selectedKeys: _selected,
                      onToggle: _toggleCity,
                      onContinue: _selected.isEmpty ? null : () => _goToPage(1),
                    ),
                    DateSelectPage(
                      palette: palette,
                      startYmd: _start,
                      endYmd: _end,
                      cityCount: _selected.length,
                      datesEstimated: _datesEstimated,
                      distribution: _start.isEmpty || _end.isEmpty
                          ? const []
                          : previewCityDistribution(
                              _selected,
                              _start,
                              _end,
                              dayOverrides:
                                  _dayOverrides.isEmpty ? null : _dayOverrides,
                            ),
                      generating: _generating,
                      onPickRange: _pickRange,
                      onUnknownDates: _useSuggestedDates,
                      onEditCities: () => _goToPage(0),
                      // Artık son adım değil — tercihler adımına geçirir.
                      onGenerate: _canGenerate ? () => _goToPage(2) : null,
                      onAdjustDays: _adjustDays,
                      routeSanity: checkRouteOrder(_selected),
                      selectedKeys: List<String>.from(_selected),
                      onFixRoute: _applyRouteOrder,
                    ),
                    PreferencesPage(
                      palette: palette,
                      dietTags: _dietTags,
                      mealBudgetJpy: _mealBudgetJpy,
                      routeSummary: _routeSummary(),
                      dateSummary: '$_start → $_end',
                      datesEstimated: _datesEstimated,
                      onEditCities: () => _goToPage(0),
                      onEditDates: () => _goToPage(1),
                      onToggleTag: _toggleDietTag,
                      onPickBudget: (jpy) =>
                          setState(() => _mealBudgetJpy = jpy),
                      generating: _generating,
                      onGenerate: _canGenerate ? _generate : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
