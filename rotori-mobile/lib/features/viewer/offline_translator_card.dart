import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../data/offline_translation.dart';
import '../../domain/localized_text.dart';
import 'viewer_theme.dart';

/// Japonca sayfasındaki premium, cihaz-üstü, iki yönlü metin çeviri kartı.
class OfflineTranslatorCard extends StatefulWidget {
  const OfflineTranslatorCard({
    super.key,
    required this.palette,
    required this.lang,
    required this.isPremium,
    this.gateway,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool isPremium;

  /// Testlerde gerçek platform kanalını kullanmamak için enjekte edilebilir.
  final OfflineTranslationGateway? gateway;

  @override
  State<OfflineTranslatorCard> createState() => _OfflineTranslatorCardState();
}

class _OfflineTranslatorCardState extends State<OfflineTranslatorCard> {
  final _sourceController = TextEditingController();
  late final OfflineTranslationGateway _gateway;
  late final bool _ownsGateway;

  bool _japaneseToLocal = false;
  bool? _modelsReady;
  bool _busy = false;
  String _result = '';
  String? _error;

  OfflineTranslationLanguage get _localLanguage => widget.lang == AppLang.tr
      ? OfflineTranslationLanguage.turkish
      : OfflineTranslationLanguage.english;

  OfflineTranslationLanguage get _sourceLanguage =>
      _japaneseToLocal ? OfflineTranslationLanguage.japanese : _localLanguage;

  OfflineTranslationLanguage get _targetLanguage =>
      _japaneseToLocal ? _localLanguage : OfflineTranslationLanguage.japanese;

  @override
  void initState() {
    super.initState();
    _ownsGateway = widget.gateway == null;
    _gateway = widget.gateway ?? createOfflineTranslationGateway();
    if (widget.isPremium && _gateway.isSupported) _checkModels();
  }

  @override
  void didUpdateWidget(covariant OfflineTranslatorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.isPremium && widget.isPremium) ||
        (oldWidget.lang != widget.lang && widget.isPremium)) {
      setState(() {
        _result = '';
        _error = null;
        _modelsReady = null;
      });
      if (_gateway.isSupported) _checkModels();
    } else if (oldWidget.isPremium && !widget.isPremium) {
      setState(() {
        _result = '';
        _error = null;
        _modelsReady = null;
        _sourceController.clear();
      });
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    if (_ownsGateway) _gateway.close();
    super.dispose();
  }

  Future<void> _checkModels() async {
    try {
      final ready = await _gateway.areModelsReady(
        source: _sourceLanguage,
        target: _targetLanguage,
      );
      if (mounted) setState(() => _modelsReady = ready);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _modelsReady = false;
        _error = const LText(
          'Dil paketleri kontrol edilemedi.',
          'Language packs could not be checked.',
        ).of(widget.lang);
      });
    }
  }

  Future<void> _downloadModels() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _gateway.downloadModels(
        source: _sourceLanguage,
        target: _targetLanguage,
      );
      if (mounted) setState(() => _modelsReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const LText(
          'Dil paketleri indirilemedi. Wi-Fi bağlantını kontrol edip tekrar dene.',
          'Language packs could not be downloaded. Check Wi-Fi and try again.',
        ).of(widget.lang);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _translate() async {
    final text = _sourceController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = const LText(
          'Çevirmek istediğin metni yaz.',
          'Enter the text you want to translate.',
        ).of(widget.lang);
      });
      return;
    }
    if (!widget.isPremium || _modelsReady != true) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = '';
    });
    try {
      final translated = await _gateway.translate(
        text: text,
        source: _sourceLanguage,
        target: _targetLanguage,
      );
      if (mounted) setState(() => _result = translated.trim());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const LText(
          'Çeviri tamamlanamadı. Tekrar deneyebilirsin.',
          'Translation could not be completed. Please try again.',
        ).of(widget.lang);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _swapLanguages() {
    setState(() {
      _japaneseToLocal = !_japaneseToLocal;
      final previousResult = _result;
      _result = '';
      _error = null;
      if (previousResult.isNotEmpty) {
        _sourceController.text = previousResult;
      } else {
        _sourceController.clear();
      }
    });
  }

  Future<void> _copyResult() async {
    await Clipboard.setData(ClipboardData(text: _result));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          const LText('Çeviri kopyalandı.', 'Translation copied.')
              .of(widget.lang),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  String _languageLabel(OfflineTranslationLanguage language) =>
      switch (language) {
        OfflineTranslationLanguage.turkish => 'Türkçe',
        OfflineTranslationLanguage.english => 'English',
        OfflineTranslationLanguage.japanese => '日本語',
      };

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Container(
      key: const Key('offline-translator-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TranslatorHeader(
            palette: p,
            lang: widget.lang,
            isPremium: widget.isPremium,
          ),
          const SizedBox(height: 14),
          if (!widget.isPremium)
            _PremiumTranslatorLock(palette: p, lang: widget.lang)
          else
            ..._premiumContent(p),
        ],
      ),
    );
  }

  List<Widget> _premiumContent(ViewerPalette p) {
    final supported = _gateway.isSupported;
    final sourceLabel = _languageLabel(_sourceLanguage);
    final targetLabel = _languageLabel(_targetLanguage);
    return [
      _DirectionSelector(
        palette: p,
        source: sourceLabel,
        target: targetLabel,
        onSwap: supported && !_busy ? _swapLanguages : null,
      ),
      const SizedBox(height: 12),
      if (!supported)
        _InfoBanner(
          palette: p,
          icon: Icons.phone_iphone_rounded,
          text: const LText(
            'Çevrimdışı çeviri iPhone ve Android uygulamasında çalışır. Bu web ön izlemesinde arayüzü görebilirsin.',
            'Offline translation works in the iPhone and Android app. This web preview shows the interface.',
          ).of(widget.lang),
        )
      else if (_modelsReady == null)
        _InfoBanner(
          palette: p,
          icon: Icons.hourglass_top_rounded,
          text: const LText(
            'Dil paketleri kontrol ediliyor…',
            'Checking language packs…',
          ).of(widget.lang),
        )
      else if (_modelsReady == false)
        _DownloadBanner(
          palette: p,
          lang: widget.lang,
          busy: _busy,
          onDownload: _busy ? null : _downloadModels,
        ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('offline-translator-input'),
        controller: _sourceController,
        enabled: supported && !_busy,
        minLines: 3,
        maxLines: 5,
        maxLength: 500,
        textInputAction: TextInputAction.newline,
        style: TextStyle(color: p.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          labelText: sourceLabel,
          hintText: _japaneseToLocal
              ? '例：東京駅はどこですか？'
              : const LText(
                  'Örn. Tokyo İstasyonu nerede?',
                  'E.g. Where is Tokyo Station?',
                ).of(widget.lang),
          filled: true,
          fillColor: p.elevated,
          counterStyle: TextStyle(color: p.textMuted, fontSize: 11),
          labelStyle: TextStyle(color: p.textSecondary),
          hintStyle: TextStyle(color: p.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.accent, width: 1.5),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          key: const Key('offline-translator-error'),
          style: TextStyle(color: p.sunset, fontSize: 12),
        ),
      ],
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('offline-translator-submit'),
          onPressed:
              supported && _modelsReady == true && !_busy ? _translate : null,
          icon: _busy && _modelsReady == true
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 18),
          label: Text(
            const LText('Google ile çevir', 'Translate with Google')
                .of(widget.lang),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: p.border,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
      if (_result.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          key: const Key('offline-translator-result'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.accent.withValues(alpha: 0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      targetLabel,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('offline-translator-copy'),
                    onPressed: _copyResult,
                    visualDensity: VisualDensity.compact,
                    tooltip: const LText('Kopyala', 'Copy').of(widget.lang),
                    icon: Icon(Icons.copy_rounded, color: p.accent, size: 19),
                  ),
                ],
              ),
              Text(
                _result,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Image.asset(
                'assets/images/powered-by-google-translate.png',
                height: 16,
                alignment: Alignment.centerLeft,
                errorBuilder: (_, __, ___) => Text(
                  'Powered by Google Translate',
                  style: TextStyle(color: p.textMuted, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          const LText(
            'Otomatik çeviri hata yapabilir; sağlık ve acil durum ifadelerini doğrula.',
            'Automatic translation can make mistakes; verify medical and emergency phrases.',
          ).of(widget.lang),
          style: TextStyle(color: p.textMuted, fontSize: 11),
        ),
      ],
    ];
  }
}

class _TranslatorHeader extends StatelessWidget {
  const _TranslatorHeader({
    required this.palette,
    required this.lang,
    required this.isPremium,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final badgeColor = isPremium ? palette.matcha : palette.gold;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.translate_rounded, color: palette.accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                const LText('Cepte Çevirmen', 'Pocket Translator').of(lang),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                const LText(
                  'Metin cihazından çıkmaz',
                  'Your text never leaves your device',
                ).of(lang),
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPremium ? Icons.offline_bolt_rounded : Icons.lock_rounded,
                size: 14,
                color: badgeColor,
              ),
              const SizedBox(width: 4),
              Text(
                isPremium ? 'OFFLINE' : 'PREMIUM',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiumTranslatorLock extends StatelessWidget {
  const _PremiumTranslatorLock({required this.palette, required this.lang});

  final ViewerPalette palette;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('offline-translator-premium-lock'),
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.gold.withValues(alpha: 0.16),
            palette.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: palette.gold.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.gold.withValues(alpha: 0.17),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.workspace_premium_rounded,
                color: palette.gold, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  const LText(
                    'Premium ile çevrimdışı çeviri',
                    'Offline translation with Premium',
                  ).of(lang),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  const LText(
                    'Türkçe ve Japonca metinleri internetsiz çevir. Premium üyeliğin açıldığında çevirmen otomatik kullanıma hazır olur.',
                    'Translate Japanese and English text without internet. The translator unlocks automatically when Premium is active.',
                  ).of(lang),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionSelector extends StatelessWidget {
  const _DirectionSelector({
    required this.palette,
    required this.source,
    required this.target,
    required this.onSwap,
  });

  final ViewerPalette palette;
  final String source;
  final String target;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    Widget languagePill(String label) => Expanded(
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.elevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        );

    return Row(
      children: [
        languagePill(source),
        IconButton(
          key: const Key('offline-translator-swap'),
          onPressed: onSwap,
          tooltip: 'Swap languages',
          icon: Icon(Icons.swap_horiz_rounded, color: palette.accent),
        ),
        languagePill(target),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.palette,
    required this.icon,
    required this.text,
  });

  final ViewerPalette palette;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.gold.withValues(alpha: 0.26)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: palette.gold, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: palette.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    required this.palette,
    required this.lang,
    required this.busy,
    required this.onDownload,
  });

  final ViewerPalette palette;
  final AppLang lang;
  final bool busy;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.gold.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.download_for_offline_rounded,
                  color: palette.gold, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  const LText(
                    'İlk kullanım için iki dil paketi gerekir (yaklaşık 60 MB). Wi-Fi ile bir kez indir; sonra internet gerekmez.',
                    'Two language packs are needed the first time (about 60 MB). Download once over Wi-Fi; no internet is needed afterward.',
                  ).of(lang),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('offline-translator-download'),
            onPressed: onDownload,
            icon: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.gold,
                    ),
                  )
                : const Icon(Icons.wifi_rounded, size: 17),
            label: Text(
              busy
                  ? const LText('İndiriliyor…', 'Downloading…').of(lang)
                  : const LText(
                      'Dil paketlerini indir',
                      'Download language packs',
                    ).of(lang),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.gold,
              side: BorderSide(color: palette.gold.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
