import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/l10n.dart';
import 'core/router.dart';
import 'data/language_store.dart';
import 'env.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MissingEnvApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: JapanTripApp()));
}

class JapanTripApp extends ConsumerWidget {
  const JapanTripApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final lang = ref.watch(appLangProvider);
    // LanguageScope MaterialApp'in ÜSTÜNDE — böylece tüm pushed route'lar
    // (viewer alt ekranları) aktif dili miras alır.
    return LanguageScope(
      lang: lang,
      child: MaterialApp.router(
        title: 'Rotori',
        theme: AppTheme.dark,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        locale: Locale(lang.code),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}

/// SUPABASE_URL/ANON_KEY olmadan derlendiğinde hata mesajı gösterir.
class _MissingEnvApp extends StatelessWidget {
  const _MissingEnvApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  'SUPABASE_URL / SUPABASE_ANON_KEY eksik',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'flutter run \\\n'
                  '  --dart-define=SUPABASE_URL=https://xxx.supabase.co \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=eyJ...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
